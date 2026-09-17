import type { NewsItem, NewsRating } from '../types'
export const VERSION = 'importance-v2'
export const categories: Record<string, string> = {model:'模型进展', research:'研究论文', product:'产品更新', developer:'开发与基础设施', business:'商业与行业', policy:'政策与治理', safety:'安全与事故', analysis:'分析与教程', other:'其他 / 待分类'}
export const dimensionNames: Record<string, string> = {increment:'实质增量', impact:'实际影响', explanation:'解释价值', decision:'决策价值'}
export function ratingFor(item: NewsItem): NewsRating {
  const r = item.rating
  if (r?.version === VERSION) return r
  return {score:null, reason:'当前只有标题、来源和时间，待补充正文与适用的对照材料后再评估。', tags:[], method:'pending', assessedAt:'', version:VERSION, category:'other', evidenceLevel:'C', dimensions:[], sources:[], gaps:['需要原文及适用的历史或同类对照。']}
}
export function scoreOf(item: NewsItem): number | null {
  const r = ratingFor(item)
  return typeof r.score === 'number' && Number.isFinite(r.score) && r.score >= 0 && r.score <= 10 ? r.score : null
}
export function evidenceFor(item: NewsItem): {label: string; explanation: string} {
  if (scoreOf(item) === null) return {label:'C 不足', explanation:'材料不足，只有标题或缺少关键依据；暂不评分，等待补充材料。'}
  return ratingFor(item).evidenceLevel === 'A'
    ? {label:'A 充分', explanation:'关键判断有充分直接材料支持；涉及性能比较时有相应对照。'}
    : {label:'B 待验', explanation:'有原文依据，但关键收益、影响或适用范围仍有待验证。'}
}
export function matchesScore(item: NewsItem, minimum: number): boolean {
  const score = scoreOf(item)
  return minimum === -1 ? score === null : minimum === 0 || (score !== null && score >= minimum)
}
export function publicSourceURL(url: string): boolean {
  try { const u = new URL(url); return u.protocol === 'https:' && !u.username && !u.password } catch { return false }
}
