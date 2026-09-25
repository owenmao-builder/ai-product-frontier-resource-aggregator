import { afterEach, describe, expect, it, vi } from 'vitest';
import { fetchSingleFeed, rssContentContext } from '../src/fetchers/opml-rss';
import { archiveContentContext, mergeCollected } from '../src/collection';

describe('RSS product context', () => {
  afterEach(() => vi.unstubAllGlobals());

  it('preserves the longest substantive body and its original product links', () => {
    const context = rssContentContext({
      content: '<p>New decision models are available.</p>',
      contentSnippet: 'New decision models are available.',
      'content:encoded': '<p>Our new open source decision model <strong>Sprout-1</strong> is available.</p><p>Code: <a href="https://github.com/lab/sprout">GitHub</a>; demo: https://sprout.example.org/demo.</p>',
      summary: '<p>Short summary.</p>',
    }, 'https://x.com/researcher/status/123');
    expect(context.content_text).toBe('Our new open source decision model Sprout-1 is available. Code: GitHub; demo: https://sprout.example.org/demo.');
    expect(context.content_links).toEqual(['https://github.com/lab/sprout', 'https://sprout.example.org/demo']);
  });

  it('removes scripts and styles even if the parser copied them into a snippet', () => {
    const script = 'window.secret = "https://unrelated.example.com/tracker";';
    const style = '.hidden { display: none; }';
    const context = rssContentContext({
      content: `<script>${script}</script><style>${style}</style><p>Introducing Sprout-1.</p>`,
      contentSnippet: `${script} ${style} Introducing Sprout-1.`,
      summary: '<template><a href="https://hidden.example.com">hidden</a></template>',
    }, 'https://x.com/researcher/status/123');
    expect(context.content_text).toBe('Introducing Sprout-1.');
    expect(context.content_links).toBeUndefined();
  });

  it('bounds stored text and links, rejects nonpublic targets, and resolves actual relative links', () => {
    const context = rssContentContext({ content: `<p>${'模'.repeat(7000)}</p>` +
      '<a href="/releases/sprout">Release</a><a href="javascript:alert(1)">Script</a><a href="http://127.0.0.1/repo">Local</a>' +
      '<a href="http://localhost/repo">Local</a><a href="https://secret:password@example.com">Credentials</a>' +
      '<a href="https://github.com/lab/repo">Code</a><a href="https://github.com/lab/repo">Code</a>' +
      Array.from({ length: 20 }, (_, i) => `<a href="https://models.example.com/${i}">Model</a>`).join('')
    }, 'https://models.example.com/posts/123');
    expect(context.content_text).toHaveLength(6000);
    expect(context.content_links).toHaveLength(12);
    expect(context.content_links?.slice(0, 2)).toEqual(['https://models.example.com/releases/sprout', 'https://github.com/lab/repo']);
    expect(context.content_links?.some(link => /localhost|127\.0\.0\.1|password|javascript/.test(link))).toBe(false);
    expect(archiveContentContext({ content_text: 42, content_links: ['file:///tmp/repo', null] })).toEqual({});
  });

  it('carries full RSS bodies through collection without altering the title or publication time', async () => {
    const now = new Date('2026-09-25T05:00:00Z');
    const xml = `<?xml version="1.0"?><rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/"><channel><title>AI researcher</title><link>https://x.com/researcher</link><description>Feed</description><item><title>New decision model…</title><link>https://x.com/researcher/status/123</link><pubDate>Fri, 25 Sep 2026 04:00:00 GMT</pubDate><description>Short excerpt</description><content:encoded><![CDATA[<p>Today we release Sprout-1, an open source decision model.</p><a href="https://github.com/lab/sprout">Source code</a>]]></content:encoded></item></channel></rss>`;
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(new Response(xml, { status: 200 })));
    const result = await fetchSingleFeed({ title: 'AI researcher', xmlUrl: 'https://feeds.example.com/researcher', htmlUrl: 'https://x.com/researcher' }, now, false);
    expect(result.status.ok).toBe(true);
    expect(result.items).toHaveLength(1);
    const archived = mergeCollected([], result.items, now)[0];
    expect(archived).toMatchObject({ title: 'New decision model…', published_at: '2026-09-25T04:00:00.000Z',
      content_text: 'Today we release Sprout-1, an open source decision model. Source code', content_links: ['https://github.com/lab/sprout'] });
  });
});
