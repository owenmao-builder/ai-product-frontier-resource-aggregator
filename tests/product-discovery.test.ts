import { describe, expect, it } from 'vitest';
import { discoverProducts, parseOfficialPage, parseQwenArticle, productsFromPage, recentRelease, releaseNames } from '../src/product-discovery';
import { isRecentRelease, mergeProductCatalog } from '../web/src/lib/products';
import type { ArchiveItem } from '../src/types';
import type { AIProduct } from '../web/src/types';

const now=new Date('2026-09-18T08:00:00Z');
const qwen='https://qwen.ai/blog?id=qwen3.8-omni-flash';
const law='https://openai.com/index/astra-for-law';
function news(title:string,url:string):ArchiveItem {
  return {id:url,site_id:'test',site_name:'Test',source:'Test',title,url,published_at:now.toISOString(),first_seen_at:now.toISOString(),last_seen_at:now.toISOString()};
}
function page(title:string,date='2026-09-18',body='Today we are introducing this new release.') {
  return `<html><head><meta property="article:published_time" content="${date}"></head><body><main><h1>${title}</h1><p>${body}</p></main></body></html>`;
}
const qwenAPI=JSON.stringify({success:true,data:{title:'Qwen3.8-Omni-Flash：耳聪目明，办事得力',content:page('Qwen3.8-Omni-Flash','2026-09-01'),extra:{date:'2026-09-18T15:00:00+08:00',introduction:'今天全新模型正式上线'}}});

