interface DatedNews {
  published_at: string | null
  first_seen_at: string
}

export function newsTime(item: DatedNews, now = Date.now()) {
  const published = Date.parse(item.published_at || '')
  const collected = Date.parse(item.first_seen_at)
  // Keep this rule aligned with NewsItem.newsTime in macos/Models.swift.
  const afterCollection = Number.isFinite(collected) && published - collected > 5 * 60_000
  if (Number.isFinite(published) && published <= now && !afterCollection) {
    return { timestamp: published, isCollection: false, explanation: '发布时间，按本机时区显示。' }
  }
  const reason = afterCollection ? '来源发布时间晚于收录时间' : Number.isFinite(published) ? '来源发布时间在未来' : '来源未提供有效发布时间'
  if (Number.isFinite(collected) && collected <= now) {
    return { timestamp: collected, isCollection: true, explanation: `${reason}，暂显示收录时间；不代表发布时间。` }
  }
  return { timestamp: null, isCollection: false, explanation: '发布时间和收录时间均缺失或异常。' }
}
