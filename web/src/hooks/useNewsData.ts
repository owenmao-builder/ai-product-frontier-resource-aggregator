import { useState, useEffect, useMemo, useCallback, useRef } from 'react'
import type { NewsData, NewsItem, SiteStat } from '../types'
import { matchesScore, scoreOf, ratingFor } from '../lib/ratings'
import { compareNewsTimes } from '../lib/newsTime'
import { resolveSourceTimes } from '../lib/sourceTimes'

export interface SourceStat {
  source: string
  count: number
}

export type TimeRange = '24h' | '7d'

interface UseNewsDataReturn {
  data: NewsData | null
  loading: boolean
  error: string | null
  filteredItems: NewsItem[]
  siteStats: SiteStat[]
  sourceStats: SourceStat[]
  searchQuery: string
  setSearchQuery: (query: string) => void
  selectedSite: string
  setSelectedSite: (site: string) => void
  selectedSource: string
  setSelectedSource: (source: string) => void
  loadMore: () => void
  hasMore: boolean
  displayCount: number
  refresh: () => void
  timeRange: TimeRange
  setTimeRange: (range: TimeRange) => void
  isSwitching: boolean
  minScore: number
  setMinScore: (value: number) => void
  selectedCategory: string
  setSelectedCategory: (value:string) => void
  sortBy: 'score' | 'time'
  setSortBy: (value: 'score' | 'time') => void
  scoring: boolean
  aiError: string | null
  lastChecked: string | null
}

const PAGE_SIZE = 50

