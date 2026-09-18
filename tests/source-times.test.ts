import { describe, expect, it, vi } from 'vitest'
import type { NewsData, NewsItem } from '../web/src/types'
import { resolveSourceTimes } from '../web/src/lib/sourceTimes'
import { formatBeijingTime, newsTime, compareNewsTimes } from '../web/src/lib/newsTime'
import { parseRelativeTimeZh } from '../src/utils/date'

const now = Date.parse('2026-09-18T06:00:00Z')
const item = (id: number): NewsItem => ({ id: String(id), site_id: 'xinzhiyuan', site_name: '新智元', source: '新智元', title: '时间测试', url: `https://aiera.com.cn/asi-post.html?id=${id}`, published_at: '2026-09-18T08:03:39Z', first_seen_at: '2026-09-18T02:06:03Z', last_seen_at: '2026-09-18T02:06:03Z', title_original: '', title_en: null, title_zh: null, title_bilingual: '' })
const snapshot = (items: NewsItem[]) => ({ items } as NewsData)
const response = (data: unknown) => new Response(JSON.stringify(data), { status: 200 })

describe('verified source publication times', () => {
  it('does not present a scraped just-now hint as exact publication time', () => {
    const approximate = { ...item(300), site_id: 'aibase', published_at: '2026-09-18T02:06:03Z' }
    expect(newsTime(approximate, now).isCollection).toBe(true)
    expect(newsTime({ ...approximate, site_id: 'tophub' }, now).isCollection).toBe(true)
    expect(newsTime({ ...approximate, site_id: 'directrss' }, now).isCollection).toBe(false)
    expect(parseRelativeTimeZh('刚刚', new Date(now))).toBeNull()
    expect(parseRelativeTimeZh('刚刚，Claude Code大重构！', new Date(now))).toBeNull()
  })
  it('reads real source time, preserves input and rating identity, reuses cache after refresh', async () => {
    const source = item(114307)
    const fetcher = vi.fn<typeof fetch>().mockResolvedValue(response([{ id: 114307, date: '2026-09-18T08:03:39', date_gmt: '2026-09-18T00:03:39', link: source.url }]))
    const data = await resolveSourceTimes(snapshot([source]), fetcher, now)
    expect(fetcher).toHaveBeenCalledTimes(1)
    expect(newsTime(data.items[0], now)).toMatchObject({ timestamp: Date.parse('2026-09-18T00:03:39Z'), isCollection: false })
    expect(data.items[0].published_at).toBe(source.published_at)
    expect(source.source_publication).toBeUndefined()
    expect(compareNewsTimes(data.items[0], source, now)).toBeLessThan(0)
    expect(compareNewsTimes(source, data.items[0], now)).toBeGreaterThan(0)
    const next = await resolveSourceTimes(snapshot([source]), fetcher, now + 1000)
    expect(fetcher).toHaveBeenCalledTimes(1)
    expect(next.items[0].source_publication).toEqual(data.items[0].source_publication)
    // A later outage must not replace verified publication with collection time.
    fetcher.mockRejectedValue(new Error('offline'))
    const nextDay = { ...source, first_seen_at: '2026-09-19T02:00:00Z' }
    const stale = await resolveSourceTimes(snapshot([nextDay]), fetcher, now + 86_400_001)
    expect(newsTime(stale.items[0], now + 86_400_001).isCollection).toBe(false)
  })

  it('rejects mismatched URLs and future publications', async () => {
    const sources = [item(200), item(201)]
    const fetcher = vi.fn<typeof fetch>().mockResolvedValue(response([
      { id: 200, date: '2026-09-18T08:03:39', date_gmt: '2026-09-18T00:03:39', link: 'https://example.com/wrong' },
      { id: 201, date: '2026-09-18T16:03:39', date_gmt: '2026-09-18T08:03:39', link: sources[1].url },
    ]))
    const data = await resolveSourceTimes(snapshot(sources), fetcher, now)
    expect(data.items.every(row => row.source_publication === undefined)).toBe(true)
  })

  it('does not fetch historical articles or unrelated hosts', async () => {
    const yesterday = { ...item(202), published_at: '2026-09-17T00:00:00Z', first_seen_at: '2026-09-17T02:00:00Z' }
    const unrelated = { ...item(203), url: 'https://aiera.com.cn.evil.example/asi-post.html?id=203' }
    const fetcher = vi.fn<typeof fetch>()
    await resolveSourceTimes(snapshot([yesterday, unrelated]), fetcher, now)
    expect(fetcher).not.toHaveBeenCalled()
  })

  it.each(['UTC', 'America/Los_Angeles', 'Asia/Shanghai'])('always displays Beijing time on a computer using %s', zone => {
    const previous = process.env.TZ
    process.env.TZ = zone
    try {
      expect(formatBeijingTime(Date.parse('2026-09-18T00:03:39Z'))).toBe('2026-09-18 08:03')
      expect(formatBeijingTime(Date.parse('2026-09-17T16:00:00Z'))).toBe('2026-09-18 00:00')
    } finally {
      if (previous === undefined) delete process.env.TZ
      else process.env.TZ = previous
    }
  })
})
