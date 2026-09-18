import { describe, expect, it } from 'vitest'
import { XinzhiyuanFetcher, xinzhiyuanPublishedAt } from '../src/fetchers/xinzhiyuan.js'
import { newsTime } from '../web/src/lib/newsTime'

const now = new Date('2026-09-18T06:00:00Z') // 14:00 in Shanghai
const post = { id: 114307, date: '2026-09-18T08:03:39', date_gmt: '2026-09-18T00:03:39', title: { rendered: 'Timestamp fixture' }, link: 'https://example.com/article' }

describe('WordPress publication timestamps', () => {
  it.each(['UTC', 'Asia/Shanghai', 'America/Los_Angeles'])('interprets 08:03 Shanghai independently of collector timezone %s', zone => {
    const previous = process.env.TZ
    process.env.TZ = zone
    try {
      expect(xinzhiyuanPublishedAt(post)?.toISOString()).toBe('2026-09-18T00:03:39.000Z')
      expect(xinzhiyuanPublishedAt({ date: post.date })?.toISOString()).toBe('2026-09-18T00:03:39.000Z')
      expect(xinzhiyuanPublishedAt({ date: post.date, date_gmt: 'invalid' })?.toISOString()).toBe('2026-09-18T00:03:39.000Z')
      expect(xinzhiyuanPublishedAt({ date: '2026-09-18T08:03:39+08:00' })?.toISOString()).toBe('2026-09-18T00:03:39.000Z')
    } finally {
      if (previous === undefined) delete process.env.TZ
      else process.env.TZ = previous
    }
  })

  it('rejects invalid and genuinely future posts without dropping valid news', async () => {
    class FixtureFetcher extends XinzhiyuanFetcher {
      protected async fetchJsonData<T>(): Promise<T> {
        return [
          { ...post, date: 'invalid', date_gmt: 'invalid' },
          { ...post, date_gmt: '2026-09-18T08:00:00' },
          post,
          { ...post, date_gmt: '2026-09-01T00:00:00' },
        ] as T
      }
    }
    const items = await new FixtureFetcher().fetch(now)
    expect(items).toHaveLength(1)
    expect(items[0].publishedAt?.toISOString()).toBe('2026-09-18T00:03:39.000Z')
  })
})

describe('display and sorting time for cached upstream news', () => {
  const broken = { published_at: '2026-09-18T08:03:39Z', first_seen_at: '2026-09-18T02:06:03.931Z' }

  it('labels the collection fallback and preserves original timestamps', () => {
    const original = { ...broken }
    const resolved = newsTime(broken, now.getTime())
    expect(resolved.timestamp).toBe(Date.parse(broken.first_seen_at))
    expect(resolved.isCollection).toBe(true)
    expect(resolved.explanation).toContain('不代表发布时间')
    expect(broken).toEqual(original)
    // It must not silently switch to the bad publication time after 16:03.
    expect(newsTime(broken, Date.parse('2026-09-18T12:00:00Z'))).toEqual(resolved)
  })

  it('preserves valid UTC dates and tolerates only small source-clock skew', () => {
    expect(newsTime({ ...broken, published_at: '2026-09-18T00:03:39Z' }, now.getTime())).toMatchObject({ timestamp: Date.parse('2026-09-18T00:03:39Z'), isCollection: false })
    expect(newsTime({ published_at: '2026-09-18T02:05:00Z', first_seen_at: '2026-09-18T02:00:00Z' }, now.getTime()).isCollection).toBe(false)
    expect(newsTime({ published_at: '2026-09-18T02:05:01Z', first_seen_at: '2026-09-18T02:00:00Z' }, now.getTime()).isCollection).toBe(true)
  })

  it.each([null, '', 'invalid'])('uses collection time for missing or invalid publication %s', published_at => {
    expect(newsTime({ ...broken, published_at }, now.getTime()).isCollection).toBe(true)
  })

  it('never manufactures a time when both timestamps are invalid or in the future', () => {
    expect(newsTime({ published_at: broken.published_at, first_seen_at: '2026-09-18T08:04:00Z' }, now.getTime()).timestamp).toBeNull()
    expect(newsTime({ published_at: 'invalid', first_seen_at: 'invalid' }, now.getTime()).timestamp).toBeNull()
    // A valid publication time remains usable when collection time is missing.
    expect(newsTime({ published_at: '2026-09-18T00:03:39Z', first_seen_at: '' }, now.getTime()).isCollection).toBe(false)
  })
})
