import {describe,expect,it} from 'vitest'
import {isFreshProductSignal,isRecentMajorRelease,mergeProductCatalog,visibleProducts,withProductReporting} from '../web/src/lib/products'
import type {AIProduct,ProductBoard,ProductDiscovery,ProductSignal} from '../web/src/types'

const now=Date.parse('2026-09-25T02:00:00Z')
const signal:ProductSignal={kind:'x',label:'X · 3 位作者讨论',title:'甲、乙、丙',url:'https://x.com/author/status/123',observedAt:'2026-09-22T03:00:00Z',sourceCount:3}
const product:AIProduct={id:'community-kev',name:'Kev',maker:'Cognition',major:false,category:'决策模型',summary:'讨论摘要',difference:'社区提到可本地运行',access:'查看来源',homepage:signal.url,sourceURL:signal.url,aliases:['Kev'],discoveryBasis:'community',firstSeenAt:signal.observedAt,lastSeenAt:signal.observedAt,signals:[signal],relatedNews:[{title:'Kev 决策模型开源',url:signal.url,date:signal.observedAt}]}
const discovery=(items:AIProduct[]):ProductDiscovery=>({checkedAt:new Date(now).toISOString(),items,pending:[],errors:[]})
const empty:ProductBoard={verifiedAt:'',items:[]}

