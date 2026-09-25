import { createHash } from 'node:crypto';
import type { ArchiveItem } from './types.js';
import type { DiscoveredProduct } from './product-discovery.js';

type Signal = {kind:string;label:string;title:string;url:string;observedAt:string;sourceCount?:number};
type Product = DiscoveredProduct & {repository?:string;discoveryBasis?:'official'|'community';firstSeenAt?:string;lastSeenAt?:string;signals?:Signal[];relatedNews?:{title:string;url:string;date:string}[]};
type News = ArchiveItem & {content_text?:string;content_links?:string[];source_publication?:{publishedAt:string}};
interface Repository {url:string;owner:string;name:string;kind:'github'|'huggingface'}
interface Candidate {product:Product;aliases:string[];repositories:Set<string>;known:boolean}
interface Parsed {item:News;title:string;text:string;time:number;repository?:Repository;names:string[];links:Repository[]}
const normalize=(s:string)=>s.toLowerCase().replace(/[‐‑–—]/g,'-').replace(/(?<!\d)\.|\.(?!\d)/g,'').replace(/[^a-z0-9.\p{Script=Han}]/gu,'');
const escape=(s:string)=>s.replace(/[.*+?^${}()|[\]\\]/g,'\\$&');
const aiContext=/\b(?:ai|llms?|agents?|models?|inference|decision|neural|machine learning|copilot|diffusion|transformers?)\b|人工智能|智能体|模型|决策|推理|智能工具|智能助手/i;
const action=/\b(?:introducing|introduces?|launch(?:ed|es|ing)?|releases?|released|unveil(?:ed|s)?|open.sourc(?:ed|ing))\b|开源|发布|推出|上线/i;
const speculation=/传闻|疑似|或将|拟推出|计划发布|即将发布|考虑发布|\b(?:rumou?r|considering|plans? to|might|may release|coming soon)\b/i;
const finance=/融资|估值|股价|市值|\b(?:raises? \$|funding round|valuation|stock price)\b/i;
const generic=/^(?:ai|llm|agent|agents|model|models|tool|tools|framework|system one|decision model|world model|new model|open source|ai agents?|ai models?|openai|anthropic|google|meta|microsoft|nvidia|qwen|deepseek|claude|chatgpt|gemini|llama|our|we|the|this|introducing|show hn|github|hugging face|agentic ai|mac|ios|android|windows|linux|api|sdk|cli|training|day 0|projects|hub|vibe|arm|java|python|youtube|cloudflare|spacexai|typesafe ai|oppo|meta connect|palo alto networks|tether|kimi)$/i;
const officialAccounts=new Set(['aiatmeta','meta','metaai','muse','muse_ai','openai','openaidevs','chatgpt','anthropicai','claudeai','googledeepmind','googleai','qwenlm','alibaba_qwen','deepseek_ai','zai_org','tencenthunyuan','spacexai','mistralai','nvidia','huggingface','typesafeai']);
const temporalPhrase=/^(?:today|tomorrow|yesterday|tonight|now|soon|later|currently|recently|finally|already|here|there|this week|next week|last week|this month|next month|earlier today)$/i;
const categoryWords=new Set('ai artificial intelligence llm llms large language foundation world decision reasoning generative general multimodal personal coding knowledge custom agentic autonomous intelligent smart open source real time realtime voice video image text web deep learning machine models model agent agents assistant assistants tool tools framework frameworks system systems engine engines feature features mode modes feed feeds apps app search generation inference'.split(' '));
const broadCategory=(name:string)=>{const words=name.toLowerCase().split(/[ -]+/);return words.length>1&&words.every(word=>categoryWords.has(word));};
// Consumer device families mentioned in a mixed news roundup are not new AI products.
const consumerDevice=/^(?:Watch\s+[A-Z]?\d|Find\s+X\d|iPhone\b|iPad\b|Pixel\s+\d|Galaxy\s+[A-Z]?\d|Enco\s+[A-Z]?\d)/i;
const standaloneModifier=/^(?:pro|max|mini|lite|flash|base|preview|plus|ultra|beta|alpha|experimental|instruct|thinking|fast|small|medium|large|hack)$/i;
function validName(raw:string):string|undefined {
  const name=raw.replace(/^["'“‘`\s]+|["'”’`\s,，:：;；]+$/g,'').replace(/[‐‑–—]/g,'-').trim();
  if(name.length<2||name.length>72||generic.test(name)||standaloneModifier.test(name)||temporalPhrase.test(name)||broadCategory(name)||consumerDevice.test(name)||/^\d|https?:|^www\./i.test(name))return;
  if(/(?:-like|-style)$|\b(?:and|versus|vs|raises|funding|launches|released|introducing|built|based|using|powered|first|new|best|open source)\b/i.test(name))return;
  return name;
}
function repoOf(raw:string):Repository|undefined {
  try {
    const u=new URL(/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(raw)?'https://github.com/'+raw:raw);if(!/^https?:$/.test(u.protocol)||u.username||u.password)return;
    const host=u.hostname.toLowerCase().replace(/^www\./,'');let parts=u.pathname.split('/').filter(Boolean);
    if(host==='github.com') {
      if(parts.length<2||/^(?:topics|trending|search|collections|marketplace|orgs|users|features|settings)$/i.test(parts[0]))return;
      const name=parts[1].replace(/\.git$/,'');if(!validName(name))return;
      return {url:`https://github.com/${parts[0]}/${name}`,owner:parts[0],name,kind:'github'};
    }
    if(host==='huggingface.co') {
      if(parts[0]==='spaces')parts=parts.slice(1);
      else if(/^(?:datasets|blog|collections|posts|papers|docs|models|organizations|join|login|api)$/.test(parts[0]||''))return;
      if(parts.length<2||!validName(parts[1]))return;
      const space=u.pathname.startsWith('/spaces/')?'spaces/':'';
      return {url:`https://huggingface.co/${space}${parts[0]}/${parts[1]}`,owner:parts[0],name:parts[1],kind:'huggingface'};
    }
  }catch{/* Malformed article links do not establish a product. */}
  return;
}
function canonicalURL(raw:string):string {
  try {const u=new URL(raw);u.hash='';u.hostname=u.hostname.replace(/^www\./,'').replace(/^twitter\.com$/,'x.com');for(const key of [...u.searchParams.keys()])if(/^utm_|^(?:ref|source|s|t|ref_src)$/.test(key))u.searchParams.delete(key);return u.href.replace(/\/$/,'');}catch{return raw;}
}
const namePatterns=new Map<string,RegExp>();
function boundaryIndex(text:string,name:string):number {
  let regexp=namePatterns.get(name);
  if(!regexp){const pattern=escape(name).replace(/(?:\\-| )+/g,'[ \\-‐‑–—]*');regexp=new RegExp(`(^|[^a-z0-9])(${pattern})(?![a-z0-9]|\\.\\d|-[a-z0-9])`,'i');if(namePatterns.size>2048)namePatterns.clear();namePatterns.set(name,regexp);}
  const match=regexp.exec(text);
  return match?match.index+match[1].length:-1;
}
function namesIn(text:string):string[] {
  const names:string[]=[];
  const named=(raw:string)=>{if(normalize(raw)==='customfeeds'&&/\bYouTube\b/i.test(text))return 'YouTube Custom Feeds';if(temporalPhrase.test(raw)){const full=new RegExp('\\b'+escape(raw)+' (?:AI|Agent|Studio|Code)\\b').exec(text);if(full)return validName(full[0]);}return validName(raw);};
  // A name stops before prose; dots and hyphens inside versions stay intact.
  const token='[A-Z][A-Za-z0-9]*(?:[.-][A-Za-z0-9]+)*';
  const name=`${token}(?:[ -](?:${token}|[0-9]+(?:\\.[0-9]+)*(?:[BM])?)){0,4}`;
  const completed=new RegExp(`^\\s*(${name})\\s*(?:正式)?(?:发布|上线|开源)(?=[：:，,。.!]|$)`).exec(text);
  if(completed){const value=validName(completed[1]);if(value)return [value];}
  for(const re of [
    new RegExp(`\\b(?:[Ii]ntroducing|[Mm]eet|[Ll]aunching|[Rr]eleased?|[Rr]eleases|[Uu]nveils?|[Ll]aunched?|[Ll]aunches|[Oo]pen-sourcing)\\s+(?:(?:a|an|the|our|new)\\s+)*(${name})`,'g'),
    new RegExp(`(?:发布(?!会)|推出|上线|开源)(?:了)?[：:、\\s]*(?:(?:一个|一款|全新|新的|新|轻量|小型|推理|决策|多模态|人工智能|AI|开源|模型|工具|框架|智能体|家族)[：:、\\s]*){0,7}(${name})`,'g'),
    new RegExp(`(?:模型|工具|智能体|框架)(?:名为|叫做|叫|：|:|\\s+)\\s*(${name})`,'g'),
    new RegExp(`^\\s*Show HN:\\s*(${name})(?=\\s*[:：—–-]|\\s+(?:is|lets|for|an?|the)\\b|$)`,'i'),
  ])for(const m of text.matchAll(re.global?re:new RegExp(re.source,re.flags+'g'))){const n=named(m[1]);if(n)names.push(n);}
  // Explicit product names may precede their release verb (e.g. Nova 2.1 正式上线).
  for(const m of text.matchAll(new RegExp(`(?:^|[。！!?；;\\n])\\s*(${name})\\s*(?:正式)?(?:正式上线|已发布|is now available|has launched)`,'g'))){const n=named(m[1]);if(n)names.push(n);}
  return [...new Set(names)].filter(n=>!names.some(other=>other!==n&&(other.startsWith(n+' ')||other.startsWith(n+'-')||(!/[ -]/.test(n)&&other.endsWith(' '+n)))));
}
function textTitle(item:News):string{return item.title_original||item.title_en||item.title;}
function parse(item:News):Parsed {
  const title=textTitle(item);const text=[title,item.title,item.content_text?.slice(0,14000)].filter(Boolean).join('\n');
  const repository=repoOf(item.url);
  const links=(item.content_links||[]).slice(0,60).flatMap(url=>{const r=repoOf(url);return r?[r]:[];});
  const names=!speculation.test(title)&&!finance.test(title)&&aiContext.test(text)?namesIn(title):[];
  // Full RSS paragraphs can introduce a product even if a roundup headline does not.
  if(!names.length&&!speculation.test(title)&&!finance.test(title)) {
    for(const sentence of (item.content_text||'').slice(0,14000).split(/[。!！?？;；\n]/).slice(0,70)) {
      if(action.test(sentence)&&aiContext.test(sentence)&&!speculation.test(sentence)&&!finance.test(sentence))names.push(...namesIn(sentence));
    }
  }
  return {item,title,text,time:Date.parse(item.source_publication?.publishedAt||item.published_at||item.first_seen_at),repository,names:[...new Set(names)],links};
}
function isIncidental(text:string,index:number):boolean {
  const prefix=text.slice(Math.max(0,index-90),index);
  return /(?:\b(?:based on|built on|powered by|inspired by|compared (?:to|with)|versus|vs\.?|outperforms?|beats?|instead of)|基于|使用|利用|用|搭载|接入|调用|类|类似|复刻|重现|重建|克隆|底座(?:是|为)?|对比|相比|超过|超越|兼容|受.{0,12}启发|复刻|替代)\s*(?:[A-Za-z0-9' -]{0,25})$/i.test(prefix);
}
function mentions(text:string,candidates:Candidate[]):{candidate:Candidate;index:number;length:number}[] {
  const found=candidates.flatMap(candidate=>{
    const hits=candidate.aliases.flatMap(alias=>{const index=boundaryIndex(text,alias);return index<0?[]:[{candidate,index,length:alias.length}];});
    return hits.sort((a,b)=>a.index-b.index||b.length-a.length).slice(0,1);
  }).sort((a,b)=>a.index-b.index||b.length-a.length);
  // Longest identity owns overlapping text: Muse Realtime Avatar cannot heat Muse.
  return found.filter((hit,i)=>!found.some((other,j)=>i!==j&&other.index<=hit.index&&other.index+other.length>=hit.index+hit.length&&(other.length>hit.length||(other.length===hit.length&&other.candidate!==hit.candidate))));
}
interface Outlet {id:string;name:string;hosts:string[];match:RegExp}
const outlets:Outlet[]=[
  ['ithome.com','IT之家',['ithome.com'],'IT之家|ITHome'],
  ['aibase.com','AIbase',['aibase.com'],'AIbase'],
  ['36kr.com','36氪',['36kr.com'],'36氪|36Kr'],
  ['qbitai.com','量子位',['qbitai.com'],'量子位'],
  ['jiqizhixin.com','机器之心',['jiqizhixin.com'],'机器之心'],
  ['geekpark.net','极客公园',['geekpark.net'],'极客公园|GeekPark'],
  ['ifanr.com','爱范儿',['ifanr.com'],'爱范儿|ifanr'],
  ['huxiu.com','虎嗅',['huxiu.com'],'虎嗅(?:App)?|Huxiu'],
  ['wallstreetcn.com','华尔街见闻',['wallstreetcn.com'],'华尔街见闻'],
  ['woshipm.com','人人都是产品经理',['woshipm.com'],'人人都是产品经理'],
  ['theverge.com','The Verge',['theverge.com'],'The Verge'],
  ['techcrunch.com','TechCrunch',['techcrunch.com'],'TechCrunch'],
  ['thenextweb.com','The Next Web',['thenextweb.com'],'The Next Web'],
  ['wsj.com','WSJ',['wsj.com'],'WSJ|Wall Street Journal|华尔街日报'],
  ['reuters.com','Reuters',['reuters.com','reut.rs'],'Reuters|路透社|路透'],
  ['nytimes.com','New York Times',['nytimes.com','nyti.ms'],'New York Times|The New York Times|纽约时报'],
  ['businessinsider.com','Business Insider',['businessinsider.com'],'Business Insider'],
  ['bloomberg.com','Bloomberg',['bloomberg.com'],'Bloomberg|彭博'],
  ['wired.com','Wired',['wired.com'],'Wired|连线'],
  ['axios.com','Axios',['axios.com'],'Axios'],
  ['cnbc.com','CNBC',['cnbc.com'],'CNBC'],
  ['engadget.com','Engadget',['engadget.com'],'Engadget'],
  ['techradar.com','TechRadar',['techradar.com'],'TechRadar'],
  ['bbc.com','BBC',['bbc.com','bbc.co.uk'],'BBC'],
].map(([id,name,hosts,aliases])=>({id:id as string,name:name as string,hosts:hosts as string[],match:new RegExp('^(?:'+aliases+')(?:$|[\\s·（(｜|/-])','i')}));
const aggregateHosts=['techmeme.com','news.google.com','readhub.cn','readhub.me','tophub.today','newsnow.busiyi.world','top.baidu.com'];
const aggregatedSource=/^(?:Readhub|Techmeme|TopHub|NewsNow|百度(?:[ ·（(].*)?|Baidu)(?:$|[\s·（(｜|/-])/i;
function isHost(host:string,domain:string):boolean{return host===domain||host.endsWith('.'+domain);}
function source(item:News,product:Product):{id:string;kind:'x'|'media'|'community'}|undefined {
  let url:URL;try{url=new URL(item.url);}catch{return;}
  const host=url.hostname.toLowerCase().replace(/^www\./,'');
  if(host==='x.com'||host==='twitter.com') {
    const handle=url.pathname.split('/')[1]?.toLowerCase();
    if(!handle||['i','search','home'].includes(handle)||!url.pathname.includes('/status/'))return;
    const owner=product.repository?repoOf(product.repository)?.owner.toLowerCase():undefined;
    if(officialAccounts.has(handle)||handle===owner||normalize(handle)===normalize(product.maker))return;
    return {id:`x:${handle}`,kind:'x'};
  }
  if(/\b(?:官方|Official)\b/i.test(item.source)||item.source.includes('官方'))return;
  const originHosts=[product.homepage,product.sourceURL].flatMap(raw=>{try{return [new URL(raw).hostname.replace(/^www\./,'')];}catch{return [];}});
  if(product.discoveryBasis!=='community'&&originHosts.includes(host)&&!['github.com','huggingface.co'].includes(host))return;
  if(host==='news.ycombinator.com'||/^(?:Hacker News|hackernews|HN)(?:\b|\s|$)/i.test(item.source))return {id:'community:hn',kind:'community'};
  if(aggregateHosts.some(domain=>isHost(host,domain))||aggregatedSource.test(item.source))return;
  const outlet=outlets.find(o=>o.hosts.some(domain=>isHost(host,domain))||o.match.test(item.source.trim()));
  if(outlet)return {id:'media:'+outlet.id,kind:'media'};
  if(host==='github.com'||host==='huggingface.co')return;
  if(host==='v2ex.com')return {id:'community:v2ex',kind:'community'};
  if(host==='reddit.com')return {id:'community:reddit',kind:'community'};
  if(['mp.weixin.qq.com','medium.com','youtube.com','bilibili.com'].some(domain=>isHost(host,domain))) {
    const author=item.source.trim();
    if(!author||author.includes(host)||/^(?:News|RSS|微信公众号|YouTube)$/i.test(author))return;
    return {id:`community:${host}:${normalize(author)}`,kind:'community'};
  }
  return {id:`media:${host}`,kind:'media'};
}


function modelShortForms(name:string):string[] {
  // These are named Claude model lines with a version, not arbitrary last words.
  const match=/^Claude[ -]+((?:Opus|Sonnet|Haiku|Fable)[ -]*\d+(?:\.\d+)*(?:[ -]+(?:Preview|Thinking))?)$/i.exec(name);
  return match?[match[1]]:[];
}
function charmContext(text:string):boolean {
  return /\b(?:Meta|Muse)\b/i.test(text)&&boundaryIndex(text,'Charm')>=0&&!/charm offensive/i.test(text);
}
function contextualCandidate(name:string,text:string,candidates:Candidate[]):Candidate|undefined {
  if(normalize(name)==='customfeeds'&&/\bYouTube\b/i.test(text)&&boundaryIndex(text,'Custom Feeds')>=0)return candidates.find(c=>c.product.name==='YouTube Custom Feeds');
  return normalize(name)==='charm'&&charmContext(text)?candidates.find(c=>normalize(c.product.name)==='musecharm'):undefined;
}
function consolidateCanonical(candidates:Candidate[]):void {
  for(const canonical of [...candidates]) {
    const aliases=modelShortForms(canonical.product.name);
    const isCharm=normalize(canonical.product.name)==='musecharm';
    if(!aliases.length&&!isCharm)continue;
    canonical.aliases=[...new Set([...canonical.aliases,...aliases])];
    canonical.product={...canonical.product,aliases:[...new Set([...canonical.product.aliases,...aliases])]};
    for(const other of [...candidates]) {
      if(other===canonical)continue;
      const modelAlias=aliases.some(alias=>normalize(alias)===normalize(other.product.name));
      const contextualCharm=isCharm&&normalize(other.product.name)==='charm'&&charmContext(other.product.summary);
      if(!modelAlias&&!contextualCharm)continue;
      // A separately attributed creator or repository can be a different product.
      if(other.repositories.size&&![...other.repositories].some(r=>canonical.repositories.has(r)))continue;
      if(other.product.maker!=='开发者 / 社区'&&other.product.maker!==canonical.product.maker)continue;
      for(const repository of other.repositories)canonical.repositories.add(repository);
      candidates.splice(candidates.indexOf(other),1);
    }
  }
}
function sourceName(id:string,item:News):string {
  if(id.startsWith('x:'))return '@'+id.slice(2);
  if(id==='community:hn')return 'Hacker News';
  if(id==='community:v2ex')return 'V2EX';
  if(id==='community:reddit')return 'Reddit';
  const outlet=outlets.find(o=>id==='media:'+o.id);if(outlet)return outlet.name;
  return item.source&&!/^(?:News|Test|RSS)$/i.test(item.source)?item.source:id.replace(/^media:/,'');
}

/** Discover named products locally, then attribute recent discussion to its actual subject. */
export function discoverCommunityProducts(news:ArchiveItem[],known:DiscoveredProduct[],now:Date):DiscoveredProduct[] {
  const current=news.filter(item=>{const n=item as News;const time=Date.parse(n.source_publication?.publishedAt||n.published_at||n.first_seen_at);return Number.isFinite(time)&&time>=+now-7*86400_000&&time<=+now;}).map(item=>parse(item));
  const candidates:Candidate[]=known.filter(product=>Boolean(validName(product.name))).map(product=>({product:product as Product,aliases:[...new Set([product.name,...product.aliases])].sort((a,b)=>b.length-a.length),repositories:new Set([product.homepage,product.sourceURL,(product as Product).repository].flatMap(raw=>{const r=raw&&repoOf(raw);return r?[canonicalURL(r.url)]:[];})),known:true}));
  consolidateCanonical(candidates);
  const byName=()=>{const map=new Map<string,Candidate>();const ambiguous=new Set<string>();for(const c of candidates)for(const alias of c.aliases){const key=normalize(alias);if(map.has(key)&&map.get(key)!==c)ambiguous.add(key);else map.set(key,c);}for(const key of ambiguous)map.delete(key);return map;};
  let names=byName();
  for(const article of current) {
    if(speculation.test(article.title)||finance.test(article.title)||/^\s*RT\s+@/i.test(article.title))continue;
    const repositories=article.repository?[article.repository]:article.links.filter(r=>{
      const position=article.text.toLowerCase().indexOf(r.name.toLowerCase());
      return position>=0&&!isIncidental(article.text,position)&&action.test(article.text)&&aiContext.test(article.text);
    });
    const established=article.names.length?article.names:repositories.length&&(aiContext.test(article.text)||article.repository?.kind==='huggingface')?repositories.map(r=>r.name):[];
    for(const raw of established) {
      const name=validName(raw);if(!name)continue;
      const position=boundaryIndex(article.title,name);if(position>=0&&isIncidental(article.title,position))continue;
      const unversioned=name.replace(/[ -]v?\d+(?:\.\d+)*(?:[BM])?$/i,'');
      const repository=repositories.find(r=>normalize(r.name)===normalize(name)||normalize(r.name)===normalize(unversioned))||(article.repository&&established.length===1?article.repository:undefined);
      const named=contextualCandidate(name,article.text,candidates)||names.get(normalize(name));
      const existing=(named&&(!repository||named.repositories.has(canonicalURL(repository.url)))?named:undefined)||(repository&&candidates.find(c=>c.repositories.has(canonicalURL(repository.url))));
      if(existing){if(repository)existing.repositories.add(canonicalURL(repository.url));continue;}
      const url=repository?.url||article.item.url;
      const product={id:'community-'+createHash('sha256').update(repository?canonicalURL(repository.url):normalize(name)).digest('hex').slice(0,16),name,maker:name==='YouTube Custom Feeds'?'YouTube':repository?.owner||'开发者 / 社区',major:false,category:/model|模型|决策/i.test(article.text)?'模型更新':'Agent 与工具',summary:`报道提及 ${name}：${article.item.title.slice(0,200)}`,difference:'社区报道中的具体 AI 产品；功能与相对其他产品的区别请展开查看原始报道。',access:repository?'通过项目主页查看代码、权重和使用方法。':'通过原始报道查看产品与使用入口。',homepage:url,sourceURL:article.item.url,aliases:[name,...(repository?[repository.name]:[])],repository:repository?.kind==='github'?repository.url:undefined,discoveredAutomatically:true,discoveryBasis:'community',dateBasis:'首次发现来自社区报道，未确认官方首发日期。'} as Product;
      const candidate={product,aliases:product.aliases,repositories:new Set(repository?[canonicalURL(repository.url)]:[]),known:false};candidates.push(candidate);names=byName();
    }
  }
  consolidateCanonical(candidates);names=byName();
  const articlesByCandidate=new Map<Candidate,Parsed[]>();
  for(const article of current) {
    if(/^\s*RT\s+@/i.test(article.title))continue;
    let subjects:Candidate[]=[];
    if(article.repository)subjects=candidates.filter(c=>c.repositories.has(canonicalURL(article.repository!.url)));
    if(!subjects.length&&article.names.length)subjects=article.names.flatMap(n=>{const c=contextualCandidate(n,article.text,candidates)||names.get(normalize(n));return c?[c]:[];});
    if(!subjects.length){const c=contextualCandidate('Custom Feeds',article.title,candidates);if(c)subjects=[c];}
    if(!subjects.length&&charmContext(article.title)){const c=contextualCandidate('Charm',article.title,candidates);if(c)subjects=[c];}
    if(!subjects.length) {
      const found=mentions(article.title,candidates).filter(h=>{
        if((!h.candidate.known||h.candidate.product.discoveryBasis==='community')&&/^[A-Za-z]+$/.test(h.candidate.product.name)&&!aiContext.test(article.text))return false;
        const tail=article.title.slice(h.index+h.length);
        const specificSuffix=/^[ -]+(?:[A-Z][A-Za-z0-9.-]*|[0-9]+(?:\.[0-9]+)*)(?:[ -]|$)/.test(tail)&&!/^ +(Is|Has|Goes|Hits|Climbs|Launches|Releases|Review|Saves)\b/.test(tail);
        return !isIncidental(article.title,h.index)&&!specificSuffix;
      });
      if(found.length)subjects=[found[0].candidate];
    }
    // Only explicit introductions in the body establish attribution; an arbitrary
    // background mention or a linked base checkpoint never lends its heat.
    for(const candidate of new Set(subjects)) {
      const entries=articlesByCandidate.get(candidate)||[];entries.push(article);articlesByCandidate.set(candidate,entries);
    }
  }
  const result:Product[]=[];
  for(const [candidate,entries] of articlesByCandidate) {
    const sorted=entries.sort((a,b)=>b.time-a.time);const urls=new Set<string>(),titles=new Set<string>();
    const unique=[...sorted].sort((a,b)=>Number(Boolean(source(b.item,candidate.product)))-Number(Boolean(source(a.item,candidate.product)))).filter(a=>{const url=canonicalURL(a.item.url),title=normalize(a.title);if(urls.has(url)||titles.has(title))return false;urls.add(url);titles.add(title);return true;}).sort((a,b)=>b.time-a.time);
    const external=new Map<string,{article:Parsed;kind:string;name:string}>();
    for(const article of unique){const s=source(article.item,candidate.product);if(s&&!external.has(s.id))external.set(s.id,{article,kind:s.kind,name:sourceName(s.id,article.item)});}
    const signals:Signal[]=[];const latest=sorted[0],first=sorted[sorted.length-1];
    const externalEntries=[...external.values()].sort((a,b)=>b.article.time-a.article.time);
    if(external.size>=2){const recent=externalEntries[0].article;signals.push({kind:'community',label:`${external.size} 家集中报道`,title:'近7天报道来源：'+externalEntries.map(s=>s.name).join('、'),url:recent.item.url,observedAt:new Date(recent.time).toISOString(),sourceCount:external.size});}
    const x=externalEntries.filter(s=>s.kind==='x');
    if(x.length>=2){const recent=x[0].article;signals.push({kind:'x',label:`X · ${x.length} 位作者讨论`,title:'讨论作者：'+x.map(s=>s.name).join('、'),url:recent.item.url,observedAt:new Date(recent.time).toISOString(),sourceCount:x.length});}
    result.push({...candidate.product,discoveryBasis:candidate.product.discoveryBasis||(candidate.known?'official':'community'),firstSeenAt:new Date(Math.min(first.time,Date.parse(candidate.product.firstSeenAt||'')||first.time)).toISOString(),lastSeenAt:new Date(latest.time).toISOString(),signals:[...(candidate.product.signals||[]).filter(s=>s.kind!=='community'&&s.kind!=='x'),...signals],relatedNews:unique.slice(0,20).map(a=>({title:a.item.title,url:a.item.url,date:new Date(a.time).toISOString()}))});
  }
  return result.sort((a,b)=>(b.signals?.find(s=>s.kind==='community')?.sourceCount||0)-(a.signals?.find(s=>s.kind==='community')?.sourceCount||0)||String(b.lastSeenAt).localeCompare(String(a.lastSeenAt)));
}
