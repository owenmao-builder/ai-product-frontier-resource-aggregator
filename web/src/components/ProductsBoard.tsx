import { useEffect, useMemo, useState } from 'react'
import { ArrowUpRight, Building2, CheckCircle2, Flame, RefreshCw, Search, Sparkles } from 'lucide-react'
import type { AIProduct, ProductBoard } from '../types'
import catalog from '../../../data/products.json'

type ProductFilter = 'all' | 'major' | 'hot'
const dateLabel = (value?: string) => value ? new Date(value).toLocaleString('zh-CN', {month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit'}) : '尚未更新'

export function isRecentRelease(product: AIProduct, now = Date.now()) {
  if (!product.releasedOn || !/^\d{4}-\d{2}-\d{2}$/.test(product.releasedOn) || !['新模型','新版本','新功能','新工具','新架构'].includes(product.releaseKind || '')) return false
  const [year, month, day] = product.releasedOn.split('-').map(Number)
  const release = new Date(year, month - 1, day)
  if (release.getFullYear() !== year || release.getMonth() !== month - 1 || release.getDate() !== day) return false
  const start = new Date(now)
  start.setHours(0, 0, 0, 0)
  start.setDate(start.getDate() - 6)
  return release.getTime() >= start.getTime() && release.getTime() <= now
}

export function ProductsBoard({board, loading, onRefresh}: {board?: ProductBoard; loading: boolean; onRefresh: () => void}) {
  const [filter, setFilter] = useState<ProductFilter>('major')
  const [query, setQuery] = useState('')
  const [category, setCategory] = useState('all')
  const [now, setNow] = useState(Date.now)
  useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now()), 60000)
    return () => window.clearInterval(timer)
  }, [])
  const source: ProductBoard = board || catalog
  const products = useMemo(() => source.items.filter(product => !product.major || isRecentRelease(product, now)).map(product => ({...product, signals: (product.signals || []).filter(signal => {
    const age = now - Date.parse(signal.observedAt)
    return age >= 0 && age <= 86400000
  })})).filter(product => product.major || product.signals.length > 0).sort((a,b) =>
    Number(b.major) - Number(a.major) || Number(b.releaseKind === '新模型') - Number(a.releaseKind === '新模型') ||
    (b.releasedOn || '').localeCompare(a.releasedOn || '') || a.name.localeCompare(b.name)), [source, now])
  const majorCount = products.filter(product => product.major).length
  const hotCount = products.filter(product => product.signals.length).length
  const categories = [...new Set(products.map(product => product.category))]
  const visible = products.filter(product => (filter !== 'major' || product.major) && (filter !== 'hot' || product.signals.length > 0) &&
    (category === 'all' || product.category === category) && [product.name, product.maker, product.summary, ...product.aliases].join(' ').toLowerCase().includes(query.trim().toLowerCase()))

  return <section aria-label="AI 产品栏目" className="space-y-6">
    <div className="rounded-2xl border border-primary-100 dark:border-primary-900 bg-gradient-to-br from-white via-primary-50/60 to-sky-50 dark:from-slate-800 dark:via-slate-800 dark:to-indigo-950 p-6 sm:p-7">
      <div className="flex items-start justify-between gap-6">
        <div>
          <div className="flex items-center gap-2 text-xs font-semibold tracking-widest text-primary-600 dark:text-primary-400"><Sparkles className="w-4 h-4" />AI 产品</div>
          <h2 className="text-2xl sm:text-3xl font-bold text-slate-900 dark:text-white mt-3">近 7 天，大厂又发布了什么？</h2>
          <p className="text-sm text-slate-600 dark:text-slate-300 mt-3 leading-relaxed">直接看具体模型、版本和新功能，标明官方发布日期、这次新增的能力，以及近期热门工具。</p>
        </div>
        <button onClick={onRefresh} disabled={loading} aria-label="刷新产品热度" className="shrink-0 rounded-xl border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-800 p-2.5 text-slate-600 dark:text-slate-300 hover:text-primary-600"><RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} /></button>
      </div>
      <div className="flex flex-wrap items-center gap-x-6 gap-y-2 mt-5 text-sm">
        <span className="inline-flex items-center gap-2 text-primary-700 dark:text-primary-300"><Building2 className="w-4 h-4" /><strong>{majorCount}</strong> 项大厂近 7 天上新</span>
        <span className="inline-flex items-center gap-2 text-orange-700 dark:text-orange-300"><Flame className="w-4 h-4" /><strong>{hotCount}</strong> 款近期热门</span>
        <span className="text-xs text-slate-500 dark:text-slate-400">含今天 · 按官方首发日筛选 · 资料核对 {source.verifiedAt.slice(0,10)}</span>
      </div>
    </div>

    <div className="flex flex-wrap items-center gap-3">
      <div className="inline-flex p-1 rounded-xl bg-slate-100 dark:bg-slate-800" role="group" aria-label="产品筛选">
        {([['all','全部',products.length],['major','大厂上新 · 7 天',majorCount],['hot','近期热门',hotCount]] as const).map(([value,label,count]) => <button key={value} aria-pressed={filter === value} onClick={() => setFilter(value)} className={`px-4 py-2 rounded-lg text-sm ${filter === value ? 'bg-white dark:bg-slate-700 text-primary-700 dark:text-primary-300 font-semibold shadow-sm' : 'text-slate-500 dark:text-slate-400'}`}>{label}<span className="ml-2 text-xs opacity-70">{count}</span></button>)}
      </div>
      <label className="relative flex-1 min-w-[190px]"><Search className="absolute left-3 top-3 w-4 h-4 text-slate-400" /><input aria-label="搜索 AI 产品" placeholder="搜索模型、版本或用途" value={query} onChange={event=>setQuery(event.target.value)} className="input w-full pl-10 py-2.5 text-sm rounded-xl" /></label>
      <select aria-label="产品用途" value={category} onChange={event=>setCategory(event.target.value)} className="input w-auto min-w-[130px] text-sm py-2.5 rounded-xl"><option value="all">全部用途</option>{categories.map(category=><option key={category}>{category}</option>)}</select>
    </div>

    <div className="flex flex-wrap justify-between gap-2 text-xs text-slate-500 dark:text-slate-400">
      <span>GitHub 周榜 · {dateLabel(source.githubFetchedAt)}　 /　HN 近 7 天 · {dateLabel(source.hnFetchedAt)}</span>
      <span>热度随「立即拉取」更新</span>
    </div>
    {Object.values(source.errors || {}).length > 0 && <p role="status" className="text-sm rounded-xl bg-amber-50 dark:bg-amber-900/20 text-amber-800 dark:text-amber-300 p-3">{Object.values(source.errors || {}).join(' ')}</p>}

    <div className="grid md:grid-cols-2 xl:grid-cols-3 gap-4">
      {visible.map(product => <ProductCard key={product.id} product={product} />)}
    </div>
    {!visible.length && <div className="text-center rounded-2xl border border-dashed border-slate-300 dark:border-slate-600 p-12"><p className="text-slate-500">{filter === 'hot' ? '暂无符合条件的近期热度，刷新后再看看。' : '暂无符合条件的近 7 天上新。'}</p><button onClick={()=>{setFilter('all');setCategory('all');setQuery('')}} className="text-primary-600 text-sm mt-3">查看全部产品</button></div>}

    <details className="text-xs text-slate-500 dark:text-slate-400 border-t border-slate-200 dark:border-slate-700 pt-4 leading-relaxed">
      <summary className="cursor-pointer font-medium">入选标准与覆盖范围</summary>
      <p className="mt-3">大厂上新只收录官方确认的具体模型、版本或新功能，按官方公告的首发日期筛选最近 7 个自然日（含今天），不使用抓取日期、文章更新时间或旧模型被再次报道的日期。超过时限、只有品牌名或日期未核实的条目不展示；新模型优先排列。</p>
      <p className="mt-2">近期热门满足任一条件：进入 GitHub 周趋势榜且本周新增至少 500 星，或最近 7 天相关 HN 话题达到 100 赞。大厂条目在此也必须满足发布时限；其他工具可以较早发布、最近走红。热度不等于质量，不与新闻评分混算，超过 24 小时未更新的热度停止计入。</p>
      <p className="mt-2">发布条目按官方资料核验维护，覆盖不等于全网；热度与今日相关消息随刷新更新，过期条目自动移出。</p>
    </details>
  </section>
}

