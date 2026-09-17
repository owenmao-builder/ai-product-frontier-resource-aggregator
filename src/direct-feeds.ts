import { readFileSync } from 'node:fs';
import type { OpmlFeed } from './types.js';

interface DirectFeed {
  name: string;
  feedURL: string;
  homeURL: string;
}

// Shared with the Mac app and source catalog; no private OPML is required.
const directFeeds: DirectFeed[] = JSON.parse(readFileSync(new URL('../feeds/direct-feeds.json', import.meta.url), 'utf8'));

export function withDirectFeeds(feeds: OpmlFeed[]): OpmlFeed[] {
  const subscriptions = new Map<string, OpmlFeed>();
  for (const feed of feeds) subscriptions.set(feed.xmlUrl, feed);
  for (const feed of directFeeds) subscriptions.set(feed.feedURL, { title: feed.name, xmlUrl: feed.feedURL, htmlUrl: feed.homeURL });
  return [...subscriptions.values()];
}
