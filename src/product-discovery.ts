import * as cheerio from 'cheerio';
import pLimit from 'p-limit';
import { createHash } from 'node:crypto';
import type { ArchiveItem } from './types.js';
import { discoverCommunityProducts } from './community-products.js';
import type { ModelTrendsCache } from './model-trends.js';

export interface DiscoveredProduct {
  id: string; name: string; maker: string; major: boolean; category: string;
  summary: string; difference: string; access: string; homepage: string; sourceURL: string;
  aliases: string[]; releasedOn?: string; releaseKind?: string; discoveredAutomatically?: boolean;
  verifiedAt?: string; dateBasis?: string; repository?: string;
  discoveryBasis?: 'official' | 'community'; firstSeenAt?: string; lastSeenAt?: string;
  signals?: {kind:string; label:string; title:string; url:string; observedAt:string; sourceCount?:number}[];
  relatedNews?: {title:string; url:string; date:string}[];
}
export interface PendingProduct { name: string; maker: string; newsTitle: string; newsURL: string; reason: string; officialURL?:string }
export interface ProductDiscovery {
  checkedAt: string; items: DiscoveredProduct[]; pending: PendingProduct[]; errors: string[];
}
export interface DiscoveryCache extends ProductDiscovery {
  checks: Record<string, {checkedAt: string; products: DiscoveredProduct[]; mentionedNames?:string[]; error?: string}>;
  linkChecks?: Record<string, {checkedAt:string; links:string[]}>;
  modelTrends?: ModelTrendsCache;
}
interface Vendor { name: string; hosts: string[]; match: RegExp }
const vendors: Vendor[] = [
  {name:'阿里 / Qwen',hosts:['qwen.ai','qwenlm.github.io','help.aliyun.com'],match:/Qwen|千问|通义/i},
  {name:'智谱',hosts:['z.ai','docs.z.ai','bigmodel.cn','docs.bigmodel.cn'],match:/GLM|智谱/i},
  {name:'OpenAI',hosts:['openai.com'],match:/OpenAI|GPT|Codex|Astra|ChatGPT/i},
  {name:'Anthropic',hosts:['anthropic.com','claude.com','code.claude.com'],match:/Anthropic|Claude/i},
  {name:'Google',hosts:['blog.google','deepmind.google','ai.google.dev'],match:/Google|Gemini|DeepMind/i},
  {name:'DeepSeek',hosts:['deepseek.com','api-docs.deepseek.com'],match:/DeepSeek|深度求索/i},
  {name:'Meta',hosts:['ai.meta.com','research.meta.ai','about.fb.com','meta.ai'],match:/Meta|Llama|\bMuse\b/i},
  {name:'Mistral',hosts:['mistral.ai'],match:/Mistral|Codestral|Ministral/i},
  {name:'NVIDIA',hosts:['nvidia.com','blogs.nvidia.com','developer.nvidia.com'],match:/NVIDIA|英伟达|Nemotron/i},
];
const compact = (value: string) => value.toLowerCase().replace(/[^a-z0-9.\p{Script=Han}]/gu,'');
const clean = (value: string) => value.replace(/\s+/g,' ').trim();
const short = (value: string) => {
  const text=clean(value);const excerpt=text.split(' ').slice(0,22).join(' ').slice(0,150);
  if(excerpt.length===text.length)return excerpt;
  const sentence=excerpt.match(/^.*[。！？]/)?.[0];return sentence||excerpt.replace(/\s+\S*$/,'')+'…';
};
const releaseAction = /发布|上线|推出|升级|重构|新增|正式开放|开源(?!模型)|\b(introducing|introduces?|launched?|launches|released?|releases|unveils?|available|new offering|relaunches)\b/i;
const excluded = /传闻|疑似|偷跑|或将|即将|下周发布|延期|估计是|关停|下线|资助|融资|估值|评测报告|综述|排行榜|unreleased|rumou?r|sneak.launched|coming soon|remain available|\bretir(?:e|ed|ing)\b/i;

export function publisher(url: string): Vendor | undefined {
  try { const parsed=new URL(url); if(parsed.protocol!=='https:'||parsed.username||parsed.password)return;
    const host=parsed.hostname.replace(/^www\./,''); return vendors.find(v=>v.hosts.includes(host));
  } catch { return; }
}

