import type {NewsEvent, EventReport, CoverageSignal} from '../types'
import {publicSourceURL} from '../lib/ratings'

export function CoverageOverview({coverage}:{coverage:CoverageSignal}) {
  return <div className="mb-4 space-y-2 rounded-lg bg-amber-50 dark:bg-amber-900/20 p-3">
    <strong className="text-amber-700 dark:text-amber-300">{coverage.sourceCount} 家集中报道</strong>
    <p className="text-xs text-slate-500">报道来源：{coverage.sourceNames.join('、')}</p>
  </div>
}

export function EventCoverage({event,onVisit}:{event:NewsEvent;onVisit?:(url:string,title?:string)=>void}) {
  const kinds:Record<string,string> = {media:'媒体',official:'官方',community:'作者/社区',aggregator:'聚合平台'}
  const reportCard = (report:EventReport) => <div key={report.id} className="rounded-lg bg-slate-50 dark:bg-slate-800 p-3 space-y-2">
    <div className="flex gap-2 items-baseline flex-wrap"><strong className="text-slate-900 dark:text-white">{report.name}</strong><span className="text-xs text-slate-500">{kinds[report.kind] || '来源'}</span>{event.coverage?.sourceIDs.includes(report.id) && <span className="text-xs text-amber-700 dark:text-amber-300">计入热度</span>}<span className="ml-auto text-xs text-slate-500">{report.basis}</span></div>
    <div className="text-xs font-medium text-amber-700 dark:text-amber-300">{report.focus.join(' · ')}</div>
    <ul className="list-disc pl-5 space-y-1">{report.points.map((point,index)=><li key={index}>{point}</li>)}</ul>
    {report.articles.filter(article=>publicSourceURL(article.url)).map(article=><a key={article.id} href={article.url} target="_blank" rel="noopener noreferrer" onClick={()=>onVisit?.(article.url,article.title)} className="block text-xs text-primary-600 dark:text-primary-300">原文 ↗ {article.title}</a>)}
  </div>
  return <div className="mb-4 space-y-4">
    <strong className="text-slate-900 dark:text-white">核心分析</strong>
    <div className="space-y-3">{event.insights.map((insight,index)=><div key={index}><strong className="text-primary-700 dark:text-primary-300">{insight.title}</strong><p className="mt-1">{insight.text}</p></div>)}</div>
    <strong className="block text-slate-900 dark:text-white">各家关注点</strong>
    <div className="grid gap-3 md:grid-cols-2">{event.reports.slice(0,4).map(reportCard)}</div>
    {event.reports.length>4 && <details><summary className="cursor-pointer text-primary-600 dark:text-primary-300">其余 {event.reports.length-4} 家来源</summary><div className="mt-3 grid gap-3 md:grid-cols-2">{event.reports.slice(4).map(reportCard)}</div></details>}
    <p className="text-xs text-slate-500">根据各家标题、摘录或已有分析归纳；报道数量表示关注热度。</p>
  </div>
}
