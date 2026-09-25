import { useEffect, useMemo, useState } from 'react'
import { ArrowUpRight, Building2, CheckCircle2, Flame, RefreshCw, Search, Sparkles } from 'lucide-react'
import type { AIProduct, NewsItem, ProductBoard, ProductDiscovery } from '../types'
import catalog from '../../../data/products.json'
import { publicSourceURL } from '../lib/ratings'
import { isRecentMajorRelease, mergeProductCatalog, visibleProducts, withProductReporting } from '../lib/products'

type ProductFilter = 'all' | 'major' | 'hot'
const dateLabel = (value?: string) => value ? new Date(value).toLocaleString('zh-CN', {timeZone:'Asia/Shanghai',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit'}) : '尚未更新'

export function ProductsBoard({board, discovery, news = [], loading, onRefresh}: {board?: ProductBoard; discovery?:ProductDiscovery; news?:NewsItem[]; loading: boolean; onRefresh: () => void}) {
  const [filter, setFilter] = useState<ProductFilter>('all')
  const [query, setQuery] = useState('')
  const [category, setCategory] = useState('all')
  const [now, setNow] = useState(Date.now)
  useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now()), 60000)
    return () => window.clearInterval(timer)
  }, [])
  const source = useMemo(()=>board || withProductReporting(mergeProductCatalog(catalog as ProductBoard,discovery,now),news,now),[board,discovery,news,now])
  const products = useMemo(() => visibleProducts(source,now), [source,now])
  const majorCount = products.filter(product => isRecentMajorRelease(product,now)).length
  const hotCount = products.filter(product => product.signals?.length).length
  const categories = [...new Set(products.map(product => product.category))]
  const visible = products.filter(product => (filter !== 'major' || isRecentMajorRelease(product,now)) && (filter !== 'hot' || Boolean(product.signals?.length)) &&
    (category === 'all' || product.category === category) && [product.name, product.maker, product.summary, ...product.aliases].join(' ').toLowerCase().includes(query.trim().toLowerCase()))

  return <section aria-label="AI 产品栏目" className="space-y-6">
    <div className="rounded-2xl border border-primary-100 dark:border-primary-900 bg-gradient-to-br from-white via-primary-50/60 to-sky-50 dark:from-slate-800 dark:via-slate-800 dark:to-indigo-950 p-6 sm:p-7">
      <div className="flex items-start justify-between gap-6">
        <div>
          <div className="flex items-center gap-2 text-xs font-semibold tracking-widest text-primary-600 dark:text-primary-400"><Sparkles className="w-4 h-4" />AI 产品</div>
          <h2 className="text-2xl sm:text-3xl font-bold text-slate-900 dark:text-white mt-3">新发布与近期热门 AI 产品</h2>
          <p className="text-sm text-slate-600 dark:text-slate-300 mt-3 leading-relaxed">从 X/Twitter、媒体与开源社区发现新模型、新架构和热门产品，展开查看能力变化、讨论来源与使用入口。</p>
        </div>
        <button onClick={onRefresh} disabled={loading} aria-label="同步新产品与热度" className="shrink-0 rounded-xl border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-800 p-2.5 text-slate-600 dark:text-slate-300 hover:text-primary-600"><RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} /></button>
      </div>
      <div className="flex flex-wrap items-center gap-x-6 gap-y-2 mt-5 text-sm">
        <span className="inline-flex items-center gap-2 text-primary-700 dark:text-primary-300"><Building2 className="w-4 h-4" /><strong>{majorCount}</strong> 项大厂近 7 天上新</span>
        <span className="inline-flex items-center gap-2 text-orange-700 dark:text-orange-300"><Flame className="w-4 h-4" /><strong>{hotCount}</strong> 款近期热门</span>
        <span className="text-xs text-slate-500 dark:text-slate-400">近 7 天讨论 · 大厂上新按官方首发日筛选</span>
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
      <span>{source.discovery ? `发布同步 ${dateLabel(source.discovery.checkedAt)} · 新闻与产品同时更新` : '发布清单尚未自动同步，点击刷新'}</span>
    </div>
    {Object.values(source.errors || {}).length > 0 && <p role="status" className="text-sm rounded-xl bg-amber-50 dark:bg-amber-900/20 text-amber-800 dark:text-amber-300 p-3">{Object.values(source.errors || {}).join(' ')}</p>}

    {Boolean(source.discovery?.pending.length || source.discovery?.errors.length) && <details className="rounded-xl border border-amber-200 dark:border-amber-800 bg-amber-50/60 dark:bg-amber-950/20 p-4 text-sm">
      <summary className="cursor-pointer text-amber-800 dark:text-amber-300 font-medium">新闻中的发布线索 · {source.discovery?.pending.length || 0} 项待核验</summary>
      <p className="text-xs text-slate-500 mt-2">尚未取得匹配的官方公告或发布日期，暂不计入“大厂近 7 天上新”。已核实条目保留，来源恢复后继续核对。</p>
      {source.discovery?.pending.map(item=><div key={item.maker+item.name} className="mt-3 border-t border-amber-100 dark:border-amber-900 pt-3"><strong>{item.name}</strong><span className="text-xs text-slate-500 ml-2">{item.maker}</span><p className="text-xs text-slate-500 mt-1">{item.reason}</p>{item.officialURL&&<a href={item.officialURL} target="_blank" rel="noopener noreferrer" className="block text-xs text-primary-600 dark:text-primary-300 my-1">已找到的官方资料 ↗</a>}<a href={item.newsURL} target="_blank" rel="noopener noreferrer" className="text-xs text-primary-600 dark:text-primary-300">相关新闻 · {item.newsTitle} ↗</a></div>)}
      {source.discovery?.errors.length ? <p className="text-xs text-amber-700 dark:text-amber-400 mt-3">{source.discovery.errors.join('；')}</p> : null}
    </details>}

    <div className="grid md:grid-cols-2 xl:grid-cols-3 gap-4">
      {visible.map(product => <ProductCard key={product.id} product={product} />)}
    </div>
    {!visible.length && <div className="text-center rounded-2xl border border-dashed border-slate-300 dark:border-slate-600 p-12"><p className="text-slate-500">{filter === 'hot' ? '暂无符合条件的近期热度，刷新后再看看。' : '暂无符合条件的新发布或热门产品。'}</p><button onClick={()=>{setFilter('all');setCategory('all');setQuery('')}} className="text-primary-600 text-sm mt-3">查看全部产品</button></div>}

    <details className="text-xs text-slate-500 dark:text-slate-400 border-t border-slate-200 dark:border-slate-700 pt-4 leading-relaxed">
      <summary className="cursor-pointer font-medium">入选标准与覆盖范围</summary>
      <p className="mt-3">大厂上新只收录官方确认的具体模型、版本或新功能，按官方公告的首发日期筛选最近 7 个自然日（含今天），不使用抓取日期、文章更新时间或旧模型被再次报道的日期。较早发布或日期尚未核实的产品仍可凭近期热度进入“全部”和“近期热门”。</p>
      <p className="mt-2">近期热门收录最近 7 天在 X/Twitter、媒体或社区受到独立来源集中讨论的具体产品，也支持 Hugging Face 趋势榜、GitHub 本周新增至少 500 星、近 7 天 HN 至少 100 赞。按独立作者和媒体去重，不把转发重复计数；X 讨论优先显示。Hugging Face/GitHub/HN 榜单核对超过 24 小时失效，讨论以原文时间计算，不因刷新延长。</p>
      <p className="mt-2">每轮从已接入的来源识别产品并关联原文。社区讨论与官方发布分别标明，不把讨论时间当作发布日期；同款产品合并，不同版本与衍生产品分开。覆盖范围取决于接入的作者和信息源。</p>
    </details>
  </section>
}