export function releaseNames(title: string): {name:string;kind:string}[] {
  const text=title.replace(/[‑–—]/g,'-').replace(/(GLM[- ]\d+(?:\.\d+)?[- ])Flash\/FlashX/gi,'$1Flash / $1FlashX');
  const names: {name:string;kind:string}[]=[];
  // Versioned model names are specific releases; generic company names are not products.
  const patterns = [
    /\bQwen[ -]?\d+(?:\.\d+)?(?:[- ](?:Omni|FlashX?|Realtime|Plus|Max|VL|Coder|Instruct|Thinking|Live|[\d]+[BM]))*/gi,
    /\bGLM[- ]\d+(?:\.\d+)?(?:[- ](?:FlashX?|Plus|Air|Vision|Thinking|Preview))*/gi,
    /\bGPT[- ]?\d+(?:\.\d+)?(?:[- ](?:Astra|Pro|Mini|Nano|Codex))*/gi,
    /\bGemini[ -]\d+(?:\.\d+)?(?:[- ](?:Flash|Pro|Live|Lite|Extended|Thinking))*/gi,
    /\bClaude[ -](?:(?:Opus|Sonnet|Haiku)[ -])?\d+(?:\.\d+)?/gi,
    /\bDeepSeek[- ](?:V|R)\d+(?:\.\d+)?(?:[- ](?:Pro|Lite|Base))*/gi,
    /\b(?:Llama|Mistral|Ministral|Nemotron)[ -]\d+(?:\.\d+)?(?:[- ][\d]+[BM])?/gi,
  ];
  for(const pattern of patterns) for(const match of text.matchAll(pattern)) names.push({name:match[0].replace(/^Qwen /i,'Qwen').replace(/^(GLM|GPT) /i,'$1-'),kind:'新模型'});
  for(const match of text.matchAll(/\b(?:Astra|Codex|ChatGPT|Claude|Gemini) for [A-Z][a-z]+(?: [A-Z][a-z]+)?/g)) names.push({name:match[0],kind:'新工具'});
  if(/Claude Code/i.test(text)&&/Projects|项目/i.test(text))names.push({name:'Claude Code Projects',kind:'新功能'});
  for(const match of text.matchAll(/\b(?:Qwen|DeepSeek)[- ](?:Live[- ])?Harness\b/gi))names.push({name:match[0],kind:'新架构'});
  if(!names.length) {
    const introduced=text.match(/^(?:Introducing|Meet|Launching) (?:the )?([A-Z][A-Za-z0-9]*(?:[ -][A-Za-z0-9]+){0,5})(?=[:：,，]|$)/);
    if(introduced&&!/^(OpenAI|ChatGPT|Claude|Gemini|Qwen|DeepSeek|Our|A |The )$/i.test(introduced[1]))names.push({name:introduced[1],kind:'新工具'});
  }
  // A product application's underlying model is not itself a new model release.
  const application = names.some(n=>n.kind==='新工具'||n.kind==='新功能') || /接入|搭载|标配|语音助手|powered by|combining|new.*model.*landed in/i.test(text);
  const unique=new Map<string,{name:string;kind:string}>();
  for(const name of names) {
    const position=text.toLowerCase().indexOf(name.name.toLowerCase());
    const prefix=position>=0?text.slice(Math.max(0,position-55),position):'';
    const suffix=position>=0?text.slice(position+name.name.length,position+name.name.length+28):'';
    const underlying=name.kind==='新模型'&&(/基于|compress(?:es|ing)|\busing\b|built (?:on|on top of)|based on/i.test(prefix)||/^\s*(?:底座|作为基座|base model|backbone)/i.test(suffix));
    if((!application||name.kind!=='新模型')&&!underlying)unique.set(compact(name.name),name);
  }
  return [...unique.values()];
}

export function releaseDay(raw: string): string | undefined {
  if(/^\d{4}-\d{2}-\d{2}$/.test(raw)) {
    const date=new Date(raw+'T00:00:00Z');
    return Number.isFinite(+date)&&date.toISOString().slice(0,10)===raw ? raw : undefined;
  }
  const date=new Date(raw);
  if(!Number.isFinite(+date))return;
  return new Date(+date+8*3600_000).toISOString().slice(0,10);
}
export function recentRelease(day: string | undefined, now: Date): boolean {
  if(!day)return false;
  const today=releaseDay(now.toISOString())!;
  const start=new Date(Date.parse(today+'T00:00:00Z')-6*86400_000).toISOString().slice(0,10);
  return releaseDay(day)===day&&day>=start&&day<=today;
}

