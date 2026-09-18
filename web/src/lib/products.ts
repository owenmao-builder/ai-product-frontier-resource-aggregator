import type { AIProduct, ProductBoard, ProductDiscovery } from '../types'

export function isRecentRelease(product: AIProduct, now = Date.now()) {
  if (!product.releasedOn || !/^\d{4}-\d{2}-\d{2}$/.test(product.releasedOn) || !['新模型','新版本','新功能','新工具','新架构'].includes(product.releaseKind || '')) return false
  const release = Date.parse(product.releasedOn + 'T00:00:00Z')
  if (!Number.isFinite(release) || new Date(release).toISOString().slice(0,10) !== product.releasedOn) return false
  const today = new Date(now + 8 * 3600_000).toISOString().slice(0,10)
  const end = Date.parse(today + 'T00:00:00Z')
  return release >= end - 6 * 86400_000 && release <= end
}

export function mergeProductCatalog(catalog: ProductBoard, discovery?: ProductDiscovery, now = Date.now()): ProductBoard {
  if (!discovery) return catalog
  const key = (name: string) => name.toLowerCase().replace(/[^a-z0-9\p{Script=Han}]/gu, '')
  const names = new Set(catalog.items.filter(p=>isRecentRelease(p,now)).flatMap(p=>[p.name,...p.aliases]).map(key))
  const items = [...catalog.items]
  for (const item of discovery.items) {
    if (isRecentRelease(item,now) && !names.has(key(item.name))) { items.push(item); names.add(key(item.name)) }
  }
  return {...catalog,items,discovery:{...discovery,pending:discovery.pending.filter(p=>!names.has(key(p.name)))}}
}
