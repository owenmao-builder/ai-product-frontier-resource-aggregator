import type { AIProduct, NewsItem, ProductBoard, ProductDiscovery, ProductSignal } from '../types'
import { publicSourceURL } from './ratings'

const nameKey = (value:string) => value.toLowerCase().replace(/[^\p{L}\p{N}.]+/gu,'')
const beijingDay = (value:number) => new Date(value + 8 * 3600_000).toISOString().slice(0,10)

export function productReportingSignal(product:AIProduct, news:NewsItem[], now=Date.now()):ProductSignal|undefined {
  const names = new Set([product.name,...product.aliases].map(nameKey))
  const events = news.flatMap(row=>row.event ? [row.event] : []).filter(event=>{
    const latest = Date.parse(event.latestAt || '')
    if (!event.coverage || event.coverage.sourceCount < 2 || !Number.isFinite(latest) || latest > now || beijingDay(latest) !== beijingDay(now)) return false
    return (event.subject && names.has(nameKey(event.subject))) || event.urls.some(url=>url.replace(/\/+$/,'')===product.sourceURL.replace(/\/+$/,''))
  }).sort((a,b)=>(b.coverage?.sourceCount || 0)-(a.coverage?.sourceCount || 0) || (b.latestAt || '').localeCompare(a.latestAt || ''))
  const event = events[0], coverage = event?.coverage
  const url = event?.urls.find(publicSourceURL)
  if (!event || !coverage || !url || !event.latestAt) return
  return {kind:'coverage',label:`${coverage.sourceCount} 家集中报道`,title:`报道来源：${coverage.sourceNames.join('、')}`,url,observedAt:event.latestAt,sourceCount:coverage.sourceCount}
}

export function withProductReporting(catalog:ProductBoard, news:NewsItem[], now=Date.now()):ProductBoard {
  return {...catalog,items:catalog.items.map(product=>{
    const signal = productReportingSignal(product,news,now)
    return {...product,signals:[...(signal ? [signal] : []),...(product.signals || []).filter(s=>s.kind!=='coverage')]}
  })}
}

export function compareProducts(a:AIProduct,b:AIProduct):number {
  const count=(p:AIProduct)=>p.signals?.find(s=>s.kind==='coverage')?.sourceCount || 0
  return count(b)-count(a) || Number(b.major)-Number(a.major) || Number(b.releaseKind==='新模型')-Number(a.releaseKind==='新模型') ||
    (b.releasedOn || '').localeCompare(a.releasedOn || '') || a.name.localeCompare(b.name)
}

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
