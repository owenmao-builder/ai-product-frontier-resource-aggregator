import { createHash } from 'node:crypto';
import type { DiscoveredProduct } from './product-discovery.js';

export interface ModelTrendsCache {
  checkedAt: string;
  items: DiscoveredProduct[];
  error?: string;
}

const endpoint = 'https://huggingface.co/api/models?sort=trendingScore&limit=50&full=true';
const hour = 3600_000;
const maxBytes = 4 * 1024 * 1024;
const officialOwners: Record<string, string> = {
  qwen: '阿里 / Qwen', 'deepseek-ai': 'DeepSeek', 'meta-llama': 'Meta', facebook: 'Meta',
  nvidia: 'NVIDIA', mistralai: 'Mistral', google: 'Google', 'google-deepmind': 'Google',
  microsoft: 'Microsoft', openai: 'OpenAI', apple: 'Apple', 'zai-org': '智谱', thudm: '智谱',
};
const tasks: Record<string, string> = {
  'text-generation': '文本生成', 'text2text-generation': '文本转换', 'fill-mask': '掩码文本补全',
  'text-classification': '文本分类', 'token-classification': '文本标注', 'sentence-similarity': '文本相似度',
  'feature-extraction': '特征提取', 'text-to-image': '文生图', 'image-to-image': '图像转换',
  'image-text-to-text': '图文理解', 'visual-question-answering': '视觉问答', 'image-classification': '图像分类',
  'automatic-speech-recognition': '语音识别', 'text-to-speech': '语音合成', 'text-to-audio': '音频生成',
  'audio-classification': '音频分类', 'image-to-video': '图生视频', 'text-to-video': '文生视频',
  'reinforcement-learning': '强化学习', robotics: '机器人',
};

function modelID(raw: unknown): string | undefined {
  if (typeof raw !== 'string') return;
  const parts = raw.split('/');
  if (parts.length !== 2 || parts.some(part => !/^[A-Za-z0-9][A-Za-z0-9._-]{0,95}$/.test(part) || /\.\.|--|[.-]$/.test(part))) return;
  return raw;
}

