import type { ArchiveItem, RawItem, LatestPayload } from './types.js';
import { normalizeUrl } from './utils/url.js';
import { makeItemId } from './utils/hash.js';
import { isAiRelated } from './filters/ai-related.js';

export interface CollectionSource {
  id: string;
  name: string;
  kind: 'platform' | 'rss';
  url?: string;
  ok: boolean;
  checked_at: string;
  fetched_at?: string;
  latest_published_at?: string;
  item_count: number;
  error?: string;
  skipped?: boolean;
}

export interface CollectionStatus {
  mode: 'local';
  started_at: string;
  finished_at: string;
  sources: CollectionSource[];
}

type CollectedItem = ArchiveItem & { source_publication?: { publishedAt: string; verifiedAt: string; sourceURL: string } };

/** Retain richer feed context without replacing reviewed article identity or translations. */
export function archiveContentContext(meta: Record<string, unknown>, previous?: ArchiveItem): Pick<ArchiveItem, 'content_text' | 'content_links'> {
  const texts = [previous?.content_text, meta.content_text].filter((value): value is string => typeof value === 'string')
    .map(value => value.replace(/\s+/g, ' ').trim()).filter(Boolean).sort((a, b) => b.length - a.length);
  const links = [...(Array.isArray(meta.content_links) ? meta.content_links : []), ...(previous?.content_links || [])];
  const publicLinks = links.flatMap(value => {
    if (typeof value !== 'string') return [];
    try {
      const url = new URL(value);
      const host = url.hostname.toLowerCase();
      // Product source links use public domains. Do not preserve credentials or local network addresses.
      if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password || !host.includes('.') ||
        host.includes(':') || /^\d+(?:\.\d+){3}$/.test(host) || /(?:^|\.)(?:localhost|local|internal|invalid|test|onion)$/.test(host)) return [];
      return [url.href];
    } catch { return []; }
  });
  return {
    ...(texts.length ? { content_text: Array.from(texts[0]).slice(0, 6000).join('') } : {}),
    ...(publicLinks.length ? { content_links: [...new Set(publicLinks)].slice(0, 12) } : {}),
  };
}

function articleKey(raw: string): string {
  const normalized = normalizeUrl(raw);
  try {
    const url = new URL(normalized);
    if (['aibase.com', 'www.aibase.com'].includes(url.hostname) && /^\/(?:zh\/)?news\/\d+$/.test(url.pathname)) {
      return 'https://www.aibase.com' + url.pathname.replace(/^\/zh\/news\//, '/news/');
    }
  } catch { /* Invalid URLs are rejected by the caller. */ }
  return normalized;
}

function expiredDatedPath(item: CollectedItem, cutoff: number): boolean {
  if (item.source_publication || (item.published_at && item.site_id !== 'tophub')) return false;
  // A clearly old dated article path can reject an archive link, but does not invent a publication hour.
  try {
    const day = new URL(item.url).pathname.match(/(?:^|\/)((?:19|20)\d{2})[-/](\d{2})[-/](\d{2})(?=[-/\.]|$)/);
    if (!day) return false;
    const end = Date.parse(`${day[1]}-${day[2]}-${day[3]}T23:59:59+08:00`);
    return Number.isFinite(end) && end < cutoff;
  } catch { return false; }
}

export function mergeCollected(previous: ArchiveItem[], incoming: RawItem[], now: Date): CollectedItem[] {
  const byURL = new Map<string, CollectedItem>();
  for (const item of previous) {
    const url = articleKey(item.url);
    if (/^https?:\/\//.test(url) && item.id && item.title && !byURL.has(url)) byURL.set(url, { ...item });
  }
  for (const raw of incoming) {
    const url = normalizeUrl(raw.url);
    const title = raw.title.trim();
    if (!/^https?:\/\//.test(url) || !title) continue;
    const date = raw.publishedAt;
    if (date && (!Number.isFinite(+date) || date > now)) continue;
    const published = date?.toISOString() ?? null;
    const key = articleKey(url);
    const old = byURL.get(key);
    if (old) {
      Object.assign(old, archiveContentContext(raw.meta, old));
      old.last_seen_at = now.toISOString();
      if (published && raw.meta.time_basis === 'publisher_addtime') {
        old.source_publication = { publishedAt: published, verifiedAt: now.toISOString(), sourceURL: old.url };
      } else if (published && !old.published_at) old.published_at = published;
      // Preserve original IDs, headline fields, translations and rating fingerprints.
    } else {
      byURL.set(key, {id:makeItemId(raw.siteId,raw.source,title,url), site_id:raw.siteId, site_name:raw.siteName,
        source:raw.source, title, url, published_at:published, first_seen_at:now.toISOString(), last_seen_at:now.toISOString(),
        ...archiveContentContext(raw.meta)});
    }
  }
  const cutoff = +now - 7 * 86400_000;
  return [...byURL.values()].filter(item => {
    const date = Date.parse(item.source_publication?.publishedAt || item.published_at || item.first_seen_at);
    return Number.isFinite(date) && date >= cutoff && date <= +now && !expiredDatedPath(item, cutoff);
  });
}

export function collectionSnapshot(archive: CollectedItem[], status: CollectionStatus, hours: number): LatestPayload & {collection: CollectionStatus} {
  const cutoff = Date.parse(status.finished_at) - hours * 3600_000;
  const raw = archive.filter(item => Date.parse(item.source_publication?.publishedAt || item.published_at || item.first_seen_at) >= cutoff);
  const items = raw.filter(item => isAiRelated(item) || item.site_id === 'directrss');
  const groups = new Map<string, {site_id:string;site_name:string;count:number;raw_count:number}>();
  for (const source of status.sources.filter(s => s.kind === 'platform')) groups.set(source.id,{site_id:source.id,site_name:source.name,count:0,raw_count:0});
  for (const item of raw) {
    if (!groups.has(item.site_id)) groups.set(item.site_id,{site_id:item.site_id,site_name:item.site_name,count:0,raw_count:0});
    groups.get(item.site_id)!.raw_count++;
  }
  for (const item of items) groups.get(item.site_id)!.count++;
  items.sort((a,b) => Date.parse(b.source_publication?.publishedAt || b.published_at || b.first_seen_at) - Date.parse(a.source_publication?.publishedAt || a.published_at || a.first_seen_at));
  return {generated_at:status.finished_at,window_hours:hours,total_items:items.length,total_items_ai_raw:items.length,
    total_items_raw:raw.length,total_items_all_mode:raw.length,topic_filter:'ai_tech_robotics',archive_total:archive.length,
    site_count:groups.size,source_count:new Set(items.map(i=>i.source)).size,site_stats:[...groups.values()],items,collection:status};
}
