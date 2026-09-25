import type { AIProduct, NewsItem, ProductBoard, ProductDiscovery, ProductSignal } from '../types'
import { publicSourceURL } from './ratings'

const nameKey = (value:string) => value.toLowerCase().replace(/[^\p{L}\p{N}.]+/gu,'')
const beijingDay = (value:number) => new Date(value + 8 * 3600_000).toISOString().slice(0,10)

export function productReportingSignal(product:AIProduct, news:NewsItem[], now=Date.now(), catalog:AIProduct[] = []):ProductSignal|undefined {
  const names = new Set([product.name,...product.aliases].map(nameKey))
  const events = news.flatMap(row=>row.event ? [row.event] : []).filter(event=>{
    const latest = Date.parse(event.latestAt || '')
    if (!event.coverage || event.coverage.sourceCount < 2 || !Number.isFinite(latest) || latest > now || beijingDay(latest) !== beijingDay(now)) return false
    if(event.subject) return names.has(nameKey(event.subject))
    const announcement=product.sourceURL.replace(/\/+$/,'')
    const shared=catalog.some(other=>nameKey(other.name)!==nameKey(product.name) && other.sourceURL.replace(/\/+$/,'')===announcement)
    return !shared && event.urls.some(url=>url.replace(/\/+$/,'')===announcement)
  }).sort((a,b)=>(b.coverage?.sourceCount || 0)-(a.coverage?.sourceCount || 0) || (b.latestAt || '').localeCompare(a.latestAt || ''))
  const event = events[0], coverage = event?.coverage
  const url = event?.urls.find(publicSourceURL)
  if (!event || !coverage || !url || !event.latestAt) return
  return {kind:'coverage',label:`${coverage.sourceCount} 家集中报道`,title:`报道来源：${coverage.sourceNames.join('、')}`,url,observedAt:event.latestAt,sourceCount:coverage.sourceCount}
}

export function withProductReporting(catalog:ProductBoard, news:NewsItem[], now=Date.now()):ProductBoard {
  return {...catalog,items:catalog.items.map(product=>{
    const signal = productReportingSignal(product,news,now,catalog.items)
    return {...product,signals:mergeProductSignals(product.signals,signal ? [signal] : [],now)}
  })}
}

