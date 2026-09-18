import type { RawItem } from '../types.js';
import { BaseFetcher } from './base.js';

interface WPPost {
  id: number;
  date: string;
  date_gmt?: string;
  title: { rendered: string };
  link: string;
}

const WINDOW_DAYS = 7;
const MAX_PER_PAGE = 100;

export function xinzhiyuanPublishedAt(post: Pick<WPPost, 'date' | 'date_gmt'>): Date | null {
  // WordPress date is site-local; date_gmt is UTC, but neither includes an offset.
  // Never let the collector machine's timezone decide how to interpret them.
  for (const [raw, offset] of [[post.date_gmt, 'Z'], [post.date, '+08:00']]) {
    if (!raw || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})?$/.test(raw)) continue;
    const date = new Date(/(?:Z|[+-]\d{2}:\d{2})$/.test(raw) ? raw : raw + offset);
    if (Number.isFinite(date.getTime())) return date;
  }
  return null;
}

export class XinzhiyuanFetcher extends BaseFetcher {
  siteId = 'xinzhiyuan';
  siteName = '新智元';

  async fetch(now: Date): Promise<RawItem[]> {
    const windowStart = new Date(now.getTime() - WINDOW_DAYS * 24 * 60 * 60 * 1000);
    const items: RawItem[] = [];
    let page = 1;
    let hasMore = true;

    while (hasMore) {
      const url = `https://aiera.com.cn/wp-json/wp/v2/posts?per_page=${MAX_PER_PAGE}&page=${page}`;
      let posts: WPPost[];

      try {
        posts = await this.fetchJsonData<WPPost[]>(url);
      } catch {
        break;
      }

      if (posts.length === 0) break;

      for (const post of posts) {
        const publishedAt = xinzhiyuanPublishedAt(post);
        if (!publishedAt || publishedAt > now) continue;

        if (publishedAt < windowStart) {
          hasMore = false;
          break;
        }

        const title = post.title.rendered
          .replace(/&amp;/g, '&')
          .replace(/&quot;/g, '"')
          .replace(/&#39;/g, "'")
          .replace(/&lt;/g, '<')
          .replace(/&gt;/g, '>');

        items.push(
          this.createItem({
            source: '新智元',
            title,
            url: post.link,
            publishedAt,
            meta: { postId: post.id },
          })
        );
      }

      if (posts.length < MAX_PER_PAGE) break;
      page++;
    }

    return items;
  }
}
