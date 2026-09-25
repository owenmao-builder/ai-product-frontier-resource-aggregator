import { afterEach, describe, expect, it, vi } from 'vitest';
import { refreshModelTrends, type ModelTrendsCache } from '../src/model-trends';
import type { DiscoveredProduct } from '../src/product-discovery';

const now = new Date('2026-09-25T04:00:00Z');
const model = (id: string, extra: Record<string, unknown> = {}) => ({ id, author: id.split('/')[0], trendingScore: 25,
  likes: 100, downloads: 50000, pipeline_tag: 'text-generation', createdAt: '2024-01-01T00:00:00Z', ...extra });
const known = (changes: Partial<DiscoveredProduct> = {}): DiscoveredProduct => ({ id: 'edited-model', name: 'Sprout 1', maker: 'Example Lab',
  major: false, category: '模型更新', summary: '人工整理的能力说明', difference: '人工整理的版本差异', access: '已有入口说明',
  homepage: 'https://example.com/sprout', sourceURL: 'https://huggingface.co/ExampleLab/Sprout-1', aliases: ['Sprout 1'],
  releasedOn: '2026-09-23', releaseKind: '新模型', discoveryBasis: 'official', ...changes });

describe('Hugging Face model trends', () => {
  afterEach(() => vi.unstubAllGlobals());

  it('discovers concrete model repositories with their actual rank and observed time', async () => {
    const result = await refreshModelTrends(undefined, [], now, async () => [model('Lab/Laya'), model('Zero/Idle', { trendingScore: 0 }), model('Other/openjev')]);
    expect(result.checkedAt).toBe(now.toISOString());
    expect(result.items.map(item => item.name)).toEqual(['Lab/Laya', 'Other/openjev']);
    expect(result.items[1]).toMatchObject({ discoveryBasis: 'community', major: false, homepage: 'https://huggingface.co/Other/openjev',
      signals: [{ kind: 'huggingface', label: 'Hugging Face 趋势 #3', observedAt: now.toISOString() }] });
    expect(result.items[0].summary).toContain('文本生成');
    expect(result.items[0].signals?.[0].title).toContain('点赞总数 100');
    expect(result.items[0].signals?.[0]).not.toHaveProperty('sourceCount');
    expect(result.items[0]).not.toHaveProperty('releasedOn');
  });

  it('enhances an exact known model without overwriting edited or official fields', async () => {
    const edited = known();
    const result = await refreshModelTrends(undefined, [edited], now, async () => [model('ExampleLab/Sprout-1')]);
    expect(result.items[0]).toMatchObject({ id: edited.id, name: edited.name, summary: edited.summary, difference: edited.difference,
      homepage: edited.homepage, releasedOn: edited.releasedOn, discoveryBasis: 'official', releaseKind: '新模型' });
    expect(result.items[0].aliases).toContain('ExampleLab/Sprout-1');
    expect(result.items[0].signals?.[0].url).toBe(edited.sourceURL);
  });

  it('matches exact owner/name aliases while separating variants and different authors', async () => {
    const edited = known({ sourceURL: 'https://example.com/announcement', aliases: ['ExampleLab/Sprout-1'] });
    const result = await refreshModelTrends(undefined, [edited], now, async () => [model('ExampleLab/Sprout-1'), model('ExampleLab/Sprout-1-GGUF'), model('OtherLab/Sprout-1')]);
    expect(result.items.map(item => item.id)).toEqual([edited.id, expect.stringMatching(/^hf-/), expect.stringMatching(/^hf-/)]);
    expect(new Set(result.items.map(item => item.id)).size).toBe(3);
    expect(result.items[1].name).toBe('ExampleLab/Sprout-1-GGUF');
    expect(result.items[2].name).toBe('OtherLab/Sprout-1');
    expect(result.items[1].aliases).not.toContain('Sprout-1');
    const nearURL = known({ sourceURL: 'https://huggingface.co/ExampleLab/Sprout-1/tree/main', aliases: ['Sprout-1'] });
    const unmatched = await refreshModelTrends(undefined, [nearURL], now, async () => [model('ExampleLab/Sprout-1')]);
    expect(unmatched.items[0].id).not.toBe(nearURL.id);
  });

  it('uses exact official owners rather than a model name or an owner substring', async () => {
    const result = await refreshModelTrends(undefined, [], now, async () => [model('Qwen/Qwen3-4B'), model('community/Qwen3-4B'), model('Qwen-community/Qwen3-4B'), model('meta-llama/Llama-3')]);
    expect(result.items.map(item => item.major)).toEqual([true, false, false, true]);
    expect(result.items[0].maker).toBe('阿里 / Qwen');
    expect(result.items.every(item => item.releasedOn === undefined && item.discoveryBasis === 'community')).toBe(true);
  });

  it('uses a successful cache for one hour without advancing observation times', async () => {
    const initial = await refreshModelTrends(undefined, [], now, async () => [model('Lab/Laya')]);
    const read = vi.fn(async () => [model('Lab/New')]);
    const cached = await refreshModelTrends(initial, [], new Date(+now + 59 * 60_000), read);
    expect(read).not.toHaveBeenCalled();
    expect(cached.checkedAt).toBe(initial.checkedAt);
    expect(cached.items[0].signals?.[0].observedAt).toBe(initial.checkedAt);
    await refreshModelTrends(initial, [], new Date(+now + 3600_000), read);
    expect(read).toHaveBeenCalledOnce();
  });

  it('retains recent cached signals on failure without pretending they were refreshed', async () => {
    const initial = await refreshModelTrends(undefined, [], now, async () => [model('Lab/Laya')]);
    const failed = await refreshModelTrends(initial, [], new Date(+now + 2 * 3600_000), async () => { throw new Error('HTTP 503'); });
    expect(failed.error).toContain('503');
    expect(failed.checkedAt).toBe(initial.checkedAt);
    expect(failed.items[0].signals?.[0].observedAt).toBe(initial.checkedAt);
    const read = vi.fn(async () => [model('Lab/Recovered')]);
    const recovered = await refreshModelTrends({ ...failed, checkedAt: new Date(+now + 90 * 60_000).toISOString() }, [], new Date(+now + 2 * 3600_000), read);
    expect(read).toHaveBeenCalledOnce();
    expect(recovered.error).toBeUndefined();
  });

  it('expires failed signals after 24 hours and rejects future cached observations', async () => {
    const initial = await refreshModelTrends(undefined, [], now, async () => [model('Lab/Laya')]);
    const fail = async () => { throw new Error('offline'); };
    expect((await refreshModelTrends(initial, [], new Date(+now + 24 * 3600_000 + 1), fail)).items).toEqual([]);
    const future: ModelTrendsCache = { ...initial, checkedAt: new Date(+now + 3600_000).toISOString(),
      items: initial.items.map(item => ({ ...item, signals: item.signals?.map(signal => ({ ...signal, observedAt: new Date(+now + 3600_000).toISOString() })) })) };
    const result = await refreshModelTrends(future, [], now, fail);
    expect(result.items).toEqual([]);
    expect(result.checkedAt).toBe('');
    expect(result.error).toContain('offline');
  });

  it.each([{}, null, [{ id: 'Lab/Model', author: 'Lab' }], [model('../unsafe')], [model('Lab/evil%2Fpath')], [model('Lab/Model', { author: 'Other' })], [model('Lab/Model', { trendingScore: Number.NaN })]])('reports malformed payloads instead of generating products: %j', async payload => {
    const result = await refreshModelTrends(undefined, [], now, async () => payload);
    expect(result.items).toEqual([]);
    expect(result.checkedAt).toBe('');
    expect(result.error).toContain('HF 趋势拉取失败');
  });

  it('caps results at 50 and ignores duplicate repositories and nonpositive scores', async () => {
    const input = [model('Lab/Repeated'), model('Lab/Repeated'), model('Lab/Negative', { trendingScore: -1 }), ...Array.from({ length: 60 }, (_, i) => model(`Lab/Model-${i}`))];
    const result = await refreshModelTrends(undefined, [], now, async () => input);
    expect(result.items).toHaveLength(48);
    expect(result.items.at(-1)?.signals?.[0].label).toBe('Hugging Face 趋势 #50');
  });

  it('fetches only the fixed public API, rejects redirects, and limits streamed response size', async () => {
    const fetch = vi.fn().mockResolvedValue(new Response(JSON.stringify([model('Lab/Laya')]), { status: 200 }));
    vi.stubGlobal('fetch', fetch);
    const result = await refreshModelTrends(undefined, [], now);
    expect(result.items).toHaveLength(1);
    expect(fetch).toHaveBeenCalledWith('https://huggingface.co/api/models?sort=trendingScore&limit=50&full=true', expect.objectContaining({ redirect: 'error', signal: expect.any(AbortSignal) }));
    fetch.mockResolvedValueOnce(new Response(' '.repeat(4 * 1024 * 1024 + 1), { status: 200 }));
    expect((await refreshModelTrends(undefined, [], now)).error).toContain('超过 4 MB');
    fetch.mockResolvedValueOnce(new Response('Forbidden', { status: 403 }));
    expect((await refreshModelTrends(undefined, [], now)).error).toContain('HTTP 403');
  });
});
