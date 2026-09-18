import type { RawItem } from '../types.js';
import { BaseFetcher } from './base.js';
import { joinUrl } from '../utils/url.js';
import * as cheerio from 'cheerio';

// Read the publisher's structured payload as JSON; never execute page scripts.
export function parseAiBase(html: string, now: Date): RawItem[] {
  const $ = cheerio.load(html);
  const items = new Map<string, RawItem>();
  for (const script of $('script').toArray()) {
    const text = $(script).text();
    if (!text.includes('initialArticles')) continue;
    const start = text.indexOf('self.__next_f.push(');
    if (start < 0) continue;
    try {
      const flight = JSON.parse(text.slice(start + 'self.__next_f.push('.length, text.lastIndexOf(')')));
      if (typeof flight[1] !== 'string') continue;
      const payload: string = flight[1];
      const marker = payload.indexOf('"initialArticles":');
      if (marker < 0) continue;
      const from = payload.indexOf('[', marker);
      let depth = 0, quoted = false, escaped = false, end = -1;
      for (let i = from; i < payload.length; i++) {
        const c = payload[i];
        if (quoted) { if (escaped) escaped = false; else if (c === '\\') escaped = true; else if (c === '"') quoted = false; }
        else if (c === '"') quoted = true;
        else if (c === '[') depth++;
        else if (c === ']' && --depth === 0) { end = i + 1; break; }
      }
      if (end < 0) continue;
      for (const article of JSON.parse(payload.slice(from, end))) {
        if (!Number.isSafeInteger(article.Id) || article.Id <= 0 || typeof article.title !== 'string') continue;
        const raw = article.addtime;
        const publishedAt = typeof raw === 'string' && /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/.test(raw)
          ? new Date(raw.replace(' ', 'T') + '+08:00') : null;
        if (!publishedAt || !Number.isFinite(+publishedAt) || publishedAt > now) continue;
        const url = `https://www.aibase.com/zh/news/${article.Id}`;
        items.set(url, { siteId: 'aibase', siteName: 'AIbase', source: 'AIbase', title: article.title.trim(), url, publishedAt, meta: { time_basis: 'publisher_addtime', description: article.description } });
      }
    } catch { /* Try another JSON chunk, then retain an explicitly undated HTML fallback. */ }
  }
  $("a[href^='/news/'], a[href^='/zh/news/']").each((_, a) => {
    const title = $(a).find('h3').text().trim();
    const href = $(a).attr('href') || '';
    if (!title || !/^\/(?:zh\/)?news\/\d+$/.test(href)) return;
    const url = joinUrl('https://www.aibase.com', href.replace(/^\/news\//, '/zh/news/'));
    if (!items.has(url)) items.set(url, {siteId:'aibase', siteName:'AIbase', source:'AIbase', title, url, publishedAt:null, meta:{time_hint:$(a).find('div.text-sm.text-gray-400 span').first().text().trim()}});
  });
  return [...items.values()];
}

export class AiBaseFetcher extends BaseFetcher {
  siteId = 'aibase';
  siteName = 'AIbase';

  async fetch(now: Date): Promise<RawItem[]> {
    const $ = await this.fetchHtml('https://www.aibase.com/zh/news');
    const items = parseAiBase($.html(), now);
    if (!items.length) throw new Error('AIbase 页面未提供可解析的新闻');
    return items;
  }
}
