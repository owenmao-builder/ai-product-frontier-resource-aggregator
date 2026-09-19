import {describe,expect,it} from 'vitest'
import {eventArticles,eventIsRead,eventLabel,matchesEvent} from '../web/src/lib/events'
import type {NewsItem} from '../web/src/types'

const item = {id:'lead',title:'中文事件',url:'https://lead.test/1',site_id:'rss',source:'Leader',title_zh:null,event:{
  id:'event-1',title:'同一模型发布',articleCount:3,mediaCount:2,baseScore:7.4,bonus:0.3,read:false,memberIDs:['lead','b','c'],
  urls:['https://lead.test/1','https://second.test/1'],insights:[],reports:[
    {id:'a',name:'甲',kind:'media',focus:[],points:[],basis:'标题',articles:[{id:'lead',title:'新模型发布',source:'甲',siteID:'rss',url:'https://lead.test/1'}]},
    {id:'b',name:'乙',kind:'media',focus:['成本'],points:['价格下降'],basis:'标题',articles:[{id:'b',title:'低成本推理版本',source:'乙',siteID:'iris',url:'https://second.test/1'}]}
  ]
}} as NewsItem

describe('event cards across search, filters and read state',()=>{
  it('finds a secondary source without splitting the event into repeated rows',()=>{
    expect(matchesEvent(item,'iris','乙','成本')).toBe(true)
    expect(matchesEvent(item,'rss','乙','')).toBe(false)
    expect(matchesEvent(item,'all','all','低成本')).toBe(true)
    expect(matchesEvent(item,'all','不存在','')).toBe(false)
    expect(eventArticles(item)).toHaveLength(2)
  })
  it('keeps an event read even when another article becomes the lead',()=>{
    expect(eventIsRead(item,{'https://second.test/1':{}})).toBe(true)
    expect(eventIsRead({...item,event:{...item.event!,read:true}},{})).toBe(true)
    expect(eventIsRead(item,{})).toBe(false)
  })
  it('shows the reporting count for legacy events while preserving ungrouped news',()=>{
    expect(eventLabel(item)).toBe('2 家集中报道')
    const single={...item,event:undefined}
    expect(eventLabel(single)).toBe('')
    expect(matchesEvent(single,'rss','Leader','中文')).toBe(true)
    expect(eventIsRead(single,{'https://lead.test/1':{}})).toBe(true)
  })
  it('shows the reporting count without scoring details',()=>{
    const covered={...item,event:{...item.event!,bonus:0,coverage:{sourceCount:5,mediaCount:2,authorCount:3,windowHours:48,minimumScore:8.5,sourceIDs:['a','b'],sourceNames:['甲','乙']}}}
    expect(eventLabel(covered)).toBe('5 家集中报道')
    expect(eventLabel(covered)).not.toContain('+0')
    expect(eventLabel({...covered,event:{...covered.event,coverage:{...covered.event.coverage,sourceCount:1,minimumScore:0}}})).toBe('3 篇合并')
  })
})
