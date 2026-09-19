import { useEffect, useState } from 'react'
import { Newspaper, Sparkles } from 'lucide-react'
import { ProductsBoard } from './components/ProductsBoard'
import { categories, scoreOf } from './lib/ratings'
import { Header } from './components/Header'
import { StatsCards } from './components/StatsCards'
import { FilterBar } from './components/FilterBar'
import { NewsList } from './components/NewsList'
import { SourceModal } from './components/SourceModal'
import { ReadingHistoryModal } from './components/ReadingHistoryModal'
import { FavoritesModal } from './components/FavoritesModal'
import { SwitchingOverlay } from './components/SwitchingOverlay'
import { useTheme } from './hooks/useTheme'
import { useNewsData } from './hooks/useNewsData'
import { useVisitedLinks } from './hooks/useVisitedLinks'
import { useFavorites } from './hooks/useFavorites'
import { newsFreshness } from './lib/freshness'

function App() {
  const { theme, toggleTheme } = useTheme()
  const [showSourceModal, setShowSourceModal] = useState(false)
  const [showHistoryModal, setShowHistoryModal] = useState(false)
  const [showFavoritesModal, setShowFavoritesModal] = useState(false)
  const [section, setSection] = useState<'news' | 'products'>('news')
  useEffect(() => {
    if (!window.__AI_NATIVE__) return
    const listener = (event: Event) => {
      const section = (event as CustomEvent).detail.section
      if (section === 'news' || section === 'products') setSection(section)
    }
    window.addEventListener('ai-news-native', listener)
    return () => window.removeEventListener('ai-news-native', listener)
  }, [])
  const changeSection = (value: 'news' | 'products') => {
    setSection(value)
    if (window.__AI_NATIVE__) window.webkit?.messageHandlers.newsBridge.postMessage({action:'section',section:value})
  }
  const { visitedLinks, markAsVisited, clearAll } = useVisitedLinks()
  const { favorites, toggleFavorite, removeFavorite, clearAll: clearAllFavorites, isFavorite } = useFavorites()

  const {
    data,
    loading,
    error,
    filteredItems,
    siteStats,
    sourceStats,
    searchQuery,
    setSearchQuery,
    selectedSite,
    setSelectedSite,
    selectedSource,
    setSelectedSource,
    loadMore,
    hasMore,
    refresh,
    timeRange,
    setTimeRange,
    isSwitching,
    minScore, setMinScore, selectedCategory, setSelectedCategory, sortBy, setSortBy, scoring, aiError, lastChecked,
  } = useNewsData()
  const freshness = newsFreshness(data?.generated_at, data?.direct_sources, Date.now(), data?.collection)

  return (
    <div className="min-h-screen bg-slate-50 dark:bg-slate-900">
      <Header 
        theme={theme} 
        toggleTheme={toggleTheme} 
        onRefresh={refresh}
        loading={loading}
        generatedAt={data?.generated_at}
        windowHours={data?.window_hours}
        onShowSources={() => setShowSourceModal(true)}
        localCollection={data?.collection?.mode === 'local'}
        onShowHistory={() => setShowHistoryModal(true)}
        onShowFavorites={() => setShowFavoritesModal(true)}
        timeRange={timeRange}
        onTimeRangeChange={setTimeRange}
        isSwitching={isSwitching}
        productsView={section === 'products'}
      />

      <nav aria-label="栏目" className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 pt-5 flex gap-2">
        <button aria-pressed={section === 'news'} onClick={() => changeSection('news')} className={`flex items-center gap-2 px-4 py-2 rounded-xl text-sm font-medium ${section === 'news' ? 'bg-primary-600 text-white' : 'text-slate-600 dark:text-slate-300 hover:bg-slate-100 dark:hover:bg-slate-800'}`}><Newspaper className="w-4 h-4" />新闻</button>
        <button aria-pressed={section === 'products'} onClick={() => changeSection('products')} className={`flex items-center gap-2 px-4 py-2 rounded-xl text-sm font-medium ${section === 'products' ? 'bg-primary-600 text-white' : 'text-slate-600 dark:text-slate-300 hover:bg-slate-100 dark:hover:bg-slate-800'}`}><Sparkles className="w-4 h-4" />AI 产品</button>
      </nav>
      
      {isSwitching && <SwitchingOverlay timeRange={timeRange} />}
      
      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6 space-y-6">
        {section === 'products' ? <ProductsBoard board={data?.product_board} discovery={data?.product_discovery} news={data?.items} loading={loading} onRefresh={refresh} /> : <>
        <StatsCards
          totalItems={data?.total_items || 0}
          sourceCount={data?.source_count || 0}
          windowHours={data?.window_hours || 24}
          siteStats={siteStats}
          onShowSources={() => setShowSourceModal(true)}
        />
        <div className="flex flex-wrap items-center gap-x-5 gap-y-1 text-xs text-slate-500 dark:text-slate-400" role="status">
          <span>{freshness.directLabel}</span>
          <span className={freshness.isStale ? 'text-amber-700 dark:text-amber-400' : ''}>{freshness.snapshotLabel}</span>
          <button onClick={() => setShowSourceModal(true)} className="text-primary-600 dark:text-primary-400">各来源更新状态 →</button>
        </div>
        
        <FilterBar
          siteStats={siteStats}
          sourceStats={sourceStats}
          selectedSite={selectedSite}
          onSiteChange={setSelectedSite}
          selectedSource={selectedSource}
          onSourceChange={setSelectedSource}
          searchQuery={searchQuery}
          onSearchChange={setSearchQuery}
        />
        
        {<div className="flex flex-wrap items-center gap-3 text-sm">
          <div className="mr-auto text-slate-500 dark:text-slate-400">{scoring ? '正在读取原文并评估…' : `已评分 ${data?.items.filter(item => scoreOf(item) !== null).length || 0} 条 · 点击分数查看依据`}{lastChecked && <span className="ml-3">刚检查 {new Date(lastChecked).toLocaleTimeString('zh-CN', {hour:'2-digit',minute:'2-digit'})}</span>}</div>
          <label className="flex items-center gap-2">类型<select aria-label="新闻类型" value={selectedCategory} onChange={event => setSelectedCategory(event.target.value)} className="bg-white dark:bg-slate-800 border rounded-lg p-2 border-slate-200 dark:border-slate-700"><option value="all">全部类型</option>{Object.entries(categories).map(([key,label]) => <option key={key} value={key}>{label}</option>)}</select></label>
          <label className="flex items-center gap-2">分数<select value={minScore} onChange={event => setMinScore(Number(event.target.value))} className="bg-white dark:bg-slate-800 border rounded-lg p-2 border-slate-200 dark:border-slate-700"><option value={0}>全部资讯</option><option value={-1}>未评分</option><option value={7}>7 分及以上</option><option value={8}>8 分及以上</option></select></label>
          <span className="text-slate-500 dark:text-slate-400">北京时间</span>
          <label className="flex items-center gap-2" title="按关注分从高到低；模型升级、架构变化、速度、成本、热度和关注匹配按适用维度计算，证据状态不限制评分">排序<select value={sortBy} onChange={event => setSortBy(event.target.value as 'score'|'time')} className="bg-white dark:bg-slate-800 border rounded-lg p-2 border-slate-200 dark:border-slate-700"><option value="score">关注优先</option><option value="time">最新优先</option></select></label>
        </div>}
        {(error || aiError) && <div role="status" className="rounded-lg p-3 bg-amber-50 text-amber-800 dark:bg-amber-900/20 dark:text-amber-200 text-sm">{error || aiError}{data && ' · 已保留上次数据'}</div>}
        <NewsList
          items={filteredItems}
          loading={loading}
          error={data ? null : error}
          hasMore={hasMore}
          onLoadMore={loadMore}
          visitedLinks={visitedLinks}
          onVisit={markAsVisited}
          isFavorite={isFavorite}
          onToggleFavorite={toggleFavorite}
        />
        </>}
      </main>
      
      <footer className="border-t border-slate-200 dark:border-slate-700 py-6 mt-8">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <p className="text-center text-sm text-slate-500 dark:text-slate-400">
            {section === 'products' ? '大厂上新按官方发布日期筛选近 7 天 · 具体型号与版本 · 热度不等于质量' : '按你的标准直接给关注分 · 模型升级 / 架构变化 / 产品热度 / 关注匹配 · 证据状态单独展示'}
          </p>
        </div>
      </footer>

      <SourceModal
        collection={data?.collection}
        isOpen={showSourceModal}
        onClose={() => setShowSourceModal(false)}
        siteStats={siteStats}
        sourceCount={data?.source_count || 0}
        windowHours={data?.window_hours || 24}
        directSources={data?.direct_sources}
      />

      <ReadingHistoryModal
        isOpen={showHistoryModal}
        onClose={() => setShowHistoryModal(false)}
        visitedLinks={visitedLinks}
        onClearAll={clearAll}
      />

      <FavoritesModal
        isOpen={showFavoritesModal}
        onClose={() => setShowFavoritesModal(false)}
        favorites={favorites}
        onRemove={removeFavorite}
        onClearAll={clearAllFavorites}
      />
    </div>
  )
}

export default App
