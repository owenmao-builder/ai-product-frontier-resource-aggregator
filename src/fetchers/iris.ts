import Parser from 'rss-parser';
import type { RawItem } from '../types.js';
import { BaseFetcher } from './base.js';
import { fetchText } from '../utils/http.js';
import { parseDate } from '../utils/date.js';
import { firstNonEmpty } from '../utils/text.js';
import { CONFIG } from '../config.js';
import pLimit from 'p-limit';

export class IrisFetcher extends BaseFetcher {
  siteId = 'iris';
  siteName = 'Info Flow';

  async fetch(now: Date): Promise<RawItem[]> {
    const html = await fetchText('https://iris.findtruman.io/web/info_flow');
    const items: RawItem[] = [];

    const feedMatch = html.match(/const\s+feeds\s*=\s*\[(.*?)\]\s*;/s);
    if (!feedMatch) throw new Error('Info Flow 页面未提供订阅列表');

    const feedSection = feedMatch[1];
    const feedRegex = /\{\s*name:\s*'([^']+)'\s*,\s*url:\s*'([^']+)'\s*\}/g;
    const feeds: Array<{ name: string; url: string }> = [];

    let match;
    while ((match = feedRegex.exec(feedSection)) !== null) {
      feeds.push({ name: match[1], url: match[2] });
    }

    const parser = new Parser();

    const limit = pLimit(8);
    await Promise.all(feeds.map(feed => limit(async () => {
      try {
        const parsed = await parser.parseString(await fetchText(feed.url, { timeout: CONFIG.rss.feedTimeout }));
        const sourceName = firstNonEmpty(feed.name, parsed.title, 'Iris Feed');

        for (const entry of parsed.items || []) {
          const title = (entry.title || '').trim();
          const url = (entry.link || '').trim();
          if (!title || !url) continue;

          const publishedAt =
            parseDate(entry.pubDate, now) ||
            parseDate(entry.isoDate, now) ||
            null;

          items.push(
            this.createItem({
              source: sourceName,
              title,
              url,
              publishedAt,
              meta: { feed_url: feed.url },
            })
          );
        }
      } catch {
        return;
      }
    })));

    return items;
  }
}
