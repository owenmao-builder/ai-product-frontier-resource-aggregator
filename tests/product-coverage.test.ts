import {describe,expect,it} from 'vitest'
import {compareProducts,productReportingSignal,withProductReporting} from '../web/src/lib/products'
import type {AIProduct,NewsItem} from '../web/src/types'

const now=Date.parse('2026-09-19T04:00:00Z')
const product:AIProduct={id:'jev',name:'Jev',maker:'TypeSafe AI',major:false,category:'决策模型',summary:'',difference:'',access:'',homepage:'https://typesafe.ai/',sourceURL:'https://typesafe.ai/launch',aliases:['Jev','TypeSafe Jev'],releasedOn:'2026-09-15',releaseKind:'新模型'}
const eventNews={id:'story',title:'Jev 模型发布',url:'https://media.test/1',source:'报道',site_id:'rss',title_zh:null,event:{
  id:'jev-release',title:'Jev 模型发布',subject:'Jev',articleCount:6,mediaCount:2,bonus:1,read:false,
  reports:[],insights:[],memberIDs:['story'],urls:['https://media.test/1'],latestAt:'2026-09-19T03:00:00Z',
  coverage:{sourceCount:5,mediaCount:2,authorCount:3,windowHours:48,minimumScore:8.5,sourceIDs:['a','b','c','d','e'],sourceNames:['甲','乙','丙','丁','戊']}
}} as NewsItem

describe('news coverage in the product board',()=>{
  it('surfaces an independent model from reporting alone, without GitHub/HN signals',()=>{
    const board=withProductReporting({verifiedAt:'',items:[product]},[eventNews],now)
    expect(board.items[0].signals).toEqual([expect.objectContaining({kind:'coverage',label:'5 家集中报道',sourceCount:5})])
    expect(board.items[0].signals?.[0].title).toBe('报道来源：甲、乙、丙、丁、戊')
    const major={...product,id:'other',name:'Other',major:true}
    expect([major,board.items[0]].sort(compareProducts)[0].id).toBe('jev')
  })
  it('uses the concrete event subject instead of a competitor mention or newer version',()=>{
    for(const subject of ['OpenJev','Jev2','Another model']) {
      expect(productReportingSignal(product,[{...eventNews,event:{...eventNews.event!,subject}}],now)).toBeUndefined()
    }
    const official={...eventNews,event:{...eventNews.event!,subject:undefined,urls:[product.sourceURL]}}
    expect(productReportingSignal(product,[official],now)?.sourceCount).toBe(5)
    const versioned={...product,name:'Model3.8',aliases:['Model3.8']}
    expect(productReportingSignal(versioned,[{...eventNews,event:{...eventNews.event!,subject:'Model38'}}],now)).toBeUndefined()
  })
  it('excludes single-source, future and previous-day events and does not compound counts',()=>{
    for(const latestAt of ['2026-09-18T15:59:59Z','2026-09-19T05:00:00Z','invalid']) {
      expect(productReportingSignal(product,[{...eventNews,event:{...eventNews.event!,latestAt}}],now)).toBeUndefined()
    }
    const single={...eventNews,event:{...eventNews.event!,coverage:{...eventNews.event!.coverage!,sourceCount:1}}}
    expect(productReportingSignal(product,[single],now)).toBeUndefined()
    const first=withProductReporting({verifiedAt:'',items:[product]},[eventNews],now)
    expect(withProductReporting(first,[eventNews,eventNews],now).items[0].signals).toEqual(first.items[0].signals)
  })
  it('does not share heat between versions through a common announcement URL',()=>{
    const first={...product,name:'Model2.5',aliases:['Model2.5'],sourceURL:'https://example.com/model-family'}
    const second={...first,id:'model-25',name:'Model25',aliases:['Model25']}
    const shared={...eventNews,event:{...eventNews.event!,subject:second.name,urls:[first.sourceURL]}}
    expect(productReportingSignal(first,[shared],now,[first,second])).toBeUndefined()
    expect(productReportingSignal(second,[shared],now,[first,second])?.sourceCount).toBe(5)
    const unknown={...shared,event:{...shared.event,subject:undefined}}
    expect(productReportingSignal(first,[unknown],now,[first,second])).toBeUndefined()
    expect(productReportingSignal(second,[unknown],now,[first,second])).toBeUndefined()
  })

})
