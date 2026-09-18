import { readFile, writeFile, rename, mkdir } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { Command } from 'commander';
import pLimit from 'p-limit';
import { CONFIG } from './config.js';
import { createAllFetchers } from './fetchers/index.js';
import { fetchSingleFeed, resolveOfficialRssUrl } from './fetchers/opml-rss.js';
import { withDirectFeeds } from './direct-feeds.js';
import { hashString } from './utils/hash.js';
import { collectionSnapshot, mergeCollected } from './collection.js';
import type { CollectionSource, CollectionStatus } from './collection.js';
import type { ArchiveItem, RawItem } from './types.js';
import { discoverProducts } from './product-discovery.js';

async function readJSON(path: string, fallback: any) { try { return JSON.parse(await readFile(path,'utf8')); } catch { return fallback; } }
async function atomicJSON(path: string, value: unknown) { const tmp=path+'.tmp'; await writeFile(tmp,JSON.stringify(value)); await rename(tmp,path); }
async function bounded<T>(task: Promise<T>, ms: number): Promise<T> {
  let timer: ReturnType<typeof setTimeout>;
  try { return await Promise.race([task,new Promise<never>((_,reject)=>{timer=setTimeout(()=>reject(new Error('来源响应超时')),ms);})]); }
  finally { clearTimeout(timer!); }
}

async function main() {
  const options = new Command().requiredOption('--output-dir <path>').requiredOption('--catalog <path>').option('--seed <path>').parse().opts();
  CONFIG.http.timeout=15_000; CONFIG.http.retries=0; CONFIG.rss.feedTimeout=15_000;
  const directory=resolve(options.outputDir); await mkdir(directory,{recursive:true});
  const started=new Date();
  const previous=await readJSON(join(directory,'archive.json'),{items:[]});
  const seed=options.seed ? await readJSON(options.seed,{items:[]}) : {items:[]};
  const previousStatus=await readJSON(join(directory,'status.json'),{sources:[]});
  const previousProducts=await readJSON(join(directory,'product-discovery.json'),{});
  const known=new Map<string,CollectionSource>((previousStatus.sources || []).map((s:CollectionSource)=>[s.id,s]));
  const catalog=await readJSON(options.catalog,[]);
  const feeds=withDirectFeeds(catalog.flatMap((group:any)=>(group.feeds || []).map((f:any)=>({title:f.name,xmlUrl:f.url,htmlUrl:''}))));
  const sources: CollectionSource[]=[]; const incoming: RawItem[]=[];
  const platformLimit=pLimit(6),rssLimit=pLimit(12);
  function status(id:string,name:string,kind:'platform'|'rss',url?:string): CollectionSource {
    const prior=known.get(id);
    return {id,name,kind,url,ok:false,checked_at:new Date().toISOString(),fetched_at:prior?.fetched_at,
      latest_published_at:prior?.latest_published_at,item_count:0};
  }
  function success(source:CollectionSource,items:RawItem[]) {
    source.ok=true;source.fetched_at=new Date().toISOString();source.item_count=items.length;
    const dates=items.map(i=>i.publishedAt).filter((d):d is Date=>d!=null&&Number.isFinite(+d)&&d<=new Date());
    if(dates.length)source.latest_published_at=new Date(Math.max(...dates.map(Number))).toISOString();
    incoming.push(...items);
  }
  const platforms=createAllFetchers().map(fetcher=>platformLimit(async()=>{
    const source=status(fetcher.siteId,fetcher.siteName,'platform');
    try { const items=await bounded(fetcher.fetch(new Date()),70_000); if(!items.length)throw new Error('未取得可解析内容，保留上次缓存'); success(source,items); }
    catch(error){source.error=error instanceof Error?error.message:String(error);}
    sources.push(source);console.log(`${source.ok?'OK':'FAIL'} ${source.name}: ${source.item_count}${source.error?' '+source.error:''}`);
  }));
  const subscriptions=feeds.map(feed=>rssLimit(async()=>{
    const id='rss:'+hashString(feed.xmlUrl); const source=status(id,feed.title,'rss',feed.xmlUrl);
    const {url,skipReason}=resolveOfficialRssUrl(feed.xmlUrl);
    if(!url){source.skipped=true;source.error=skipReason || '无可用公开订阅';}
    else {
      try {
        const result=await bounded(fetchSingleFeed({...feed,xmlUrl:url,xmlUrlOriginal:feed.xmlUrl},new Date(),false),20_000);
        if(!result.status.ok)throw new Error(result.status.error || '订阅抓取失败');
        success(source,result.items);
      } catch(error){source.error=error instanceof Error?error.message:String(error);}
    }
    sources.push(source);
  }));
  await Promise.all([...platforms,...subscriptions]);
  const archive=mergeCollected([...(seed.items as ArchiveItem[]),...(previous.items as ArchiveItem[])],incoming,new Date());
  let products;
  try { products=await discoverProducts(archive,previousProducts,new Date()); }
  catch(error) {
    // Product verification must never discard a successful news collection.
    products={checkedAt:new Date().toISOString(),items:[],pending:[],checks:{},linkChecks:{},...previousProducts,
      errors:['产品发布同步失败，保留上次已核实资料：'+(error instanceof Error?error.message:String(error))]};
  }
  const {checks,linkChecks,...productDiscovery}=products;
  const finished=new Date();
  const state:CollectionStatus={mode:'local',started_at:started.toISOString(),finished_at:finished.toISOString(),sources:sources.sort((a,b)=>a.kind.localeCompare(b.kind)||a.name.localeCompare(b.name))};
  if(!sources.some(s=>s.ok))throw new Error('全部来源抓取失败，保留上次资讯');
  await atomicJSON(join(directory,'archive.json'),{items:archive});
  await atomicJSON(join(directory,'status.json'),state);
  await atomicJSON(join(directory,'product-discovery.json'),products);
  await atomicJSON(join(directory,'result.json'),{snapshots:[24,168].map(hours=>({...collectionSnapshot(archive,state,hours),product_discovery:productDiscovery}))});
  console.log(JSON.stringify({finished_at:state.finished_at,sources:sources.length,success:sources.filter(s=>s.ok).length,articles:archive.length}));
}
main().then(()=>process.exit(0)).catch(error=>{console.error(error);process.exit(1);});
