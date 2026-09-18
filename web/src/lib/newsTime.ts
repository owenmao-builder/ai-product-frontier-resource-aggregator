import type { SourcePublication } from '../types'

interface DatedNews {
  published_at: string | null
  first_seen_at: string
  url?: string
  site_id?: string
  source_publication?: SourcePublication
}

export function newsTime(item: DatedNews, now = Date.now()) {
  const source = item.source_publication
  if (source && source.sourceURL === item.url && Date.parse(source.publishedAt) <= now && Date.parse(source.verifiedAt) <= now) {
    return { timestamp: Date.parse(source.publishedAt), isCollection: false, explanation: '已核对原站发布时间，按北京时间（UTC+8）显示。' }
  }
  const published = Date.parse(item.published_at || '')
  const collected = Date.parse(item.first_seen_at)
  const collectionProxy = ['aibase', 'tophub'].includes(item.site_id || '') && Number.isFinite(published) && published === collected
  // Keep this rule aligned with NewsItem.newsTime in macos/Models.swift.
  const afterCollection = Number.isFinite(collected) && published - collected > 5 * 60_000
  if (Number.isFinite(published) && published <= now && !afterCollection && !collectionProxy) {
    return { timestamp: published, isCollection: false, explanation: '信息源发布时间，按北京时间（UTC+8）显示。' }
  }
  const reason = collectionProxy ? '来源仅提供相对时间，尚无准确发布时间' : afterCollection ? '来源发布时间晚于收录时间' : Number.isFinite(published) ? '来源发布时间在未来' : '来源未提供有效发布时间'
  if (Number.isFinite(collected) && collected <= now) {
    return { timestamp: collected, isCollection: true, explanation: `${reason}，暂显示收录时间；不代表发布时间。` }
  }
  return { timestamp: null, isCollection: false, explanation: '发布时间和收录时间均缺失或异常。' }
}

export function compareNewsTimes(first: DatedNews, second: DatedNews, now = Date.now()): number {
  const a = newsTime(first, now), b = newsTime(second, now)
  const aPublished = a.timestamp !== null && !a.isCollection
  const bPublished = b.timestamp !== null && !b.isCollection
  if (aPublished !== bPublished) return aPublished ? -1 : 1
  return (b.timestamp ?? 0) - (a.timestamp ?? 0)
}

const beijingFormatter = new Intl.DateTimeFormat('zh-CN', {
  timeZone: 'Asia/Shanghai', year: 'numeric', month: '2-digit', day: '2-digit',
  hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
})

export function formatBeijingTime(timestamp: number | null): string {
  if (timestamp === null || !Number.isFinite(timestamp)) return '未知时间'
  const parts = Object.fromEntries(beijingFormatter.formatToParts(timestamp).map(part => [part.type, part.value]))
  return `${parts.year}-${parts.month}-${parts.day} ${parts.hour}:${parts.minute}`
}