function ProductCard({product}: {product: AIProduct}) {
  const hot = Boolean(product.signals?.length)
  return <article className="rounded-2xl border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 p-5 shadow-sm flex flex-col">
    <div className="flex items-start justify-between gap-3">
      <div><p className="text-xs text-slate-500 dark:text-slate-400">{product.maker} · {product.category}</p><h3 className="font-bold text-lg mt-1 text-slate-900 dark:text-white">{product.name}</h3></div>
      <a aria-label={`${product.name} 官网`} href={product.homepage} target="_blank" rel="noopener noreferrer" className="rounded-lg p-2 bg-slate-50 dark:bg-slate-700 text-slate-500 hover:text-primary-600"><ArrowUpRight className="w-4 h-4" /></a>
    </div>
    {product.releasedOn && <p className="text-xs font-medium text-primary-600 dark:text-primary-300 mt-3">官方发布 {product.releasedOn} · {product.releaseKind}</p>}
    <p className="text-sm text-slate-600 dark:text-slate-300 leading-relaxed mt-3">{product.summary}</p>
    <div className="flex flex-wrap gap-2 mt-4">
      {product.major && <span className="inline-flex items-center gap-1 text-xs rounded-md px-2 py-1 bg-primary-50 dark:bg-primary-900/30 text-primary-600 dark:text-primary-300"><CheckCircle2 className="w-3 h-3" />大厂上新</span>}
      {hot && <span className="inline-flex items-center gap-1 text-xs rounded-md px-2 py-1 bg-orange-50 dark:bg-orange-900/20 text-orange-700 dark:text-orange-300"><Flame className="w-3 h-3" />{product.signals?.[0].label}</span>}
      {product.repository && <span className="text-xs rounded-md px-2 py-1 bg-slate-100 dark:bg-slate-700 text-slate-500 dark:text-slate-300">开源工具</span>}
    </div>
    <details className="mt-4 border-t border-slate-100 dark:border-slate-700 pt-3 text-sm group">
      <summary className="cursor-pointer text-primary-600 dark:text-primary-300 font-medium">展开产品重点与热度依据</summary>
      <div className="space-y-3 mt-4 text-slate-600 dark:text-slate-300 leading-relaxed">
        <div><h4 className="font-semibold text-xs text-slate-900 dark:text-white mb-1">有什么不同</h4><p>{product.difference}</p></div>
        <div><h4 className="font-semibold text-xs text-slate-900 dark:text-white mb-1">怎么使用</h4><p>{product.access}</p></div>
        {product.signals?.map((signal,index) => <div key={`${signal.kind}-${index}`} className="p-3 rounded-lg bg-orange-50/70 dark:bg-orange-900/10 text-xs"><a href={signal.url} target="_blank" rel="noopener noreferrer" className="text-orange-700 dark:text-orange-300 font-semibold">热度依据 · {signal.label} ↗</a><p className="mt-1 break-words">{signal.title}</p><p className="mt-1 text-slate-400">核对时间 {dateLabel(signal.observedAt)}</p></div>)}
        {product.relatedNews?.length ? <div><h4 className="font-semibold text-xs text-slate-900 dark:text-white mb-1">今日相关消息</h4>{product.relatedNews.map(news=><a key={news.url} href={news.url} target="_blank" rel="noopener noreferrer" className="block text-xs text-primary-600 dark:text-primary-300 mb-2">{news.title} ↗</a>)}</div> : null}
        <a href={product.sourceURL} target="_blank" rel="noopener noreferrer" className="inline-flex items-center gap-1 text-xs text-primary-600 dark:text-primary-300">{product.major ? '核对官方发布公告' : '核对官方资料'}<ArrowUpRight className="w-3 h-3" /></a>
      </div>
    </details>
  </article>
}
