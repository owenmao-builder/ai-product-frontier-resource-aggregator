import { useState } from 'react'
import { ExternalLink, Clock, BadgeCheck, Star, ChevronDown } from 'lucide-react'
import type { NewsItem } from '../types'
import { SourceBadge } from './SourceBadge'
import { formatDateTime } from '../utils/formatDate'
import { ratingFor, scoreOf, evidenceFor, categories, dimensionNames, publicSourceURL } from '../lib/ratings'
import { Analytics } from '../utils/analytics'
import { newsTime, formatBeijingTime } from '../lib/newsTime'

interface NewsCardProps {
  item: NewsItem
  index: number
  isVisited?: boolean
  isFavorite?: boolean
  onVisit?: (url: string, title?: string) => void
  onToggleFavorite?: (url: string, title: string) => void
}

export function NewsCard({ item, index, isVisited = false, isFavorite = false, onVisit, onToggleFavorite }: NewsCardProps) {
  const [expanded, setExpanded] = useState(false)
  const score = ratingFor(item)
  const value = scoreOf(item)
  const displayTitle = ((value ?? -1) >= 7 && score.chineseTitle) || item.title_zh || item.title_en || item.title_bilingual || item.title
  const evidence = evidenceFor(item)
  const time = newsTime(item)
  return (
    <article className={`card card-hover p-4 animate-slide-up group relative transition-all duration-300 ${isVisited ? 'visited-card' : ''}`} style={{ animationDelay: `${Math.min(index * 20, 200)}ms` }}>
      <div className="flex items-start gap-4">
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 mb-2 flex-wrap">
            <SourceBadge siteId={item.site_id} siteName={item.site_name} />
            <span className="text-xs truncate max-w-[240px] text-slate-500 dark:text-slate-400">{item.source}</span>
            {isVisited && <span className="inline-flex items-center gap-0.5 text-emerald-600 dark:text-emerald-400"><BadgeCheck className="w-3.5 h-3.5"/><span className="text-xs">已读</span></span>}
          </div>
          <a href={item.url} target="_blank" rel="noopener noreferrer" onClick={() => { Analytics.trackNewsClick(displayTitle, item.source, item.site_id); onVisit?.(item.url, displayTitle) }} className="block text-base font-medium leading-relaxed text-slate-900 dark:text-white hover:text-primary-600 dark:hover:text-primary-400">
            {displayTitle}<ExternalLink className="inline-block w-3.5 h-3.5 ml-2 text-slate-400"/>
          </a>
          <div className="flex items-center gap-3 mt-3 text-xs text-slate-500 dark:text-slate-400 flex-wrap">
            <span className="flex items-center gap-1" title={time.explanation}><Clock className="w-3.5 h-3.5"/>{time.isCollection ? '收录 ' : ''}{formatBeijingTime(time.timestamp)}</span>
            {item.priority?.reasons.slice(0,2).map(reason => <span key={reason} title={`排序依据：${item.priority?.reasons.join('；')}${item.priority?.provisional ? '；升级幅度待原文核验，不代表已经取得证据评分。' : ''}`} className="rounded px-1.5 py-0.5 bg-amber-50 text-amber-700 dark:bg-amber-900/20 dark:text-amber-300">{reason}</span>)}
            {[categories[score.category || "other"], ...score.tags].slice(0,3).map((tag,i) => <span key={`${tag}-${i}`} className="rounded px-1.5 py-0.5 bg-primary-50 text-primary-600 dark:bg-primary-900/20 dark:text-primary-300">{tag}</span>)}
          </div>
          {(value ?? -1) >= 7 && <button onClick={() => setExpanded(!expanded)} className="mt-3 text-xs font-medium text-primary-600 dark:text-primary-300">{expanded ? '收起重点 ↑' : '展开重点 ↓'}</button>}
        </div>
        <div className="flex items-center gap-3 flex-shrink-0">
          {score && <button onClick={() => setExpanded(!expanded)} aria-expanded={expanded} aria-label={`${value?.toFixed(1) || "待评估"}，证据 ${evidence.label}，查看评估依据`} title={`证据 ${evidence.label}：${evidence.explanation}`} className={`w-16 rounded-xl px-1 py-2 transition-colors ${(value ?? -1)>=7 ? 'bg-primary-50 text-primary-700 dark:bg-primary-900/30 dark:text-primary-300' : 'bg-slate-100 text-slate-500 dark:bg-slate-700 dark:text-slate-300'}`}>
            <span className="block text-2xl font-bold tabular-nums leading-7">{value?.toFixed(1) || "—"}</span>
            <span className="flex items-center justify-center gap-0.5 text-[11px] mt-0.5">{evidence.label}<ChevronDown className={`w-3 h-3 ${expanded ? 'rotate-180' : ''}`}/></span>
          </button>}
          <button onClick={() => onToggleFavorite?.(item.url, displayTitle)} className={`p-1.5 rounded-lg transition-all ${isFavorite ? 'text-amber-500 bg-amber-50 dark:bg-amber-900/20' : 'text-slate-400 hover:text-amber-500'}`} aria-label={isFavorite ? '取消收藏' : '收藏'}>
            <Star className={`w-4 h-4 ${isFavorite ? 'fill-current' : ''}`}/>
          </button>
        </div>
      </div>
      {expanded && score && <div className="mt-4 border-t border-slate-100 dark:border-slate-700 pt-3 text-sm leading-relaxed text-slate-600 dark:text-slate-300">
        {(value ?? -1) >= 7 && <div className="mb-4">
          <strong className="text-slate-900 dark:text-white">新闻重点</strong>
          {score.highlights?.length ? <ul className="mt-2 space-y-1.5 list-disc pl-5">{score.highlights.map((point,i) => <li key={i}>{point}</li>)}</ul> : <p className="mt-2">中文重点尚未补充，可先查看已有依据。</p>}
          {score.release && <p className="mt-3 text-primary-600 dark:text-primary-300">发布优先 +1.0 · {score.release.reason}</p>}
        </div>}
        <details open={(value ?? -1) < 7 ? true : undefined}>
        <summary className="cursor-pointer text-xs text-slate-500">评分依据与来源</summary>
        <p className="mt-2 mb-2 text-xs text-slate-500 dark:text-slate-400">证据 {evidence.label} · {evidence.explanation}</p>
        <strong className="text-slate-900 dark:text-white">{value === null ? '待评估原因' : '评估依据'}</strong><p className="mt-1">{score.reason}</p>
        {score.dimensions?.map(d => <p key={d.key} className="mt-2 text-xs"><strong>{dimensionNames[d.key]} {d.value}/5</strong> · {d.reason}</p>)}
        {score.comparison && <p className="mt-3"><strong>相对变化：</strong>{score.comparison}</p>}
        {score.sources?.filter(source => publicSourceURL(source.url)).map((source,i) => <a key={`${source.url}-${i}`} href={source.url} target="_blank" rel="noopener noreferrer" className="block mt-2 text-primary-600 dark:text-primary-300">依据 · {source.title} ↗</a>)}
        {Boolean(score.gaps?.length) && <p className="mt-3 text-xs text-slate-500">待确认：{score.gaps?.join('；')}</p>}
        <div className="text-xs mt-2 text-slate-400">{score.model || '按标题暂分类型'}{score.assessedAt && ` · ${formatDateTime(score.assessedAt)}`}</div>
        </details>
      </div>}
    </article>
  )
}