describe('community product discovery on the board',()=>{
  it('admits an unknown product without an official release date and retains discussion evidence',()=>{
    const board=mergeProductCatalog(empty,discovery([product]),now)
    expect(visibleProducts(withProductReporting(board,[],now),now)).toEqual([product])
    expect(isRecentMajorRelease(product,now)).toBe(false)
    expect(product.releasedOn).toBeUndefined()
  })
  it('keeps recent candidates available for a later GitHub/HN match without declaring them hot',()=>{
    const candidate={...product,signals:[]}
    const board=mergeProductCatalog(empty,discovery([candidate]),now)
    expect(board.items).toHaveLength(1)
    expect(visibleProducts(board,now)).toHaveLength(0)
    expect(mergeProductCatalog(empty,discovery([{...candidate,lastSeenAt:'2026-09-17T02:00:00Z'}]),now).items).toHaveLength(0)
  })
  it('adds community heat to a curated entry while preserving its identity and official facts',()=>{
    const curated={...product,id:'curated-kev',discoveryBasis:'official' as const,summary:'编辑说明',difference:'编辑比较',releasedOn:'2026-09-20',releaseKind:'新模型',sourceURL:'https://github.com/jaredpalmer/kev',signals:[],relatedNews:[]}
    const result=mergeProductCatalog({...empty,items:[curated]},discovery([product,product]),now)
    expect(result.items).toHaveLength(1)
    expect(result.items[0]).toMatchObject({id:curated.id,summary:curated.summary,difference:curated.difference,releasedOn:curated.releasedOn,sourceURL:curated.sourceURL,discoveryBasis:'official',signals:[signal],relatedNews:product.relatedNews})
    expect(withProductReporting(result,[],now).items[0].signals).toEqual([signal])
  })
  it('shows an older Meta Muse as hot but excludes it from major-vendor new releases',()=>{
    const muse={...product,id:'meta-muse',name:'Muse',maker:'Meta',major:true,aliases:['Meta Muse'],discoveryBasis:'official' as const,releasedOn:'2026-09-08',releaseKind:'新工具'}
    expect(visibleProducts({...empty,items:[muse]},now)).toHaveLength(1)
    expect(isRecentMajorRelease(muse,now)).toBe(false)
    expect(visibleProducts({...empty,items:[{...muse,signals:[]}]},now)).toHaveLength(0)
    expect(isRecentMajorRelease({...muse,releasedOn:'2026-09-24'},now)).toBe(true)
    expect(isRecentMajorRelease({...muse,releasedOn:'2026-09-24',discoveryBasis:'community'},now)).toBe(false)
  })
  it('keeps Muse, Muse Realtime Avatar and different numeric model versions separate',()=>{
    const named=(name:string)=>({...product,id:name,name,aliases:[name]})
    const items=['Muse','Muse Realtime Avatar','Model3.8','Model38','OpenJev','Jev'].map(named)
    expect(mergeProductCatalog(empty,discovery(items),now).items.map(i=>i.name)).toEqual(items.map(i=>i.name))
  })
  it('expires discussion after seven days while keeping the shorter GitHub/HN observation lifetime',()=>{
    expect(isFreshProductSignal({...signal,observedAt:new Date(now-7*86400000).toISOString()},now)).toBe(true)
    for(const observedAt of ['invalid',new Date(now+1).toISOString(),new Date(now-7*86400000-1).toISOString()]) {
      expect(visibleProducts({...empty,items:[{...product,signals:[{...signal,observedAt}]}]},now)).toHaveLength(0)
    }
    expect(isFreshProductSignal({...signal,kind:'hn'},now)).toBe(false)
    expect(isFreshProductSignal({...signal,kind:'community'},now)).toBe(true)
  })
  it('promotes a community entry when an official release is confirmed without losing its discussion',()=>{
    const official={...product,id:'release-kev',major:true,discoveryBasis:'official' as const,releasedOn:'2026-09-24',releaseKind:'新模型',homepage:'https://example.com/kev',sourceURL:'https://example.com/kev',signals:[]}
    const board=mergeProductCatalog({...empty,items:[product]},discovery([official]),now)
    expect(board.items[0]).toMatchObject({id:product.id,discoveryBasis:'official',sourceURL:official.sourceURL,releasedOn:official.releasedOn,signals:[signal]})
    expect(isRecentMajorRelease(board.items[0],now)).toBe(true)
  })
  it('accepts a Hugging Face trend without a launch date and expires it after 24 hours',()=>{
    const hf={...signal,kind:'huggingface',label:'Hugging Face 趋势 #2',url:'https://huggingface.co/team/model',observedAt:new Date(now).toISOString(),sourceCount:undefined}
    const item={...product,signals:[hf]}
    expect(visibleProducts(mergeProductCatalog(empty,discovery([item]),now),now)).toHaveLength(1)
    expect(isRecentMajorRelease({...item,major:true},now)).toBe(false)
    expect(isFreshProductSignal(hf,now+86400000)).toBe(true)
    expect(isFreshProductSignal(hf,now+86400001)).toBe(false)
  })
  it('does not merge family members that share their announcement URL or generic alias',()=>{
    const names=['Model2.5','Model25','Model2.5 Pro']
    const items=names.map(name=>({...product,id:name,name,aliases:['Model'],sourceURL:'https://example.com/model-family'}))
    expect(mergeProductCatalog(empty,discovery(items),now).items.map(i=>i.name)).toEqual(names)
  })
  it('keeps only safe, recent, distinct discussion links before rendering',()=>{
    const valid=product.relatedNews![0]
    const unsafe={...valid,url:'javascript:alert(1)'}
    const future={...valid,url:'https://x.com/author/status/124',date:new Date(now+1).toISOString()}
    const old={...valid,url:'https://x.com/author/status/125',date:new Date(now-7*86400000-1).toISOString()}
    const board=visibleProducts({...empty,items:[{...product,relatedNews:[valid,valid,unsafe,future,old]}]},now)
    expect(board[0].relatedNews).toEqual([valid])
  })

  it('keeps homonymous GitHub repositories, HF models and named makers separate',()=>{
    const nova={...product,name:'Nova',aliases:['Nova'],maker:'Shared vendor'}
    const cases:[AIProduct,AIProduct][]=[
      [{...nova,id:'gh-alice',repository:'alice/Nova'},{...nova,id:'gh-bob',repository:'https://github.com/bob/Nova/tree/main'}],
      [{...nova,id:'hf-alice',homepage:'https://huggingface.co/alice/Nova'},{...nova,id:'hf-bob',homepage:'https://huggingface.co/bob/Nova/tree/main'}],
      [{...nova,id:'maker-alice',maker:'Alice Labs'},{...nova,id:'maker-bob',maker:'Bob Labs'}]
    ]
    for(const [first,second] of cases) {
      const result=mergeProductCatalog({...empty,items:[first]},discovery([second]),now)
      expect(result.items.map(item=>item.id)).toEqual([first.id,second.id])
    }
    const same=mergeProductCatalog({...empty,items:[{...nova,repository:'alice/Nova'}]},discovery([{...nova,id:'other-id',repository:'https://github.com/alice/Nova/tree/main'}]),now)
    expect(same.items).toHaveLength(1)
  })
  it('lets an unknown community maker become the official maker without changing the card identity',()=>{
    const unknown={...product,maker:'开发者 / 社区'}
    const official={...product,id:'official-kev',maker:'Cognition',major:true,discoveryBasis:'official' as const,releasedOn:'2026-09-24',releaseKind:'新模型',homepage:'https://github.com/jaredpalmer/kev',repository:'jaredpalmer/kev',sourceURL:'https://example.com/kev'}
    const result=mergeProductCatalog({...empty,items:[unknown]},discovery([official]),now)
    expect(result.items).toHaveLength(1)
    expect(result.items[0]).toMatchObject({id:unknown.id,maker:'Cognition',discoveryBasis:'official',repository:official.repository,signals:[signal]})
  })

})
