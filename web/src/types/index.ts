export interface NewsRating {
  score?: number | null
  reason: string
  tags: string[]
  method: string
  assessedAt: string
  model?: string | null
  version?: string
  category?: string
  evidenceLevel?: string
  dimensions?: {key:string; value:number; reason:string}[]
  sources?: {url:string; title:string; quote:string}[]
  comparison?: string | null
  gaps?: string[]
  chineseTitle?: string
  highlights?: string[]
  release?: {kind:string; publisher:string; url:string; quote:string; reason:string} | null
}

export interface NewsItem {
  id: string
  site_id: string
  site_name: string
  source: string
  title: string
  url: string
  published_at: string | null
  first_seen_at: string
  last_seen_at: string
  title_original: string
  title_en: string | null
  title_zh: string | null
  title_bilingual: string
  rating?: NewsRating
}

export interface SiteStat {
  site_id: string
  site_name: string
  count: number
  raw_count: number
}

export interface NewsData {
  generated_at: string
  window_hours: number
  total_items: number
  total_items_ai_raw: number
  total_items_raw: number
  total_items_all_mode: number
  topic_filter: string
  archive_total: number
  site_count: number
  source_count: number
  site_stats: SiteStat[]
  items: NewsItem[]
  direct_sources?: DirectFeedStatus[]
  product_board?: ProductBoard
}

export interface AIProduct {
  id: string
  name: string
  maker: string
  major: boolean
  category: string
  summary: string
  difference: string
  access: string
  homepage: string
  sourceURL: string
  aliases: string[]
  releasedOn?: string
  releaseKind?: string
  repository?: string
  signals?: {kind: string; label: string; title: string; url: string; observedAt: string}[]
  relatedNews?: {title: string; url: string; date: string}[]
}

export interface ProductBoard {
  verifiedAt: string
  items: AIProduct[]
  checkedAt?: string
  githubFetchedAt?: string
  hnFetchedAt?: string
  errors?: Record<string, string>
}

export interface DirectFeedStatus {
  id: string
  checkedAt?: string
  fetchedAt?: string
  error?: string
  windowCount: number
  latestTitle?: string
  latestURL?: string
  latestPublishedAt?: string
}

export interface SourceStatus {
  generated_at: string
  sites: SiteStatus[]
  successful_sites: number
  failed_sites: string[]
  zero_item_sites: string[]
  fetched_raw_items: number
  items_before_topic_filter: number
  items_in_24h: number
}

export interface SiteStatus {
  site_id: string
  site_name: string
  ok: boolean
  item_count: number
  duration_ms: number
  error: string | null
}
