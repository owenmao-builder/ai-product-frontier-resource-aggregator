import type { DirectFeedStatus } from '../types'
import { formatBeijingTime } from './newsTime'

export function newsFreshness(generatedAt: string | undefined, sources: DirectFeedStatus[] = [], now = Date.now()) {
  const generated = Date.parse(generatedAt || '')
  const age = now - generated
  const snapshotLabel = !Number.isFinite(generated) ? '聚合内容暂未取得' : age < 0 ? '聚合快照时间异常' : `聚合快照 ${formatBeijingTime(generated)}${age >= 3_600_000 ? ` · ${Math.floor(age / 3_600_000)} 小时未更新` : ''}`
  const ready = sources.filter(source => !source.error && source.fetchedAt).length
  const checks = sources.map(source => Date.parse(source.checkedAt || '')).filter(Number.isFinite)
  const checked = checks.length ? Math.max(...checks) : null
  const directLabel = sources.length ? `原站直采 ${ready}/${sources.length} · 最近检查 ${formatBeijingTime(checked)}` : '原站直采由 Mac 应用提供'
  return { snapshotLabel, directLabel, isStale: !Number.isFinite(generated) || age < 0 || age >= 3_600_000 }
}
