import Foundation

enum DirectFeedTests {
    static func run() throws {
        let now = parseDate("2026-09-17T08:00:00Z")!
        let feed = DirectFeed(id: "fixture", name: "测试订阅", feedURL: "https://example.com/feed", homeURL: "https://example.com", description: "RSS fixture")
        let xml = """
        <rss version="2.0"><channel><title>Channel</title>
        <item><title><![CDATA[模型 & Agent]]></title><link>https://example.com/new</link><pubDate>Thu, 17 Sep 2026 06:00:00 GMT</pubDate></item>
        <item><title>Duplicate</title><link>https://example.com/new#section</link><pubDate>Thu, 17 Sep 2026 06:00:00 GMT</pubDate></item>
        <item><title>昨天</title><link>https://example.com/yesterday</link><pubDate>Wed, 16 Sep 2026 05:00:00 +0000</pubDate></item>
        <item><title>旧内容</title><link>https://example.com/old</link><pubDate>Wed, 09 Sep 2026 12:56:58 GMT</pubDate></item>
        <item><title>无日期</title><link>https://example.com/undated</link></item>
        <item><title>未来</title><link>https://example.com/future</link><pubDate>Fri, 18 Sep 2026 06:00:00 GMT</pubDate></item>
        <item><title>Unsafe link</title><link>javascript:alert(1)</link><pubDate>Thu, 17 Sep 2026 06:00:00 GMT</pubDate></item>
        </channel></rss>
        """
        let items = try DirectFeeds.parse(Data(xml.utf8), feed: feed, now: now)
        precondition(items.count == 3 && items.first?.title == "模型 & Agent", "Decode CDATA, deduplicate fragments and reject missing/future dates or unsafe links")
        let laterItems = try DirectFeeds.parse(Data(xml.utf8), feed: feed, now: now.addingTimeInterval(60))
        precondition(items.map(\.id) == laterItems.map(\.id), "Refreshing preserves IDs and associated ratings")
        for invalid in ["<html><body>Error</body></html>", "<rss><channel><item>"] {
            do { _ = try DirectFeeds.parse(Data(invalid.utf8), feed: feed, now: now); preconditionFailure("Invalid feeds must fail") }
            catch { }
        }
        let cached = [feed.id: DirectFeedCache(items: items, checkedAt: timestamp(now), fetchedAt: timestamp(now))]
        let empty = NewsData(generated_at: timestamp(now), window_hours: 24, total_items: 0, total_items_raw: 0, source_count: 0, site_stats: [], items: [])
        let today = DirectFeeds.merge(empty, feeds: [feed], cached: cached, now: now)
        precondition(today.items.count == 1 && today.items.first?.url == "https://example.com/new")
        precondition(today.source_count == 1 && today.direct_sources?.first?.windowCount == 1)
        var week = empty; week.window_hours = 168
        precondition(DirectFeeds.merge(week, feeds: [feed], cached: cached, now: now).items.count == 2, "First seen today does not make old posts recent")
        let repeated = DirectFeeds.merge(today, feeds: [feed], cached: cached, now: now)
        precondition(repeated.items.count == 1 && repeated.total_items_raw == 1, "Merge must be idempotent")
        var upstream = empty
        var duplicate = items[0]; duplicate.site_id = "opmlrss"; duplicate.id = "upstream-id"
        upstream.items = [duplicate]
        let deduped = DirectFeeds.merge(upstream, feeds: [feed], cached: cached, now: now)
        precondition(deduped.items.count == 1 && deduped.items[0].id == "upstream-id", "Keep upstream IDs when an article also arrives via aggregation")
        var failedCache = cached
        failedCache[feed.id]?.error = "测试网络失败"
        let expired = DirectFeeds.merge(today, feeds: [feed], cached: failedCache, now: now.addingTimeInterval(86400))
        precondition(expired.items.isEmpty && expired.source_count == 1, "Expired news ages out while configured sources stay visible")
        precondition(expired.direct_sources?.first?.latestTitle == "模型 & Agent" && expired.direct_sources?.first?.error != nil, "Keep the latest known article and report fetch failures")
        precondition(Scoring.majorPublisher(at: "https://mossfirepodcast.substack.com/p/example") == nil, "Editorial sources do not earn the major-lab release bonus")
        print("PASS: direct RSS parsing, date windows, stable IDs, upstream deduplication and cached source status")
    }
}