export function useNewsData(): UseNewsDataReturn {
  const [data, setData] = useState<NewsData | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [searchQuery, setSearchQuery] = useState('')
  const [selectedSite, setSelectedSite] = useState('all')
  const [selectedSource, setSelectedSource] = useState('all')
  const [displayCount, setDisplayCount] = useState(PAGE_SIZE)
  const [timeRange, setTimeRange] = useState<TimeRange>('24h')
  const [isSwitching, setIsSwitching] = useState(false)
  const [minScore, setMinScore] = useState(0)
  const [selectedCategory, setSelectedCategory] = useState('all')
  const [sortBy, setSortBy] = useState<'score' | 'time'>('score')
  const [scoring, setScoring] = useState(false)
  const [aiError, setAiError] = useState<string | null>(null)
  const [lastChecked, setLastChecked] = useState<string | null>(null)
  const rangeRef = useRef(timeRange)
  rangeRef.current = timeRange
  
  const preloadedDataRef = useRef<{ [key in TimeRange]?: NewsData }>({})
  const isInitialLoadRef = useRef(true)
  const abortControllerRef = useRef<AbortController | null>(null)

  useEffect(() => {
    if (!window.__AI_NATIVE__) return
    const listener = (event: Event) => {
      const payload = (event as CustomEvent).detail
      if (payload.range !== rangeRef.current) return
      if (payload.data) {
        setData(payload.data)
        preloadedDataRef.current[payload.range as TimeRange] = payload.data
        isInitialLoadRef.current = false
      }
      setLoading(Boolean(payload.loading))
      setIsSwitching(false)
      setError(payload.error || null)
      setAiError(payload.aiError || null)
      setScoring(Boolean(payload.scoring))
      setLastChecked(payload.lastChecked || null)
    }
    window.addEventListener('ai-news-native', listener)
    return () => window.removeEventListener('ai-news-native', listener)
  }, [])

  const fetchData = useCallback(async (range: TimeRange, isPreload = false, force = false) => {
    if (window.__AI_NATIVE__) {
      if (!isPreload) {
        setError(null)
        window.webkit?.messageHandlers.newsBridge.postMessage({action: force ? 'refresh' : 'load', range})
      }
      return
    }
    if (preloadedDataRef.current[range] && !isPreload && !force) {
      setData(preloadedDataRef.current[range]!)
      setLoading(false)
      setIsSwitching(false)
      return
    }

    if (!isPreload) {
      if (abortControllerRef.current) {
        abortControllerRef.current.abort()
      }
      abortControllerRef.current = new AbortController()
      
      if (isInitialLoadRef.current) {
        setLoading(true)
      } else {
        setIsSwitching(true)
      }
      setError(null)
    }

    try {
      const basePath = import.meta.env.BASE_URL || '/'
      const fileName = range === '24h' ? 'latest-24h.json' : 'latest-7d.json'
      const signal = isPreload ? undefined : abortControllerRef.current?.signal
      
      const response = await fetch(`${basePath}data/${fileName}${force ? `?checked=${Date.now()}` : ''}`, { signal, cache: force ? 'no-store' : 'default' })
      if (!response.ok) {
        throw new Error('数据加载失败')
      }
      const json = await resolveSourceTimes(await response.json())
      if (signal?.aborted) return
      
      preloadedDataRef.current[range] = json
      
      if (!isPreload) {
        setData(json)
        isInitialLoadRef.current = false
      }
    } catch (err) {
      if (err instanceof Error && err.name === 'AbortError') {
        return
      }
      if (!isPreload) {
        setError(err instanceof Error ? err.message : '未知错误')
      }
    } finally {
      if (!isPreload) {
        setLoading(false)
        setIsSwitching(false)
      }
    }
  }, [])

  useEffect(() => {
    fetchData(timeRange)
    return () => {
      abortControllerRef.current?.abort()
    }
  }, [timeRange, fetchData])

  useEffect(() => {
    if (!window.__AI_NATIVE__ && !isInitialLoadRef.current && !preloadedDataRef.current['7d']) {
      fetchData('7d', true)
    }
  }, [data, fetchData])

  const handleTimeRangeChange = useCallback((range: TimeRange) => {
    setTimeRange(range)
    setDisplayCount(PAGE_SIZE)
    setSelectedSite('all')
    setSelectedSource('all')
    setSearchQuery('')
  }, [])

  const sourceStats = useMemo(() => {
    if (!data?.items || selectedSite === 'all') return []
    
    const sourceMap = new Map<string, number>()
    data.items
      .filter(item => item.site_id === selectedSite)
      .forEach(item => {
        sourceMap.set(item.source, (sourceMap.get(item.source) || 0) + 1)
      })
    
    return Array.from(sourceMap.entries())
      .map(([source, count]) => ({ source, count }))
      .sort((a, b) => b.count - a.count)
  }, [data, selectedSite])

  const filteredItems = useMemo(() => {
    if (!data?.items) return []
    
    let items = data.items.filter(item => matchesScore(item, minScore) && (selectedCategory === 'all' || ratingFor(item).category === selectedCategory))
    
    if (selectedSite !== 'all') {
      items = items.filter(item => item.site_id === selectedSite)
    }

    if (selectedSource !== 'all') {
      items = items.filter(item => item.source === selectedSource)
    }
    
    if (searchQuery.trim()) {
      const query = searchQuery.toLowerCase()
      items = items.filter(item => 
        item.title.toLowerCase().includes(query) ||
        item.source.toLowerCase().includes(query) ||
        (item.title_zh && item.title_zh.toLowerCase().includes(query))
      )
    }
    
    items = [...items].sort((a, b) => {
      if (sortBy === 'score' && (scoreOf(a) ?? -1) !== (scoreOf(b) ?? -1)) return (scoreOf(b) ?? -1) - (scoreOf(a) ?? -1)
      return compareNewsTimes(a, b)
    })
    return items.slice(0, displayCount)
  }, [data, selectedSite, selectedSource, searchQuery, displayCount, minScore, sortBy, selectedCategory])

  const totalFiltered = useMemo(() => {
    if (!data?.items) return 0
    
    let items = data.items.filter(item => matchesScore(item, minScore) && (selectedCategory === 'all' || ratingFor(item).category === selectedCategory))
    
    if (selectedSite !== 'all') {
      items = items.filter(item => item.site_id === selectedSite)
    }

    if (selectedSource !== 'all') {
      items = items.filter(item => item.source === selectedSource)
    }
    
    if (searchQuery.trim()) {
      const query = searchQuery.toLowerCase()
      items = items.filter(item => 
        item.title.toLowerCase().includes(query) ||
        item.source.toLowerCase().includes(query) ||
        (item.title_zh && item.title_zh.toLowerCase().includes(query))
      )
    }
    
    return items.length
  }, [data, selectedSite, selectedSource, searchQuery, minScore, selectedCategory])

  const loadMore = () => {
    setDisplayCount(prev => prev + PAGE_SIZE)
  }

  const hasMore = displayCount < totalFiltered

  const refresh = () => {
    setDisplayCount(PAGE_SIZE)
    preloadedDataRef.current = {}
    fetchData(timeRange, false, true)
  }

  useEffect(() => {
    setDisplayCount(PAGE_SIZE)
  }, [selectedSite, selectedSource, searchQuery, minScore, selectedCategory])

  useEffect(() => {
    setSelectedSource('all')
  }, [selectedSite])

  return {
    data,
    loading,
    error,
    filteredItems,
    siteStats: data?.site_stats || [],
    sourceStats,
    searchQuery,
    setSearchQuery,
    selectedSite,
    setSelectedSite,
    selectedSource,
    setSelectedSource,
    loadMore,
    hasMore,
    displayCount,
    refresh,
    timeRange,
    setTimeRange: handleTimeRangeChange,
    isSwitching,
    minScore, setMinScore, selectedCategory, setSelectedCategory, sortBy, setSortBy, scoring, aiError, lastChecked
  }
}
