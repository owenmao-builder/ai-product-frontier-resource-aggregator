import {describe,expect,it} from 'vitest';
import {mergeDiscoveredProducts,syncProducts} from '../src/product-sync';
import type {DiscoveredProduct} from '../src/product-discovery';
import type {ArchiveItem} from '../src/types';

const now=new Date('2026-09-25T04:00:00Z');
const product:DiscoveredProduct={id:'sprout',name:'Sprout 2.5',maker:'Example Lab',major:false,category:'决策模型',summary:'已核对的模型说明',difference:'模型差异',access:'公开权重',homepage:'https://huggingface.co/example/Sprout-2.5',sourceURL:'https://huggingface.co/example/Sprout-2.5',aliases:['Sprout 2.5'],discoveryBasis:'official'};
function post(handle:string,title:string):ArchiveItem {return {id:handle,site_id:'opmlrss',site_name:'RSS',source:handle,title,url:`https://x.com/${handle}/status/123`,published_at:'2026-09-24T06:00:00Z',first_seen_at:now.toISOString(),last_seen_at:now.toISOString()};}

describe('combined product discovery',()=>{
  it('keeps social evidence and edited identity while adding the live model trend',async()=>{
    const news=[post('alice','Sprout 2.5 is a useful decision model.'),post('bob','Sprout 2.5 模型支持本地决策。')];
    const result=await syncProducts(news,{},now,[product],async()=>{throw new Error('no official fetch expected');},async()=>[
      {id:'example/Sprout-2.5',author:'example',trendingScore:123,likes:450,createdAt:'2026-09-20T00:00:00Z'}
    ]);
    const selected=result.items.filter(p=>p.id==='sprout');
    expect(selected).toHaveLength(1);
    expect(selected[0].summary).toBe(product.summary);
    expect(selected[0].signals?.map(s=>s.kind)).toEqual(expect.arrayContaining(['x','community','huggingface']));
    expect(selected[0].releasedOn).toBeUndefined();
    expect(selected[0].relatedNews).toHaveLength(2);
  });
  it('does not merge different authors or collapse decimal versions',()=>{
    const other={...product,id:'other',maker:'Another Lab'};
    const newer={...product,id:'newer',name:'Sprout 25'};
    expect(mergeDiscoveredProducts([product],[other,newer])).toHaveLength(3);
  });
  it('does not restore old social signals or articles through the model trend cache',async()=>{
    const oldURL='https://x.com/previous_author/status/old';
    const previousProduct:DiscoveredProduct={...product,signals:[
      {kind:'x',label:'X · 8 位作者讨论',title:'Previous discussion',url:oldURL,observedAt:'2026-09-24T05:00:00Z',sourceCount:8},
      {kind:'community',label:'8 家集中报道',title:'Previous discussion',url:oldURL,observedAt:'2026-09-24T05:00:00Z',sourceCount:8},
    ],relatedNews:[{title:'Previous discussion',url:oldURL,date:'2026-09-24T05:00:00Z'}]};
    const news=[post('alice','Sprout 2.5 is a useful decision model.'),post('bob','Sprout 2.5 模型支持本地决策。')];
    const result=await syncProducts(news,{items:[previousProduct]},now,[],async()=>{throw new Error('no official fetch expected');},async()=>[
      {id:'example/Sprout-2.5',author:'example',trendingScore:123,likes:450}
    ]);
    const selected=result.items.find(item=>item.id===product.id)!;
    expect(selected.signals?.filter(signal=>signal.kind==='x')).toHaveLength(1);
    expect(selected.signals?.filter(signal=>signal.kind==='community')).toHaveLength(1);
    expect(selected.signals?.find(signal=>signal.kind==='x')?.sourceCount).toBe(2);
    expect(selected.signals?.find(signal=>signal.kind==='community')?.sourceCount).toBe(2);
    expect(selected.signals?.some(signal=>signal.kind==='huggingface')).toBe(true);
    expect(selected.signals?.some(signal=>signal.url===oldURL)).toBe(false);
    expect(selected.relatedNews?.map(article=>article.url)).toEqual(expect.arrayContaining(news.map(item=>item.url)));
    expect(selected.relatedNews).toHaveLength(2);
  });
});