export function compareProducts(a:AIProduct,b:AIProduct):number {
  const count=(p:AIProduct)=>Math.max(0,...(p.signals || []).map(s=>s.sourceCount || 0))
  return count(b)-count(a) || Number(Boolean(b.signals?.some(s=>s.kind==='x')))-Number(Boolean(a.signals?.some(s=>s.kind==='x'))) || Number(b.major)-Number(a.major) || Number(b.releaseKind==='新模型')-Number(a.releaseKind==='新模型') ||
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

export function isRecentMajorRelease(product:AIProduct, now=Date.now()):boolean {
  return product.major && product.discoveryBasis !== 'community' && isRecentRelease(product,now)
}

export function isFreshProductSignal(signal:ProductSignal, now=Date.now()):boolean {
  const age=now-Date.parse(signal.observedAt)
  const lifetime=['x','community'].includes(signal.kind) ? 7*86400000 : 86400000
  return publicSourceURL(signal.url) && Number.isFinite(age) && age>=0 && age<=lifetime
}

export function mergeProductSignals(first:ProductSignal[] = [], second:ProductSignal[] = [], now=Date.now()):ProductSignal[] {
  const signals=new Map<string,ProductSignal>()
  for(const signal of [...first,...second].filter(s=>isFreshProductSignal(s,now))) {
    const key=signal.kind==='hn' ? signal.kind+':'+signal.url : signal.kind
    const old=signals.get(key)
    if(!old || Date.parse(signal.observedAt)>=Date.parse(old.observedAt)) signals.set(key,signal)
  }
  const order=(signal:ProductSignal)=>signal.kind==='x' ? 0 : ['community','coverage'].includes(signal.kind) ? 1 : 2
  return [...signals.values()].sort((a,b)=>order(a)-order(b) || (b.sourceCount || 0)-(a.sourceCount || 0))
}

function mergeProductNews(first:AIProduct['relatedNews'] = [], second:AIProduct['relatedNews'] = [], now=Date.now()):NonNullable<AIProduct['relatedNews']> {
  const news=new Map<string,NonNullable<AIProduct['relatedNews']>[number]>()
  for(const item of [...first,...second]) {
    const age=now-Date.parse(item.date)
    if(publicSourceURL(item.url) && age>=0 && age<=7*86400000) news.set(item.url,item)
  }
  return [...news.values()].sort((a,b)=>b.date.localeCompare(a.date)).slice(0,8)
}

export function visibleProducts(catalog:ProductBoard,now=Date.now()):AIProduct[] {
  return catalog.items.map(product=>({...product,signals:mergeProductSignals(product.signals,[],now),relatedNews:mergeProductNews(product.relatedNews,[],now)}))
    .filter(product=>isRecentMajorRelease(product,now) || product.signals.length>0).sort(compareProducts)
}

function compatibleMaker(first:string,second:string):boolean {
  const generic=new Set(['','开发者社区','开发者','社区','未知','unknown','community'])
  const a=nameKey(first),b=nameKey(second)
  return a===b || generic.has(a) || generic.has(b)
}

function repositoryIdentity(product:AIProduct,host:'github.com'|'huggingface.co'):string|undefined {
  for(const value of [product.repository,product.homepage,product.sourceURL]) {
    if(!value) continue
    try {
      const url=new URL(value.includes('://') ? value : 'https://github.com/'+value)
      if(url.hostname.replace(/^www\./,'').toLowerCase()!==host) continue
      const parts=url.pathname.split('/').filter(Boolean)
      if(parts.length<2 || (host==='huggingface.co' && ['spaces','datasets','models','api'].includes(parts[0]))) continue
      return parts.slice(0,2).join('/').toLowerCase()
    } catch { /* A missing repository identity cannot establish a conflict. */ }
  }
}

function compatibleIdentity(first:AIProduct,second:AIProduct):boolean {
  if(!compatibleMaker(first.maker,second.maker)) return false
  for(const host of ['github.com','huggingface.co'] as const) {
    const a=repositoryIdentity(first,host),b=repositoryIdentity(second,host)
    if(a && b && a!==b) return false
  }
  return true
}

export function mergeProductCatalog(catalog: ProductBoard, discovery?: ProductDiscovery, now = Date.now()): ProductBoard {
  if (!discovery) return catalog
  const items=catalog.items.map(p=>({...p}))
  const names=(p:AIProduct)=>[p.name,...p.aliases].map(nameKey)
  for(const product of discovery.items) {
    const signals=mergeProductSignals(product.signals,[],now)
    const lastSeenAge=now-Date.parse(product.lastSeenAt || '')
    const recentCommunity=product.discoveryBasis==='community' && lastSeenAge>=0 && lastSeenAge<=7*86400000
    if(!(product.discoveryBasis!=='community' && isRecentRelease(product,now)) && !signals.length && !recentCommunity) continue
    const index=items.findIndex(existing=>compatibleIdentity(existing,product) && (names(existing).includes(nameKey(product.name)) || names(product).includes(nameKey(existing.name))))
    if(index<0) {items.push({...product,signals,relatedNews:mergeProductNews(product.relatedNews,[],now)}); continue}
    const existing=items[index]
    const promoted=existing.discoveryBasis==='community' && product.discoveryBasis==='official'
    items[index]={...existing,
      ...(promoted ? {discoveryBasis:'official' as const,releasedOn:product.releasedOn,releaseKind:product.releaseKind,
        sourceURL:product.sourceURL,homepage:product.homepage,verifiedAt:product.verifiedAt,dateBasis:product.dateBasis,major:product.major,maker:product.maker} : {}),
      repository:existing.repository || product.repository,
      signals:mergeProductSignals(existing.signals,signals,now),relatedNews:mergeProductNews(existing.relatedNews,product.relatedNews,now),
      firstSeenAt:existing.firstSeenAt || product.firstSeenAt,lastSeenAt:[existing.lastSeenAt,product.lastSeenAt].filter(Boolean).sort().at(-1),
    }
  }
  const confirmed=items.filter(p=>p.discoveryBasis!=='community' && isRecentRelease(p,now))
  return {...catalog,items,discovery:{...discovery,pending:discovery.pending.filter(p=>!confirmed.some(item=>compatibleMaker(item.maker,p.maker) && names(item).includes(nameKey(p.name))))}}
}
