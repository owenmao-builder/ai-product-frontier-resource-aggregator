import type { ArchiveItem } from './types.js';
import { discoverProducts, type DiscoveryCache, type DiscoveredProduct } from './product-discovery.js';
import { refreshModelTrends } from './model-trends.js';

const key=(name:string)=>name.toLowerCase().replace(/[^\p{L}\p{N}.]/gu,'');

/** Keep evidence from different discovery paths on the same concrete product. */
export function mergeDiscoveredProducts(first:DiscoveredProduct[],second:DiscoveredProduct[]):DiscoveredProduct[] {
  const items=first.map(p=>({...p}));
  for(const product of second) {
    const index=items.findIndex(p=>p.id===product.id || (key(p.name)===key(product.name)&&key(p.maker)===key(product.maker)));
    if(index<0){items.push(product);continue;}
    const existing=items[index];
    const signals=new Map((existing.signals||[]).map(s=>[s.kind+':'+s.url,s]));
    for(const signal of product.signals||[])signals.set(signal.kind+':'+signal.url,signal);
    const news=new Map([...(existing.relatedNews||[]),...(product.relatedNews||[])].map(n=>[n.url,n]));
    items[index]={...product,...existing,signals:[...signals.values()],relatedNews:[...news.values()],
      firstSeenAt:[existing.firstSeenAt,product.firstSeenAt].filter((s):s is string=>Boolean(s)).sort()[0],
      lastSeenAt:[existing.lastSeenAt,product.lastSeenAt].filter((s):s is string=>Boolean(s)).sort().at(-1)};
  }
  return items;
}

export async function syncProducts(news:ArchiveItem[],previous:Partial<DiscoveryCache>,now:Date,known:DiscoveredProduct[],
  readOfficial?:(url:string)=>Promise<string>,readTrends?:()=>Promise<unknown>):Promise<DiscoveryCache> {
  // The public model trend source and existing news are independently useful.
  const [discovery,modelTrends]=await Promise.all([
    discoverProducts(news,previous,now,readOfficial,known),
    refreshModelTrends(previous.modelTrends,[...known,...(previous.items||[])],now,readTrends),
  ]);
  const newsProducts=discovery.items.map(p=>({...p,signals:p.signals?.filter(s=>s.kind!=='huggingface')}));
  // The trend cache retains edited product metadata, which can include old
  // discussion evidence. Only the news path owns recalculated social signals.
  const trendProducts=modelTrends.items.map(({relatedNews,...product})=>({...product,signals:product.signals?.filter(s=>s.kind==='huggingface')}));
  return {...discovery,items:mergeDiscoveredProducts(newsProducts,trendProducts),modelTrends,
    errors:[...discovery.errors,...(modelTrends.error?[modelTrends.error]:[])]};
}
