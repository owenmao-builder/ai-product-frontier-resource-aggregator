import { afterEach, describe, expect, it, vi } from 'vitest';
import { parseAiBase } from '../src/fetchers/aibase';
import { collectionSnapshot, mergeCollected } from '../src/collection';
import { fetchText } from '../src/utils/http';
import { parseDate } from '../src/utils/date';
import { newsFreshness } from '../web/src/lib/freshness';
import type { ArchiveItem, RawItem } from '../src/types';
import type { CollectionStatus } from '../src/collection';

const now = new Date('2026-09-18T07:30:00Z');
const incoming: RawItem = {siteId:'aibase',siteName:'AIbase',source:'AIbase',title:'New model',url:'https://www.aibase.com/zh/news/31158',publishedAt:new Date('2026-09-18T05:50:48Z'),meta:{time_basis:'publisher_addtime'}};
const old: ArchiveItem = {id:'original-reviewed-id',site_id:'other',site_name:'Other',source:'Original source',title:'Previously reviewed model',url:incoming.url,published_at:null,first_seen_at:'2026-09-18T06:00:00Z',last_seen_at:'2026-09-18T06:00:00Z',title_zh:'已有中文标题'};
const state: CollectionStatus = {mode:'local',started_at:'2026-09-18T07:29:00Z',finished_at:now.toISOString(),sources:[
  {id:'aibase',name:'AIbase',kind:'platform',ok:true,checked_at:now.toISOString(),fetched_at:now.toISOString(),item_count:1},
  {id:'failed',name:'Failed source',kind:'platform',ok:false,checked_at:now.toISOString(),fetched_at:'2026-09-18T02:00:00Z',item_count:0,error:'HTTP 503'},
]};

describe('full local collection',()=>{
  afterEach(()=>vi.unstubAllGlobals());
  it('reads exact Beijing publication times from JSON and supports localized article paths',()=>{
    const articles=[{Id:31158,title:'Qwen [model] "release"',addtime:'2026-09-18 13:50:48',updtime:'2026-09-18 15:04:23'}];
    const html=`<script>self.__next_f.push(${JSON.stringify([1,`7:${JSON.stringify(['$',{initialArticles:articles}])}\n`])})</script><a href="/zh/news/31158"><h3>Duplicate</h3></a>`;
    const items=parseAiBase(html,now);
    expect(items).toHaveLength(1);
    expect(items[0].publishedAt?.toISOString()).toBe('2026-09-18T05:50:48.000Z');
    expect(items[0].title).toBe(articles[0].title);
  });
  it('does not pretend a relative label is an exact publication time',()=>{
    const html='<a href="/zh/news/31158"><h3>Model</h3><div class="text-sm text-gray-400"><span>刚刚</span></div></a>';
    expect(parseAiBase(html,now)[0].publishedAt).toBeNull();
  });
  it('brings afternoon articles in without reading an upstream snapshot',()=>{
    const merged=mergeCollected([], [incoming], now);
    const snapshot=collectionSnapshot(merged,state,24);
    expect(snapshot.items[0].url).toBe(incoming.url);
    expect(snapshot.items[0].published_at).toBe('2026-09-18T05:50:48.000Z');
    expect(snapshot.collection.sources[1].fetched_at).toBe('2026-09-18T02:00:00Z');
  });
  it('preserves reviewed identity, titles, translations and first-seen time across refreshes',()=>{
    const first=mergeCollected([old], [incoming], now);
    const second=mergeCollected(first,[incoming],new Date(+now+900_000));
    expect(second).toHaveLength(1);
    expect(second[0]).toMatchObject({id:old.id,title:old.title,title_zh:old.title_zh,source:old.source,first_seen_at:old.first_seen_at});
    expect(second[0].source_publication?.publishedAt).toBe('2026-09-18T05:50:48.000Z');
  });
  it('merges AIbase localized and legacy links without replacing the assessed identity',()=>{
    const legacy={...old,url:old.url.replace('/zh/news/','/news/')};
    const items=mergeCollected([legacy],[incoming],now);
    expect(items).toHaveLength(1);
    expect(items[0]).toMatchObject({id:old.id,url:legacy.url,title:old.title});
    expect(items[0].source_publication?.sourceURL).toBe(legacy.url);
  });
  it('rejects clearly old archive links without inventing a publication hour',()=>{
    const archived={...old,site_id:'tophub',url:'https://www.jiqizhixin.com/articles/2025-11-25-10',published_at:now.toISOString()};
    expect(mergeCollected([archived],[],now)).toHaveLength(0);
    const recent={...archived,url:'https://www.jiqizhixin.com/articles/2026-09-18-10',published_at:null};
    expect(mergeCollected([recent],[],now)[0].published_at).toBeNull();
  });
  it('keeps cached articles when one source fails, while expiring old and future articles',()=>{
    const cached={...old,url:'https://example.com/cached',published_at:'2026-09-18T01:00:00Z'};
    const expired={...old,url:'https://example.com/old',published_at:'2026-09-01T01:00:00Z'};
    const future={...incoming,url:'https://example.com/future',publishedAt:new Date(+now+3600_000)};
    const items=mergeCollected([cached,expired],[incoming,future],now);
    expect(items.map(i=>i.url)).toEqual([cached.url,incoming.url]);
  });
  it('reports partial collection explicitly instead of calling the old snapshot fresh',()=>{
    const labels=newsFreshness('2026-09-18T02:06:00Z',[],+now,state);
    expect(labels.directLabel).toContain('1/2');expect(labels.directLabel).toContain('1 源异常');
    expect(labels.snapshotLabel).toContain('15:30');expect(labels.isStale).toBe(true);
  });
  it('rejects HTTP error pages as source failures',async()=>{
    vi.stubGlobal('fetch',vi.fn().mockResolvedValue(new Response('<html>Forbidden</html>',{status:403})));
    await expect(fetchText('https://example.com/feed',{retries:0})).rejects.toThrow('HTTP 403');
  });
  it('honors the UTC suffix on TechURLs timestamps',()=>{
    expect(parseDate('2026-09-18 6:10:00AM UTC',now)?.toISOString()).toBe('2026-09-18T06:10:00.000Z');
  });
});
