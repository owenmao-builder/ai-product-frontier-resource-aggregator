import type {NewsItem, EventArticle} from '../types'

export function eventArticles(item:NewsItem): EventArticle[] {
  return item.event?.reports.flatMap(report => report.articles) ?? [{id:item.id,title:item.title_zh || item.title,url:item.url,source:item.source,siteID:item.site_id}]
}
export function matchesEvent(item:NewsItem, site:string, source:string, query:string): boolean {
  // Apply source and platform to the same member, but preserve the full event in the result.
  const articles = eventArticles(item).filter(article => (site === 'all' || article.siteID === site) && (source === 'all' || article.source === source))
  if (!articles.length) return false
  const text = query.trim().toLowerCase()
  return !text || [item.event?.title,item.title,item.title_zh,...articles.flatMap(article=>[article.title,article.source])].some(value=>value?.toLowerCase().includes(text))
}
export function eventIsRead(item:NewsItem, visited:Record<string,unknown>): boolean {
  return Boolean(item.event?.read || (item.event?.urls ?? [item.url]).some(url=>url in visited))
}
export function eventLabel(item:NewsItem): string {
  const event = item.event
  if (!event || event.articleCount < 2) return ''
  return (event.mediaCount >= 2 ? event.mediaCount + ' 家媒体关注 · ' : '') + event.articleCount + ' 篇合并' + (event.bonus > 0 ? ' · +' + event.bonus.toFixed(1) : '')
}