function modelURLID(raw: string): string | undefined {
  try {
    const url = new URL(raw);
    if (!['https:', 'http:'].includes(url.protocol) || url.hostname !== 'huggingface.co' || url.port || url.username || url.password) return;
    return modelID(url.pathname.replace(/^\//, '').replace(/\/$/, ''));
  } catch { return; }
}

function key(id: string): string {
  const [owner, name] = id.split('/');
  return owner.toLowerCase() + '/' + name;
}

function knownProduct(id: string, known: DiscoveredProduct[]): DiscoveredProduct | undefined {
  return known.find(product => [modelURLID(product.homepage), modelURLID(product.sourceURL), ...product.aliases.map(alias => modelID(alias) || modelURLID(alias))]
    .some(candidate => candidate !== undefined && key(candidate) === key(id)));
}

function validAge(timestamp: string | undefined, now: Date, max: number): boolean {
  const age = +now - Date.parse(timestamp || '');
  return Number.isFinite(age) && age >= 0 && age <= max;
}

function enhanceKnown(product: DiscoveredProduct, known: DiscoveredProduct[]): DiscoveredProduct {
  const trend = product.signals?.find(signal => signal.kind === 'huggingface');
  const id = trend && modelURLID(trend.url);
  const edited = id ? knownProduct(id, known) : undefined;
  if (!edited) return product;
  return {
    ...product, ...edited,
    aliases: [...new Set([...edited.aliases, ...(id ? [id] : [])])],
    signals: [...(edited.signals || []).filter(signal => signal.kind !== 'huggingface'), ...(trend ? [trend] : [])],
  };
}

async function fetchModelTrends(): Promise<unknown> {
  const response = await fetch(endpoint, {
    redirect: 'error', signal: AbortSignal.timeout(12_000),
    headers: { Accept: 'application/json', 'User-Agent': 'AI-Product-Frontier-Resource-Aggregator' },
  });
  if (!response.ok) throw new Error(`Hugging Face HTTP ${response.status}`);
  if (Number(response.headers.get('content-length')) > maxBytes) {
    await response.body?.cancel();
    throw new Error('Hugging Face 趋势响应超过 4 MB');
  }
  const reader = response.body?.getReader();
  if (!reader) throw new Error('Hugging Face 趋势响应为空');
  const chunks: Uint8Array[] = [];
  let length = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    length += value.byteLength;
    if (length > maxBytes) {
      await reader.cancel();
      throw new Error('Hugging Face 趋势响应超过 4 MB');
    }
    chunks.push(value);
  }
  return JSON.parse(Buffer.concat(chunks).toString('utf8')) as unknown;
}

interface TrendingModel {
  id: string;
  author: string;
  trendingScore: number;
  pipeline_tag?: string;
  likes?: number;
}

function validatePayload(payload: unknown): TrendingModel[] {
  if (!Array.isArray(payload)) throw new Error('Hugging Face 趋势响应不是模型列表');
  return payload.slice(0, 50).map((value: unknown) => {
    if (!value || typeof value !== 'object') throw new Error('Hugging Face 趋势缺少模型信息');
    const item = value as Record<string, unknown>;
    const id = modelID(item.id);
    if (!id || typeof item.author !== 'string' || item.author.toLowerCase() !== id.split('/')[0].toLowerCase() ||
      typeof item.trendingScore !== 'number' || !Number.isFinite(item.trendingScore)) {
      throw new Error('Hugging Face 趋势缺少有效模型标识、作者或趋势分');
    }
    return {
      id, author: item.author, trendingScore: item.trendingScore,
      ...(typeof item.pipeline_tag === 'string' ? { pipeline_tag: item.pipeline_tag } : {}),
      ...(typeof item.likes === 'number' && Number.isSafeInteger(item.likes) && item.likes >= 0 ? { likes: item.likes } : {}),
    };
  });
}

/** The trend timestamp is an observation, never an inferred model release date. */
export async function refreshModelTrends(previous: ModelTrendsCache | undefined, known: DiscoveredProduct[], now: Date,
  read: () => Promise<unknown> = fetchModelTrends): Promise<ModelTrendsCache> {
  if (previous && !previous.error && validAge(previous.checkedAt, now, hour - 1)) {
    return { ...previous, items: previous.items.filter(product => product.signals?.some(signal => signal.kind === 'huggingface' && validAge(signal.observedAt, now, 24 * hour)))
      .map(product => enhanceKnown(product, known)) };
  }
  try {
    const models = validatePayload(await read());
    const seen = new Set<string>();
    const observedAt = now.toISOString();
    const items: DiscoveredProduct[] = [];
    for (const [index, model] of models.entries()) {
      if (model.trendingScore <= 0 || seen.has(key(model.id))) continue;
      seen.add(key(model.id));
      const url = `https://huggingface.co/${model.id}`;
      const task = tasks[model.pipeline_tag || ''];
      const old = previous?.items.find(product => modelURLID(product.homepage) === model.id || product.signals?.some(signal => signal.kind === 'huggingface' && modelURLID(signal.url) === model.id));
      const product: DiscoveredProduct = {
        id: 'hf-' + createHash('sha256').update(key(model.id)).digest('hex').slice(0, 16),
        name: model.id, maker: officialOwners[model.author.toLowerCase()] || model.author,
        major: Boolean(officialOwners[model.author.toLowerCase()]), category: '模型更新',
        summary: `Hugging Face 近期趋势中的${task ? task + '模型' : 'AI 模型'}，来自 ${model.author}。具体任务与使用说明请查看模型卡。`,
        difference: `这是 ${model.id} 的具体模型仓库；版本、训练方式与能力差异以该模型卡为准。`,
        access: '通过模型卡查看权重、许可协议和运行说明。', homepage: url, sourceURL: url,
        aliases: [model.id], discoveredAutomatically: true, discoveryBasis: 'community',
        dateBasis: 'Hugging Face 趋势观测时间，不代表模型首发日期。',
        firstSeenAt: validAge(old?.firstSeenAt, now, Infinity) ? old!.firstSeenAt : observedAt, lastSeenAt: observedAt,
        signals: [{ kind: 'huggingface', label: `Hugging Face 趋势 #${index + 1}`,
          title: `HF近期趋势榜 · ${model.id}${model.likes !== undefined ? `（点赞总数 ${model.likes.toLocaleString('zh-CN')}）` : ''}`,
          url, observedAt }],
      };
      items.push(enhanceKnown(product, known));
    }
    return { checkedAt: observedAt, items };
  } catch (error) {
    const items = (previous?.items || []).flatMap(product => {
      const signals = (product.signals || []).filter(signal => signal.kind !== 'huggingface' || validAge(signal.observedAt, now, 24 * hour));
      if (!signals.some(signal => signal.kind === 'huggingface')) return [];
      return [enhanceKnown({ ...product, signals }, known)];
    });
    return {
      checkedAt: previous && validAge(previous.checkedAt, now, Infinity) ? previous.checkedAt : '', items,
      error: 'HF 趋势拉取失败：' + (error instanceof Error ? error.message : String(error)),
    };
  }
}
