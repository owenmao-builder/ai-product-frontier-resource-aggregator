import { describe, expect, it } from 'vitest'
import { newsFreshness } from '../web/src/lib/freshness'

describe('news refresh status', () => {
  const now = Date.parse('2026-09-18T07:00:00Z')
  it('separates a fresh source check from an old snapshot', () => {
    const status = newsFreshness('2026-09-18T02:06:03Z', [{ id: 'live', checkedAt: '2026-09-18T06:56:00Z', fetchedAt: '2026-09-18T06:56:01Z', windowCount: 1 }], now)
    expect(status.directLabel).toContain('1/1')
    expect(status.directLabel).toContain('14:56')
    expect(status.snapshotLabel).toContain('10:06')
    expect(status.snapshotLabel).toContain('4 小时未更新')
    expect(status.isStale).toBe(true)
  })
  it('does not count a failed source with cached data as a successful update', () => {
    const status = newsFreshness('2026-09-18T06:56:00Z', [{ id: 'failed', checkedAt: '2026-09-18T06:56:00Z', fetchedAt: '2026-09-18T02:00:00Z', error: 'offline', windowCount: 1 }], now)
    expect(status.directLabel).toContain('0/1')
    expect(status.isStale).toBe(false)
  })
  it('does not invent timestamps for missing or future snapshots', () => {
    expect(newsFreshness(undefined, [], now).snapshotLabel).toBe('聚合内容暂未取得')
    expect(newsFreshness('2026-09-19T00:00:00Z', [], now).snapshotLabel).toBe('聚合快照时间异常')
  })
})
