import {describe,expect,it} from 'vitest';
import {evidenceFor,matchesScore,ratingFor,scoreOf} from '../web/src/lib/ratings';
import type {NewsItem} from '../web/src/types';

describe('interest scores in the dashboard',()=>{
  const item={rating:{version:'interest-v1',score:7.4,evidenceLevel:'C',method:'interest-rule',reason:'用户关注标准',tags:[],assessedAt:'',dimensions:[{key:'model_change',value:4,weight:30,reason:'模型升级'}]}} as NewsItem;
  it('shows a score and passes the high-score filter without evidence A/B',()=>{
    expect(scoreOf(item)).toBe(7.4);expect(matchesScore(item,7)).toBe(true);
    expect(evidenceFor(item).label).toBe('C 不足');
    expect(evidenceFor(item).explanation).not.toContain('暂不评分');
    expect(ratingFor(item).dimensions?.[0].weight).toBe(30);
  });
  it('keeps historical evidence assessments readable and rejects invalid scores',()=>{
    expect(scoreOf({...item,rating:{...item.rating!,version:'importance-v2',score:8,evidenceLevel:'A'}})).toBe(8);
    expect(scoreOf({...item,rating:{...item.rating!,score:NaN}})).toBeNull();
    expect(scoreOf({...item,rating:{...item.rating!,score:11}})).toBeNull();
  });
});
