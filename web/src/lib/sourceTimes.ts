import { xinzhiyuanPublishedAt } from '../../../src/utils/xinzhiyuan-time'
import type { NewsData, SourcePublication } from '../types'
import { formatBeijingTime } from './newsTime'

const verifiedTimes = new Map<string, SourcePublication>()

export async function resolveSourceTimes(data: NewsData, fetcher: typeof fetch = fetch, now = Date.now()): Promise<NewsData> {
  const requested = new Map<number, string>()
  const today = formatBeijingTime(now).slice(0, 10)
  for (const item of data.items) {
    if (item.site_id !== 'xinzhiyuan') continue
    if (![item.published_at, item.first_seen_at].some(date => formatBeijingTime(Date.parse(date || '')).slice(0, 10) === today)) continue
    const known = verifiedTimes.get(item.url) ?? item.source_publication
    if (known?.sourceURL === item.url && Date.parse(known.publishedAt) <= now && now - Date.parse(known.verifiedAt) >= 0 && now - Date.parse(known.verifiedAt) < 86_400_000) continue
    try {
      const url = new URL(item.url)
      const raw = url.searchParams.get('id') || ''
      if (url.origin !== 'https://aiera.com.cn' || url.pathname !== '/asi-post.html' || !/^\d+$/.test(raw)) continue
      const id = Number(raw)
      if (Number.isSafeInteger(id) && id > 0) requested.set(id, item.url)
    } catch { continue }
    if (requested.size === 100) break
  }
  if (requested.size) {
    const params = new URLSearchParams({ include: [...requested.keys()].sort((a,b) => a-b).join(','), per_page: '100', _fields: 'id,date,date_gmt,link' })
    const controller = new AbortController()
    const timeout = setTimeout(() => controller.abort(), 15_000)
    try {
      const response = await fetcher(`https://aiera.com.cn/wp-json/wp/v2/posts?${params}`, { signal: controller.signal })
      if (response.ok) {
        const text = await response.text()
        if (text.length <= 1_000_000) {
          const posts = JSON.parse(text)
          if (Array.isArray(posts)) for (const post of posts) {
            if (!post || requested.get(post.id) !== post.link || typeof post.link !== 'string') continue
            const published = xinzhiyuanPublishedAt(post)
            if (!published || published.getTime() > now) continue
            verifiedTimes.set(post.link, { publishedAt: published.toISOString(), verifiedAt: new Date(now).toISOString(), sourceURL: post.link })
          }
        }
      }
    } catch { /* Keep source times already verified during this browser session. */ }
    finally { clearTimeout(timeout) }
  }
  return { ...data, items: data.items.map(item => ({ ...item, source_publication: verifiedTimes.get(item.url) ?? item.source_publication })) }
}