export interface OfficialPage { title:string; description:string; text:string; releasedOn?:string; dateBasis:string; links:string[] }
export function parseOfficialPage(html: string, url: string): OfficialPage {
  const $=cheerio.load(html);
  const title=clean($('h1').first().text()||$('meta[property="og:title"]').attr('content')||$('title').text()).replace(/\s*[|｜]\s*[^|｜]+$/,'');
  const description=clean($('meta[property="og:description"]').attr('content')||$('meta[name="description"]').attr('content')||'');
  const heading=$('h1').first();
  const article=heading.closest('article,main').length?heading.closest('article,main'): $('body');
  const articleText=article.text();
  // Do not borrow a date from related posts below the article or a site-wide footer.
  const visibleDate=article.find('time,p,span,div').toArray().filter(e=>$(e).parents('aside,footer,nav,a,[class*="related"],[class*="Related"]').length===0&&$(e).children().length===0&&($(e).closest('article')[0]===heading.closest('article')[0]))
    .map(e=>({text:clean($(e).text()),position:articleText.indexOf($(e).text())}))
    .find(v=>v.position<1800&&/^(?:[A-Z][a-z]+ \d{1,2}, \d{4}|\d{4}[/-]\d{2}[/-]\d{2}|\d{4}年\d{1,2}月\d{1,2}日)$/.test(v.text))?.text;
  const visibleDay=visibleDate?.replace(/年|月/g,'-').replace(/日$/,'').replace(/\//g,'-');
  let date=visibleDay||$('meta[property="article:published_time"]').attr('content')||$('meta[name="date"]').attr('content');
  let dateBasis=visibleDay?'官方页面显示的发布日期':date?'官方页面发布时间':'';
  if(!date) for(const script of $('script[type="application/ld+json"]').toArray()) {
    try {
      const root=JSON.parse($(script).text());
      const entries=[...(Array.isArray(root)?root:[root]),...(root['@graph']||[])];
      const article=entries.find((v:any)=>/Article|Posting/.test(String(v['@type']))&&v.datePublished&&(!v.headline||compact(v.headline)===compact(title)));
      if(article){date=article.datePublished;dateBasis='官方结构化发布日期';break;}
    } catch { /* Invalid metadata cannot verify a publication date. */ }
  }
  const links=$('a[href]').toArray().flatMap(a=>{try{return [new URL($(a).attr('href')!,url).href];}catch{return [];}});
  $('script,style,nav,header,footer,aside,noscript').remove();
  $('h1,h2,h3,p,div,li,section').append(' ');
  const text=clean(($('article').first().text()||$('main').first().text()||$('body').text())).slice(0,30000);
  return {title,description,text,releasedOn:date?releaseDay(String(date)):undefined,dateBasis,links};
}

export function parseQwenArticle(json: any, url: string): OfficialPage {
  if(json?.success!==true||typeof json.data?.content!=='string')throw new Error('千问官方接口未提供文章');
  const page=parseOfficialPage(json.data.content,url);
  page.title=json.data.title||page.title;
  // The public article record is authoritative; embedded templates may retain an older build date.
  page.releasedOn=releaseDay(String(json.data.extra?.date||''));
  page.dateBasis='千问官方文章接口的发布日期';
  page.description=clean(json.data.extra?.introduction||page.description);
  return page;
}

export function productsFromPage(page: OfficialPage, url: string, now: Date, knownProducts: DiscoveredProduct[] = []): DiscoveredProduct[] {
  const vendor=publisher(url);
  if(!vendor||!page.releasedOn||!recentRelease(page.releasedOn,now)||excluded.test(page.title))return [];
  if(!releaseAction.test(page.title+' '+page.description+' '+page.text.slice(0,1800)))return [];
  const names=releaseNames(page.title);
  if(!names.length) {
    const text=page.title+' '+page.description+' '+page.text.slice(0,1600);
    const known=knownProducts.filter(p=>p.major&&p.maker===vendor.name&&[p.name,...p.aliases].some(alias=>
      new RegExp('(?<![a-z0-9])'+alias.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')+'(?![a-z0-9.-])','i').test(text)))
      .sort((a,b)=>b.name.length-a.name.length);
    if(known[0])names.push({name:known[0].name,kind:known[0].releaseKind||'新工具'});
  }
  if(!names.length&&vendor.name==='Anthropic'&&/projects/i.test(page.title)&&/Claude Code/i.test(page.text.slice(0,1800)))names.push({name:'Claude Code Projects',kind:'新功能'});
  return names.filter(n=>{const owner=vendors.find(v=>v.match.test(n.name));return !owner||owner.name===vendor.name;}).map(({name,kind})=>({
    id:'release-'+createHash('sha256').update(compact(vendor.name+name)).digest('hex').slice(0,16),name,maker:vendor.name,major:true,
    category:kind==='新模型'?'模型更新':kind==='新架构'?'Agent 与框架':'产品与功能',
    summary:`${vendor.name} 已正式公布 ${name}。`,
    difference:page.description?`官方摘要：${short(page.description)}`:'官方已确认这次发布；具体能力、相对旧版的变化与适用条件请查看公告。',
    access:'通过下方官方发布页查看试用入口、API 或使用说明。',homepage:url,sourceURL:url,aliases:[...new Set([name,name.replace(/-/g,' '),name.replace(/^Qwen(?=\d)/,'Qwen '),name.replace(/^Qwen(?=\d)/,'Qwen ').replace(/-/g,' ')])],releasedOn:page.releasedOn!,releaseKind:kind,
    discoveredAutomatically:true,verifiedAt:now.toISOString(),dateBasis:page.dateBasis,discoveryBasis:'official',
  }));
}

const mediaHosts=['aibase.com','theverge.com','techmeme.com','ithome.com'];
function supportedPage(url:string): boolean {
  try {const parsed=new URL(url);return parsed.protocol==='https:'&&!parsed.username&&!parsed.password&&(Boolean(publisher(url))||mediaHosts.includes(parsed.hostname.replace(/^www\./,'')));}catch{return false;}
}
async function fetchOfficial(url: string): Promise<string> {
  const vendor=publisher(url);if(!supportedPage(url))throw new Error('不是已支持的公开来源');
  let target=url;
  for(let hop=0;hop<4;hop++) {
    const response=await fetch(target,{redirect:'manual',headers:{'User-Agent':'Mozilla/5.0 (compatible; AI-News-Menu/1.5)','Accept':'text/html,application/json'},signal:AbortSignal.timeout(12_000)});
    if(response.status>=300&&response.status<400) {
      target=new URL(response.headers.get('location')||'',target).href;
      if(!supportedPage(target)||(vendor&&publisher(target)?.name!==vendor.name))throw new Error('链接跳转到了其他来源');
      continue;
    }
    if(!response.ok)throw new Error(`官方来源 HTTP ${response.status}`);
    const text=await response.text();if(text.length>4_000_000)throw new Error('官方页面过大');return text;
  }
  throw new Error('官方页面跳转过多');
}

export async function discoverProducts(news: ArchiveItem[], previous: Partial<DiscoveryCache>, now: Date,
  read: (url:string)=>Promise<string> = fetchOfficial, knownProducts: DiscoveredProduct[] = []): Promise<DiscoveryCache> {
  const newsTime=(n:ArchiveItem)=>Date.parse((n as ArchiveItem & {source_publication?:{publishedAt:string}}).source_publication?.publishedAt||n.published_at||n.first_seen_at);
  const current = news.filter(n=>newsTime(n)>=+now-7*86400_000&&newsTime(n)<=+now).sort((a,b)=>newsTime(b)-newsTime(a));
  const candidates = new Map<string,PendingProduct>();
  for(const item of current.filter(n=>!excluded.test(n.title)&&(releaseAction.test(n.title)||Boolean(publisher(n.url))))) {
    for(const release of releaseNames(item.title)) {
      const vendor=vendors.find(v=>v.match.test(release.name))||publisher(item.url);if(!vendor)continue;
      const key=compact(vendor.name+release.name);
      if(!candidates.has(key))candidates.set(key,{name:release.name,maker:vendor.name,newsTitle:item.title,newsURL:item.url,reason:'尚未取得匹配的官方发布页与发布日期'});
    }
  }
  const checks={...(previous.checks||{})};
  const linkChecks={...(previous.linkChecks||{})};
  const candidateLinks=new Map<string,Set<string>>();
  function linkCandidate(name:string,url:string) {
    const key=compact(name);const urls=candidateLinks.get(key)||new Set<string>();urls.add(url);candidateLinks.set(key,urls);
  }
  const errors:string[]=[];
  // Primary URLs already found by the news collector are checked first, with a fixed per-refresh budget.
  const hasKnownOfficialProduct=(item:ArchiveItem)=>knownProducts.some(p=>p.major&&p.maker===publisher(item.url)?.name&&
    [p.name,...p.aliases].some(alias=>new RegExp('(?<![a-z0-9])'+alias.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')+'(?![a-z0-9.-])','i').test(item.title+' '+(item.content_text||'').slice(0,1600))));
  const primary = [...new Set(current.filter(n=>publisher(n.url)&&(releaseNames(n.title).length>0||hasKnownOfficialProduct(n))&&!excluded.test(n.title)).map(n=>n.url))].slice(0,12);
  for(const item of current.filter(n=>primary.includes(n.url)))for(const release of releaseNames(item.title))linkCandidate(release.name,item.url);
  const limit=pLimit(4);
  const unresolved=[...candidates.values()].filter(c=>!primary.some(url=>current.some(n=>n.url===url&&releaseNames(n.title).some(r=>compact(r.name)===compact(c.name)))));
  const mediaByCandidate=unresolved.map(candidate=>({candidate,urls:[...new Set(current.filter(n=>supportedPage(n.url)&&!publisher(n.url)&&!excluded.test(n.title)&&releaseNames(n.title).some(r=>compact(r.name)===compact(candidate.name)))
    .map(n=>n.url.replace('aibase.com/zh/news/','aibase.com/news/')))]
    .sort((a,b)=>Number(a.includes('aibase.com'))-Number(b.includes('aibase.com'))).slice(0,2)}));
  // Try another report if the first outlet omits the official link; cap all requests per refresh.
  const mediaQueue=[0,1].flatMap(index=>mediaByCandidate.flatMap(({candidate,urls})=>urls[index]?[{candidate,url:urls[index]}]:[])).slice(0,8);
  await Promise.all(mediaQueue.map(({candidate,url})=>limit(async()=>{
    if(!linkChecks[url]||+now-Date.parse(linkChecks[url].checkedAt)>3600_000) {
      try {
        const $=cheerio.load(await read(url));
        const links=$('a[href]').toArray().flatMap(a=>{try {return [new URL($(a).attr('href')!,url).href];}catch{return [];}})
          .filter(link=>{
            if(publisher(link)?.name!==candidate.maker||new URL(link).pathname==='/')return false;
            const target=compact(decodeURI(link));
            const digits=candidate.name.match(/\d+(?:\.\d+)?/g)||[];
            if(digits.length)return digits.every(d=>target.includes(compact(d)));
            const specific=candidate.name.split(/[ -]+/).filter(word=>word.length>3).at(-1);
            return specific?target.includes(compact(specific)):false;
          });
        linkChecks[url]={checkedAt:now.toISOString(),links:[...new Set(links)].slice(0,3)};
      } catch {linkChecks[url]={checkedAt:now.toISOString(),links:[]};}
    }
    for(const link of linkChecks[url].links) {
      linkCandidate(candidate.name,link);
      if(!primary.includes(link)&&primary.length<18)primary.push(link);
    }
  })));
  // The public documentation index covers models whose news reports omit source links.
  if(unresolved.some(c=>c.maker==='智谱')) {
    const index='https://docs.bigmodel.cn/llms.txt';
    if(!linkChecks[index]||+now-Date.parse(linkChecks[index].checkedAt)>3600_000) {
      try {
        const markdown=await read(index);
        const links=[...markdown.matchAll(/\[([^\]]+)\]\((https:\/\/docs\.bigmodel\.cn\/cn\/guide\/models\/[^)]+)\)/g)]
          .filter(m=>releaseNames(m[1]).some(r=>unresolved.some(c=>compact(c.name)===compact(r.name))))
          .map(m=>m[2].replace(/\.md$/,''));
        linkChecks[index]={checkedAt:now.toISOString(),links:[...new Set(links)].slice(0,3)};
      } catch { /* Missing index leaves the original news visible as a pending lead. */ }
    }
    for(const link of linkChecks[index]?.links||[])if(!primary.includes(link)&&primary.length<18)primary.push(link);
  }
  await Promise.all(primary.map(url=>limit(async()=>{
    const cached=checks[url];
    if(cached&&+now-Date.parse(cached.checkedAt)<(cached.error?30*60_000:12*3600_000))return;
    try {
      const parsed=new URL(url);
      let page:OfficialPage;
      if(parsed.hostname==='qwen.ai'&&parsed.pathname==='/blog'&&parsed.searchParams.get('id')) {
        const endpoint=new URL('https://qwen.ai/api/v2/article/');
        endpoint.search=new URLSearchParams({language:'zh-CN',path:parsed.searchParams.get('id')!,type:'qwen_ai'}).toString();
        page=parseQwenArticle(JSON.parse(await read(endpoint.href)),url);
      } else page=parseOfficialPage(await read(url),url);
      const products=productsFromPage(page,url,now,knownProducts);
      const mentionedNames=[...candidates.values()].filter(c=>c.maker===publisher(url)?.name&&compact(page.title+' '+page.text).includes(compact(c.name))).map(c=>compact(c.name));
      const error=products.length?undefined:!page.releasedOn?'官方页面未提供可核验的首发日期':!recentRelease(page.releasedOn,now)?'官方发布日期不在最近 7 天内':'官方页未确认匹配的具体发布';
      checks[url]={checkedAt:now.toISOString(),products,mentionedNames,error};
    } catch(error) {
      const reason=error instanceof Error?error.message:String(error);
      checks[url]={...cached,checkedAt:now.toISOString(),products:cached?.products||[],error:reason};
    }
  })));
  const items=new Map<string,DiscoveredProduct>();
  for(const product of [...(previous.items||[]),...Object.values(checks).flatMap(c=>c.products)]) {
    if(product.discoveryBasis!=='community'&&recentRelease(product.releasedOn,now))items.set(compact(product.maker+product.name),product);
  }
  const pending=[...candidates.entries()].filter(([key])=>!items.has(key)).map(([,candidate])=>{
    const match=primary.find(url=>checks[url]?.mentionedNames?.includes(compact(candidate.name)))||[...(candidateLinks.get(compact(candidate.name))||[])].find(url=>checks[url]);
    const failure=checks[match||candidate.newsURL]?.error;
    return {...candidate,reason:failure||candidate.reason,officialURL:match};
  }).slice(0,16);
  for(const url of primary)if(checks[url]?.error)errors.push(`${publisher(url)?.name}：${checks[url].error}`);
  // Discovery and popularity do not depend on an official publication timestamp.
  // The board keeps the separate, stricter seven-day official-release filter.
  const currentKnown=[...knownProducts,...items.values(),...(previous.items||[])];
  const uniqueKnown=new Map<string,DiscoveredProduct>();
  for(const product of currentKnown) {
    const key=compact(product.maker)+':'+compact(product.name);
    // A prior unnamed-maker guess should not compete with a now-curated identity.
    if(product.maker==='开发者 / 社区'&&[...uniqueKnown.values()].some(p=>compact(p.name)===compact(product.name)))continue;
    if(!uniqueKnown.has(key))uniqueKnown.set(key,product);
  }
  for(const product of discoverCommunityProducts(current,[...uniqueKnown.values()],now)) {
    const existing=[...items.entries()].find(([,p])=>p.name.toLowerCase()===product.name.toLowerCase()&&p.maker.toLowerCase()===product.maker.toLowerCase());
    const value=existing?{...product,...existing[1],signals:product.signals,relatedNews:product.relatedNews,firstSeenAt:product.firstSeenAt,lastSeenAt:product.lastSeenAt}:product;
    items.set(existing?.[0]||compact(product.maker+product.name),value);
  }
  const retained=Object.fromEntries(Object.entries(checks).filter(([,v])=>+now-Date.parse(v.checkedAt)<8*86400_000));
  const retainedLinks=Object.fromEntries(Object.entries(linkChecks).filter(([,v])=>+now-Date.parse(v.checkedAt)<8*86400_000));
  return {checkedAt:now.toISOString(),items:[...items.values()],pending,errors:[...new Set(errors)],checks:retained,linkChecks:retainedLinks};
}