describe('automatic products from collected news',()=>{
  it('discovers specific models and applications without editing the bundled catalog',async()=>{
    const result=await discoverProducts([news('Alibaba releases Qwen 3.8 Omni Flash',qwen),news('Astra for Law',law)],{},now,async url=>url.includes('/api/')?qwenAPI:page('Introducing Astra for Law','2026-09-17','Introducing Astra for Law, powered by GPT-6 Astra.'));
    expect(result.items.map(i=>i.name).sort()).toEqual(['Astra for Law','Qwen3.8-Omni-Flash']);
    expect(result.items.find(i=>i.name.startsWith('Qwen'))?.releasedOn).toBe('2026-09-18');
    expect(result.items.every(i=>i.discoveredAutomatically&&i.sourceURL)).toBe(true);
    expect(result.pending).toEqual([]);
    const standalone=mergeProductCatalog({verifiedAt:'2026-09-17',items:[]},result,+now);
    expect(standalone.items).toHaveLength(2);
    expect(mergeProductCatalog(standalone,result,+now).items).toHaveLength(2);
    const second=await discoverProducts([news('Qwen3.8-Omni-Flash 正式上线',qwen)],result,new Date(+now+900_000),async()=>{throw new Error('cache should prevent extra requests');});
    expect(second.items.map(i=>i.id).sort()).toEqual(result.items.map(i=>i.id).sort());
  });
  it('uses the official Qwen article record instead of stale embedded template dates',()=>{
    expect(parseQwenArticle(JSON.parse(qwenAPI),qwen).releasedOn).toBe('2026-09-18');
  });
  it('keeps separately owned repositories and decimal versions distinct across refreshes',async()=>{
    const known=['alice/Nova','bob/Nova','alice/Nova-2.5','alice/Nova-25'].map((repository)=>({
      id:repository,name:repository.split('/')[1],maker:repository.split('/')[0],major:false,category:'模型更新',
      summary:'AI model',difference:'',access:'',homepage:'https://github.com/'+repository,sourceURL:'https://github.com/'+repository,
      repository,aliases:[repository.split('/')[1]],discoveryBasis:'community' as const,
    }));
    const articles=known.map(p=>({...news('AI model '+p.name,p.homepage),source:'Hacker News'}));
    const result=await discoverProducts(articles,{},now,async()=>{throw new Error('no official requests needed');},known);
    expect(result.items.map(p=>p.id).sort()).toEqual(known.map(p=>p.id).sort());
    const next=await discoverProducts(articles,result,new Date(+now+900_000),async()=>'',known);
    expect(next.items.map(p=>p.id).sort()).toEqual(known.map(p=>p.id).sort());
  });
  it('reads the article header date without borrowing related article dates',()=>{
    const html='<main><p>September 17, 2026</p><h1>Introducing Astra for Law</h1><p>Introducing our new offering.</p><article><time datetime="2026-09-09">September 9, 2026</time></article></main>';
    expect(parseOfficialPage(html,law).releasedOn).toBe('2026-09-17');
    expect(parseOfficialPage(html.replace('<p>September 17, 2026</p>',''),law).releasedOn).toBeUndefined();
    expect(parseOfficialPage('<main><h1>Introducing Astra for Law</h1></main><meta property="article:modified_time" content="2026-09-18">',law).releasedOn).toBeUndefined();
  });
  it('does not treat integrations, generic brands, rumors, or future news as model releases',async()=>{
    expect(releaseNames('ChatGPT')).toEqual([]);
    expect(releaseNames('语音助手接入 Qwen3.8-Omni-Flash')).toEqual([]);
    expect(releaseNames("PrismML releases Bonsai 2 27B, which compresses Alibaba's Qwen3.8 27B to 5.9 GB")).toEqual([]);
    expect(releaseNames('Salesforce发布推理模型Koa，基于英伟达Nemotron 3 Super构建')).toEqual([]);
    expect(releaseNames('Introducing Astra for Law, powered by GPT-6 Astra')).toEqual([{name:'Astra for Law',kind:'新工具'}]);
    const future={...news('Qwen3.8-Omni-Flash 发布',qwen),published_at:'2026-09-19T08:00:00Z'};
    const result=await discoverProducts([news('传闻 Qwen3.8 发布',qwen),news('OpenAI 关停 GPT-5.3-Codex：发布七个月后下线',law),future],{},now,async()=>{throw new Error('should not fetch');});
    expect(result.items).toEqual([]);expect(result.pending).toEqual([]);
  });
  it('follows a second news report when the first report has no official link',async()=>{
    const official='https://claude.com/blog/projects-redesigned';
    const result=await discoverProducts([news('Claude Code 发布 Projects 项目功能','https://www.aibase.com/news/42'),news('Claude Code relaunches Projects','https://www.theverge.com/ai/test')],{},now,async url=>{
      if(url.includes('aibase'))return '<p>A report with no source link.</p>';
      if(url.includes('theverge'))return `<a href="${official}">Original announcement</a><a href="https://claude.com.evil.example/post">Fake</a>`;
      expect(url).toBe(official);return page('Projects, redesigned','2026-09-18','Introducing projects for Claude Code.');
    });
    expect(result.items.map(i=>i.name)).toEqual(['Claude Code Projects']);expect(result.pending).toEqual([]);
  });
  it('keeps an officially documented model pending if its first-release date is unknown',async()=>{
    const doc='https://docs.bigmodel.cn/cn/guide/models/vlm/glm-5.3-flash';
    const result=await discoverProducts([news('智谱发布 GLM-5.3-FlashX','https://www.aibase.com/news/43')],{},now,async url=>{
      if(url.endsWith('llms.txt'))return `- [GLM-5.3-Flash/FlashX](${doc}.md)`;
      if(url===doc)return '<main><h1>GLM-5.3-Flash/FlashX</h1><p>现推出 GLM-5.3-FlashX</p></main>';
      return '<p>News report</p>';
    });
    expect(result.items).toEqual([]);
    expect(result.pending[0]).toMatchObject({name:'GLM-5.3-FlashX',officialURL:doc,reason:'官方页面未提供可核验的首发日期'});
  });
  it('retains verified products through temporary source failures, then expires them',async()=>{
    const first=await discoverProducts([news('Astra for Law',law)],{},now,async()=>page('Introducing Astra for Law','2026-09-17'));
    const failed=await discoverProducts([news('Astra for Law',law)],first,new Date(+now+13*3600_000),async()=>{throw new Error('HTTP 503');});
    expect(failed.items).toHaveLength(1);expect(failed.errors[0]).toContain('HTTP 503');
    const expired=await discoverProducts([],failed,new Date('2026-09-24T08:00:00Z'),async()=>{throw new Error('HTTP 503');});
    expect(expired.items).toEqual([]);
  });
  it('rejects old, future and unverified release dates even when the report is new',()=>{
    for(const date of ['2026-09-01','2026-09-19','2026-09-31','']) {
      expect(productsFromPage(parseOfficialPage(page('Introducing Astra for Law',date),law),law,now)).toEqual([]);
    }
    expect(productsFromPage(parseOfficialPage(page('Introducing Astra for Law'),law),'https://openai.com.evil.example/post',now)).toEqual([]);
  });
  it('uses the same seven Beijing calendar days in discovery and the web board',()=>{
    const product={releasedOn:'2026-09-12',releaseKind:'新模型'} as AIProduct;
    for(const [time,expected] of [['2026-09-18T15:59:59Z',true],['2026-09-18T16:00:00Z',false]] as const) {
      expect(recentRelease(product.releasedOn!,new Date(time))).toBe(expected);
      expect(isRecentRelease(product,+new Date(time))).toBe(expected);
    }
  });
});