function ProductCard({product}: {product: AIProduct}) {
  const hot = Boolean(product.signals?.length)
  const community=product.discoveryBasis==='community'
  const recentMajor=isRecentMajorRelease(product)
  const homepage=publicSourceURL(product.homepage) ? product.homepage : undefined
  const sourceURL=publicSourceURL(product.sourceURL) ? product.sourceURL : undefined
  return <article className="rounded-2xl border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 p-5 shadow-sm flex flex-col">
    <div className="flex items-start justify-between gap-3">
      <div className="min-w-0"><p className="text-xs text-slate-500 dark:text-slate-400 break-words">{product.maker} · {product.category}</p><h3 className="font-bold text-lg mt-1 text-slate-900 dark:text-white [overflow-wrap:anywhere]">{product.name}</h3></div>
      {homepage && <a aria-label={`${product.name} ${community ? '来源与使用入口' : '官网'}`} href={homepage} target="_blank" rel="noopener noreferrer" className="shrink-0 rounded-lg p-2 bg-slate-50 dark:bg-slate-700 text-slate-500 hover:text-primary-600"><ArrowUpRight className="w-4 h-4" /></a>}
    </div>
    {!community && product.releasedOn && <p className="text-xs font-medium text-primary-600 dark:text-primary-300 mt-3">官方发布 {product.releasedOn} · {product.releaseKind}</p>}
    {product.discoveredAutomatically && <p className="text-xs text-emerald-700 dark:text-emerald-400 mt-2" title={product.dateBasis}>{community ? '社区热点发现 · 首发日期待确认' : '由新闻自动同步 · 官方发布已核对'}</p>}
    <p className="text-sm text-slate-600 dark:text-slate-300 leading-relaxed mt-3">{product.summary}</p>
    <div className="flex flex-wrap gap-2 mt-4">
      {recentMajor && <span className="inline-flex items-center gap-1 text-xs rounded-md px-2 py-1 bg-primary-50 dark:bg-primary-900/30 text-primary-600 dark:text-primary-300"><CheckCircle2 className="w-3 h-3" />大厂上新</span>}
      {hot && <span className="inline-flex items-center gap-1 text-xs rounded-md px-2 py-1 bg-orange-50 dark:bg-orange-900/20 text-orange-700 dark:text-orange-300"><Flame className="w-3 h-3" />{product.signals?.[0].label}</span>}
      {product.repository && <span className="text-xs rounded-md px-2 py-1 bg-slate-100 dark:bg-slate-700 text-slate-500 dark:text-slate-300">开源项目</span>}
    </div>
    <details className="mt-4 border-t border-slate-100 dark:border-slate-700 pt-3 text-sm group">
      <summary className="cursor-pointer text-primary-600 dark:text-primary-300 font-medium">展开产品重点与热度依据</summary>
      <div className="space-y-3 mt-4 text-slate-600 dark:text-slate-300 leading-relaxed">
        <div><h4 className="font-semibold text-xs text-slate-900 dark:text-white mb-1">有什么不同</h4><p>{product.difference}</p></div>
        <div><h4 className="font-semibold text-xs text-slate-900 dark:text-white mb-1">怎么使用</h4><p>{product.access}</p></div>
        {product.signals?.map((signal,index) => <div key={`${signal.kind}-${index}`} className="p-3 rounded-lg bg-orange-50/70 dark:bg-orange-900/10 text-xs"><a href={signal.url} target="_blank" rel="noopener noreferrer" className="text-orange-700 dark:text-orange-300 font-semibold">热度依据 · {signal.label} ↗</a><p className="mt-1 break-words">{signal.title}</p><p className="mt-1 text-slate-400">{['x','community','coverage'].includes(signal.kind) ? '最近讨论' : '核对时间'} {dateLabel(signal.observedAt)}</p></div>)}
        {product.relatedNews?.length ? <div><h4 className="font-semibold text-xs text-slate-900 dark:text-white mb-1">相关讨论与报道</h4>{product.relatedNews.map(news=><a key={news.url} href={news.url} target="_blank" rel="noopener noreferrer" className="block text-xs text-primary-600 dark:text-primary-300 mb-2">{news.title} ↗</a>)}</div> : null}
        {sourceURL && <a href={sourceURL} target="_blank" rel="noopener noreferrer" className="inline-flex items-center gap-1 text-xs text-primary-600 dark:text-primary-300">{community ? '查看产品来源' : product.major ? '核对官方发布公告' : '核对官方资料'}<ArrowUpRight className="w-3 h-3" /></a>}
      </div>
    </details>
  </article>
}
