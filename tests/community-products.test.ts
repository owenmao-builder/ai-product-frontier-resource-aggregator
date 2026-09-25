import {describe,it,expect} from 'vitest';
import {discoverCommunityProducts} from '../src/community-products';
import type {ArchiveItem} from '../src/types';
import type {DiscoveredProduct} from '../src/product-discovery';
const now=new Date('2026-09-25T10:00:00Z');
function article(title:string,url:string,extra:Record<string,unknown>={}):ArchiveItem {
  return {id:url,site_id:'test',site_name:'Test',source:'News',title,url,published_at:'2026-09-24T10:00:00Z',first_seen_at:'2026-09-24T10:00:00Z',last_seen_at:now.toISOString(),...extra};
}
function known(name:string,extra:Record<string,unknown>={}):DiscoveredProduct {
  return {id:name,name,maker:'Example Lab',major:false,category:'模型更新',aliases:[name],homepage:`https://${name.toLowerCase().replace(/\W/g,'')}.example`,sourceURL:`https://${name.toLowerCase().replace(/\W/g,'')}.example/release`,summary:'人工编辑说明',difference:'人工编辑差异',access:'API',discoveredAutomatically:false,verifiedAt:'2026-09-18T00:00:00Z',dateBasis:'官网首发',releasedOn:'2026-09-08',releaseKind:'新模型',...extra};
}
function coverage(product:DiscoveredProduct|undefined,kind='community'){return product?.signals?.find(s=>s.kind===kind);}
describe('community product discovery and source attribution',()=>{
  it('discovers a previously unknown release and gives it real discussion signals without inventing a launch date',()=>{
    const rows=[article('Acme releases NovaGraph 1.2, a new AI decision model','https://x.com/devone/status/1'),article('NovaGraph 1.2 is an interesting AI model','https://twitter.com/devtwo/status/2')];
    const result=discoverCommunityProducts(rows,[],now);
    expect(result).toHaveLength(1);expect(result[0].name).toBe('NovaGraph 1.2');
    expect(result[0]).toMatchObject({discoveryBasis:'community',maker:'开发者 / 社区',lastSeenAt:'2026-09-24T10:00:00.000Z'});
    expect(result[0].releasedOn).toBeUndefined();expect(result[0].verifiedAt).toBeUndefined();
    expect(coverage(result[0])).toMatchObject({label:'2 家集中报道',sourceCount:2});
    expect(coverage(result[0],'x')).toMatchObject({label:'X · 2 位作者讨论',sourceCount:2});
  });
  it('uses known aliases and original links while preserving editorial descriptions and old official dates',()=>{
    const product=known('Muse',{maker:'Meta',aliases:['Muse','Meta Muse'],major:true,homepage:'https://muse.ai',sourceURL:'https://about.fb.com/news/muse'});
    const result=discoverCommunityProducts([article('Meta Muse is useful','https://x.com/alice/status/1'),article('Muse 帮我完成任务','https://theverge.com/muse/review'),article('Muse new feature','https://x.com/AIatMeta/status/3')],[product],now);
    expect(result).toHaveLength(1);expect(result[0]).toMatchObject({summary:'人工编辑说明',releasedOn:'2026-09-08',discoveryBasis:'official'});
    expect(coverage(result[0])?.sourceCount).toBe(2);expect(result[0].relatedNews).toHaveLength(3);
  });
  it('keeps Jev derivatives, foundation models, and specific Muse products separate',()=>{
    const catalog=[known('Jev'),known('Qwen3.5'),known('Kev'),known('Muse',{maker:'Meta'}),known('Muse Realtime Avatar',{maker:'Meta'})];
    const rows=[article('Cognition 团队开源发布了 Jev-like 小型决策模型 Kev，基于 Qwen3.5','https://x.com/alice/status/1'),article('Kev is a useful decision model inspired by Jev','https://x.com/bob/status/2'),article('Meta 发布 Muse Realtime Avatar 实时 AI 化身','https://media.test/muse-avatar'),article('Muse Realtime Avatar 技术拆解','https://x.com/carol/status/3'),article('Muse AI Companion','https://www.producthunt.com/products/muse-ai-companion-browser-assistant'),article('Muse Charm is coming','https://media.test/muse-charm')];
    const result=discoverCommunityProducts(rows,catalog,now);
    expect(result.map(p=>p.name).sort()).toEqual(['Kev','Muse Realtime Avatar']);
    expect(coverage(result.find(p=>p.name==='Kev'))?.sourceCount).toBe(2);
    expect(coverage(result.find(p=>p.name==='Muse Realtime Avatar'))?.sourceCount).toBe(2);
  });
  it('deduplicates X handles, platform aliases, retweets, URLs, syndicated titles and HN entry points',()=>{
    const rows=[article('Laya is a decision model','https://x.com/alice/status/1'),article('Laya 性能测试','https://twitter.com/Alice/status/2'),article('Laya is a decision model','https://x.com/bob/status/3'),article('RT @alice: Laya is a decision model','https://x.com/carol/status/4'),article('Laya 独立体验','https://x.com/dan/status/5?utm_source=feed'),article('Laya another title','https://twitter.com/dan/status/5'),article('Laya 讨论','https://news.ycombinator.com/item?id=1'),article('Laya HN 第二个入口','https://news.ycombinator.com/item?id=2')];
    const p=discoverCommunityProducts(rows,[known('Laya')],now)[0];
    expect(coverage(p)?.sourceCount).toBe(3);expect(coverage(p,'x')?.sourceCount).toBe(2);
  });
  it('discovers HF model identities without a news-like title and ties matching reports to the same product',()=>{
    const result=discoverCommunityProducts([article('author/quiet-decider-0.8b','https://huggingface.co/author/quiet-decider-0.8b'),article('quiet-decider-0.8b is a useful model','https://x.com/one/status/1'),article('quiet-decider-0.8b 开源决策模型体验','https://x.com/two/status/2')],[],now);
    expect(result).toHaveLength(1);expect(result[0].name).toBe('quiet-decider-0.8b');expect(result[0].maker).toBe('author');expect(coverage(result[0])?.sourceCount).toBe(2);
  });
  it('uses Show HN and full RSS release paragraphs with repository links, excluding a linked base model',()=>{
    const result=discoverCommunityProducts([article('Show HN: OrbitDesk – an AI agent for local tasks','https://github.com/owner/orbitdesk'),article('Weekly AI tools','https://media.test/weekly',{content_text:'Today we are introducing FieldAgent 2.1, a new AI agent. Repository https://github.com/builder/fieldagent. It is based on Qwen3.5 from https://huggingface.co/Qwen/Qwen3.5-2B.',content_links:['https://github.com/builder/fieldagent','https://huggingface.co/Qwen/Qwen3.5-2B']})],[],now);
    expect(result.map(p=>p.name).sort()).toEqual(['FieldAgent 2.1','OrbitDesk']);
    expect(result.find(p=>p.name==='OrbitDesk')?.repository).toBe('https://github.com/owner/orbitdesk');
  });
  it('does not invent products from brands, broad categories, finance, rumor or comparison targets',()=>{
    const result=discoverCommunityProducts([article('Introducing AI Agents','https://media.test/agents'),article('Meta raises $5 billion for AI','https://media.test/finance'),article('Rumor: Acme releases Ghost 3 AI model next week','https://media.test/rumor'),article('New AI decision model is faster than Qwen3.5','https://media.test/compare'),article('Jev vs Kev: comparing decision models','https://media.test/vs'),article('OpenAI launches ChatGPT','https://media.test/chatgpt')],[],now);
    expect(result).toEqual([]);
  });
  it('keeps versions distinct and uses publication time instead of refresh time or future posts',()=>{
    const rows=[article('Introducing MotionKit 2.1, an AI tool','https://x.com/one/status/1'),article('MotionKit 2.1 很好用','https://x.com/two/status/2',{published_at:'2026-09-23T01:00:00Z'}),article('MotionKit 2.2 新功能','https://x.com/three/status/3'),article('MotionKit 2.1 old','https://x.com/four/status/4',{published_at:'2026-09-17T01:00:00Z'}),article('MotionKit 2.1 future','https://x.com/five/status/5',{published_at:'2026-09-26T01:00:00Z'})];
    const result=discoverCommunityProducts(rows,[known('MotionKit 2.2')],now);
    const p=result.find(p=>p.name==='MotionKit 2.1');expect(coverage(p)?.sourceCount).toBe(2);expect(coverage(p)?.observedAt).toBe('2026-09-24T10:00:00.000Z');expect(p?.relatedNews).toHaveLength(2);
    expect(coverage(result.find(p=>p.name==='MotionKit 2.2'))).toBeUndefined();
  });
  it('counts an HN discussion once even with its repository URL, and excludes the project author',()=>{
    const p=discoverCommunityProducts([
      article('Kev: Tiny Jev-like decision models built on Qwen3.5','https://github.com/jaredpalmer/kev/tree/main',{source:'Hacker News (黑客新闻)'}),
      article('Kev: Tiny Jev-like decision models built on Qwen3.5','https://news.ycombinator.com/item?id=49783999',{source:'hackernews'}),
      article('Kev 发布并开源','https://x.com/jaredpalmer/status/1'),
      article('Kev 决策模型体验','https://x.com/testauthor/status/2')
    ],[known('Kev',{repository:'jaredpalmer/kev'})],now)[0];
    expect(coverage(p)?.sourceCount).toBe(2);expect(coverage(p,'x')).toBeUndefined();
  });
  it('counts the reporting media that discovered an unknown product and preserves decimal version identity',()=>{
    const p=discoverCommunityProducts([
      article('Acme releases Sigma 2.5, an AI model','https://media.one/release'),
      article('Sigma 2.5 first look','https://media.two/review'),
      article('Acme releases Sigma 25, a new AI model','https://media.three/release')
    ],[],now);
    expect(p.map(i=>i.name).sort()).toEqual(['Sigma 2.5','Sigma 25']);
    expect(coverage(p.find(i=>i.name==='Sigma 2.5'))?.sourceCount).toBe(2);
    expect(coverage(p.find(i=>i.name==='Sigma 25'))).toBeUndefined();
  });
  it('does not combine unrelated repositories sharing a name',()=>{
    const p=discoverCommunityProducts([
      article('ownerA/neon','https://huggingface.co/ownerA/neon'),
      article('ownerB/neon','https://huggingface.co/ownerB/neon'),
      article('Neon model discussion without a creator','https://x.com/tester/status/1')
    ],[],now);
    expect(p).toHaveLength(2);expect(new Set(p.map(i=>i.id)).size).toBe(2);
    expect(p.every(i=>!i.signals?.length)).toBe(true);
    expect(p.every(i=>i.relatedNews?.length===1)).toBe(true);
  });
  it('ignores generic platforms and issuers before release verbs and derivative suffixes',()=>{
    const p=discoverCommunityProducts([
      article('Meta launches a Mac app for Muse','https://media.one/release'),
      article('TypeSafe AI 推出决策专用模型 Jev','https://media.two/release'),
      article('Laya-mlx 最近很火','https://media.three/review'),
      article('Nova 2.1 正式上线：AI 决策模型','https://media.four/release')
    ],[known('Laya')],now);
    expect(p.map(i=>i.name)).not.toContain('Mac');expect(p.map(i=>i.name)).not.toContain('TypeSafe AI');
    expect(p.map(i=>i.name)).not.toContain('Laya');expect(p.map(i=>i.name)).toContain('Nova 2.1');
  });

  it('rejects bare edition labels and verbs without rejecting full model names',()=>{
    const rows=[article('小米 MiMo-V2.6 发布：Pro 与 Flash 双版本价格不变，超越其它开源模型','https://media.one/mimo'),article('Show HN: Hack——我的 Hacker News 客户端屏蔽 AI 帖子','https://news.ycombinator.com/item?id=22'),article('Why Australia investigated the OpenAI hack','https://media.two/hack'),article('Vision Pro 新眼镜展示','https://media.three/glasses'),...['Max','Mini','Lite','Flash','Base','Preview'].map(name=>article('Introducing '+name+', a new AI model','https://media.test/'+name)),article('Introducing Nova Mini 2.1, a new AI model','https://media.test/nova')];
    // A prior cache may contain the bad discovery; it must not survive as known.
    const bad=known('Pro',{discoveryBasis:'community',maker:'开发者 / 社区'});
    const p=discoverCommunityProducts(rows,[bad],now);
    expect(p.some(i=>['Pro','Max','Mini','Lite','Flash','Base','Preview','Hack'].includes(i.name))).toBe(false);
    expect(p.some(i=>i.name==='Nova Mini 2.1')).toBe(true);
  });
  it('merges deterministic short names into the official versioned model',()=>{
    const p=discoverCommunityProducts([
      article('Anthropic releases Opus 5.5, a new AI model','https://x.com/one/status/1'),
      article('Claude Opus 5.5 实测','https://x.com/two/status/2'),
      article('Opus 5.5 很好用','https://media.test/opus')
    ],[known('Claude Opus 5.5',{maker:'Anthropic'}),known('Opus 5.5',{maker:'开发者 / 社区',discoveryBasis:'community'})],now);
    expect(p).toHaveLength(1);expect(p[0].name).toBe('Claude Opus 5.5');
    expect(p[0].aliases).toContain('Opus 5.5');expect(coverage(p[0])?.sourceCount).toBe(3);
    expect(coverage(p[0],'x')?.title).toContain('@one');expect(coverage(p[0],'x')?.title).toContain('@two');
    expect(coverage(p[0])?.title).toContain('近7天报道来源：');
  });
  it('maps Charm to Muse Charm only in Meta or Muse context, never an unrelated product',()=>{
    const p=discoverCommunityProducts([
      article('Meta为Muse AI推出Charm掌上设备','https://media.one/charm'),
      article('Meta 发布 Muse Charm，一个 AI 设备','https://media.two/charm'),
      article('Meta的Charm设备承载新的AI愿景','https://media.three/charm'),
      article('This film coasts on Charm','https://film.test/review'),
      article('other/charm','https://huggingface.co/other/charm')
    ],[known('Muse'),known('Charm',{maker:'开发者 / 社区',discoveryBasis:'community',summary:'报道提及 Charm：Meta为Muse AI推出Charm掌上设备'})],now);
    const muse=p.find(i=>i.name==='Muse Charm');expect(muse).toBeDefined();expect(coverage(muse)?.sourceCount).toBe(3);
    expect(muse?.aliases).not.toContain('Charm');expect(muse?.relatedNews?.some(i=>i.url.includes('film.test'))).toBe(false);
    expect(p.some(i=>i.name==='Muse')).toBe(false);
    expect(p.find(i=>i.maker==='other')?.relatedNews).toHaveLength(1);
  });

  it('normalizes the same newsroom across mobile, official site, WeChat and short links',()=>{
    const rows=[
      article('Muse 第一篇报道','https://www.qbitai.com/news/1',{source:'量子位 · 每日最新'}),
      article('Muse 微信分析','https://mp.weixin.qq.com/s/qbit',{source:'量子位'}),
      article('Muse 产品实践','https://geekpark.net/news/2',{source:'极客公园'}),
      article('Muse 实践新角度','https://mp.weixin.qq.com/s/geek',{source:'极客公园'}),
      article('Muse 实测','https://www.wsj.com/tech/article',{source:'WSJ'}),
      article('Muse 另一篇实测','https://on.wsj.com/abcdef',{source:'on.wsj.com'}),
      article('Muse 最新发布','https://m.36kr.com/p/12',{source:'36Kr'}),
      article('Muse 发布后体验','https://www.36kr.com/p/13',{source:'36氪 · 24小时热榜'}),
      article('Muse 虎嗅实测','https://www.huxiu.com/article/1',{source:'虎嗅 (Huxiu)'}),
      article('Muse 虎嗅微信实测','https://mp.weixin.qq.com/s/huxiu',{source:'虎嗅App'})
    ];
    const p=discoverCommunityProducts(rows,[known('Muse')],now)[0];
    expect(coverage(p)?.sourceCount).toBe(5);
    expect(coverage(p)?.title.replace('近7天报道来源：','').split('、').sort()).toEqual(['36氪','WSJ','极客公园','量子位','虎嗅'].sort());
  });
  it('excludes aggregated feeds and vendor X accounts from independent source counts',()=>{
    const rows=[
      article('Muse 一篇报道','https://media.one/1'),article('Muse 独立实测','https://x.com/tester/status/1'),
      article('Muse 聚合1','https://readhub.cn/topic/1',{source:'Readhub · AI'}),
      article('Muse 聚合2','https://different.host/readhub/2',{source:'Readhub · AI'}),
      article('Muse 聚合3','https://third.host/readhub/3',{source:'Readhub · 每日最新'}),
      article('Muse 百度热榜','https://www.baidu.com/s?wd=Muse',{source:'百度 · 实时热点'}),
      ...['openaidevs','chatgpt','alibaba_qwen','tencenthunyuan','spacexai','metaai','muse_ai','zai_org'].map((account,i)=>article('Muse 厂商自述 '+i,'https://x.com/'+account+'/status/100'))
    ];
    const p=discoverCommunityProducts(rows,[known('Muse')],now)[0];
    expect(coverage(p)?.sourceCount).toBe(2);expect(coverage(p,'x')).toBeUndefined();
    expect(coverage(p)?.title).not.toMatch(/Readhub|百度|openaidevs|chatgpt|alibaba_qwen|tencenthunyuan|spacexai/);
  });

  it('rejects time phrases and generic categories introduced in RSS prose while retaining named tools',()=>{
    const rows=[
      ...['Today','Tomorrow','Now','Next Week','Coding Agents','Knowledge Agents','Personal AI','Decision Models'].map((name,i)=>article('Weekly AI notes '+i,'https://media.test/prose/'+i,{content_text:'Introducing '+name+', an AI model category.'})),
      article('Weekly AI tools','https://media.test/tools',{content_text:'Introducing Ink Canvas, a new AI drawing tool. We are introducing Obsidian Agent, an AI plugin.'})
    ];
    const stale=known('Today',{discoveryBasis:'community'});
    const p=discoverCommunityProducts(rows,[stale],now);
    expect(p.map(i=>i.name).sort()).toEqual(['Ink Canvas','Obsidian Agent']);
  });
  it('does not attach a named product to the only unrelated repository linked by an RSS roundup',()=>{
    const rows=[article('AI 开源工具盘点','https://x.com/author/status/1',{content_text:'Introducing Step Code, an AI coding agent. Other open source Coding Agents include ZCode: https://github.com/zai-org/ZCode',content_links:['https://github.com/zai-org/ZCode']}),article('ZCode independent review','https://x.com/another/status/2')];
    const p=discoverCommunityProducts(rows,[known('ZCode',{repository:'zai-org/ZCode'})],now);
    const step=p.find(i=>i.name==='Step Code');expect(step?.maker).toBe('开发者 / 社区');
    expect(step?.repository).toBeUndefined();expect(step?.aliases).not.toContain('ZCode');
    expect(step?.relatedNews).toHaveLength(1);expect(coverage(step)).toBeUndefined();
  });
  it('qualifies the named YouTube feature without borrowing other services custom feeds',()=>{
    const p=discoverCommunityProducts([
      article('YouTube unveils Custom Feeds, an LLM-powered feature','https://media.one/youtube'),
      article("YouTube's Custom Feeds let you choose videos",'https://media.two/youtube'),
      article('Bluesky introduces custom feeds','https://media.three/bluesky')
    ],[known('Custom Feeds',{discoveryBasis:'community',maker:'开发者 / 社区'})],now);
    expect(p).toHaveLength(1);expect(p[0]).toMatchObject({name:'YouTube Custom Feeds',maker:'YouTube'});
    expect(p[0].aliases).not.toContain('Custom Feeds');expect(coverage(p[0])?.sourceCount).toBe(2);
  });

});
