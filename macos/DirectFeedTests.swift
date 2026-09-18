import Foundation

enum DirectFeedTests {
    static func run() throws {
        let now = parseDate("2026-09-17T08:00:00Z")!
        let feed = DirectFeed(id: "fixture", name: "测试订阅", feedURL: "https://example.com/feed", homeURL: "https://example.com", description: "RSS fixture")
        let xml = """
        <rss version="2.0"><channel><title>Channel</title>
        <item><title><![CDATA[模型 & Agent]]></title><link>https://example.com/new</link><pubDate>Thu, 17 Sep 2026 06:00:00 GMT</pubDate></item>
        <item><title>Duplicate</title><link>https://example.com/new#section</link><pubDate>Thu, 17 Sep 2026 06:00:00 GMT</pubDate></item>
        <item><title>Tracking duplicate</title><link>https://example.com/new/?utm_source=rss</link><pubDate>Thu, 17 Sep 2026 06:00:00 GMT</pubDate></item>
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
        let xinzhiyuan = DirectFeed(id: "xinzhiyuan", name: "新智元", feedURL: "https://aiera.com.cn/feed/", homeURL: "https://aiera.com.cn", description: "Original feed")
        let brokenExcerpt = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><rss><channel><item><title>Afternoon news</title><link>https://aiera.com.cn/2026/09/17/other/admin/114312/article/</link><pubDate>Thu, 17 Sep 2026 06:00:00 GMT</pubDate><description><![CDATA["
        let broken = Data(brokenExcerpt.utf8) + Data([0xE4, 0xB8]) + Data("]]></description></item></channel></rss>".utf8)
        let repaired = try DirectFeeds.parse(broken, feed: xinzhiyuan, now: now)
        precondition(repaired.count == 1 && repaired[0].url == "https://aiera.com.cn/asi-post.html?id=114312", "A truncated UTF-8 excerpt must not hide valid news; canonicalize original-site permalinks for deduplication")
        let damagedTitle = String(decoding: broken, as: UTF8.self).replacingOccurrences(of: "Afternoon news", with: "Damaged \u{FFFD} title")
        let rejected = try DirectFeeds.parse(Data(damagedTitle.utf8), feed: xinzhiyuan, now: now)
        precondition(rejected.isEmpty, "Do not publish corrupted article titles")
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
        precondition(deduped.items[0].source_publication?.publishedAt == duplicate.published_at, "A direct feed verifies the publisher's time on an existing article")
        precondition(Scoring.fingerprint(deduped.items[0]) == Scoring.fingerprint(duplicate), "Adding source metadata must not invalidate a rating")
        let rotated = DirectFeeds.retain([], previous: items, now: now)
        precondition(rotated.count == 2, "Keep recent posts even when a short feed rotates them out")
        let stable = DirectFeeds.retain(laterItems, previous: items, now: now.addingTimeInterval(60))
        precondition(stable.first?.first_seen_at == items.first?.first_seen_at, "Do not change collection time every time the app refreshes")
        precondition(aggregateSnapshotLabel("2026-09-17T03:00:00Z", now: now).contains("5小时未更新"))
        precondition(aggregateSnapshotLabel(nil, now: now) == "聚合内容暂未取得")
        precondition(aggregateSnapshotLabel("2026-09-18T03:00:00Z", now: now) == "聚合快照时间异常")
        var failedCache = cached
        failedCache[feed.id]?.error = "测试网络失败"
        let expired = DirectFeeds.merge(today, feeds: [feed], cached: failedCache, now: now.addingTimeInterval(86400))
        precondition(expired.items.isEmpty && expired.source_count == 1, "Expired news ages out while configured sources stay visible")
        precondition(expired.direct_sources?.first?.latestTitle == "模型 & Agent" && expired.direct_sources?.first?.error != nil, "Keep the latest known article and report fetch failures")
        precondition(Scoring.majorPublisher(at: "https://mossfirepodcast.substack.com/p/example") == nil, "Editorial sources do not earn the major-lab release bonus")
        print("PASS: direct RSS parsing, date windows, stable IDs, upstream deduplication and cached source status")
    }

    static func refreshTests() async throws {
        let now = Date()
        let good = DirectFeed(id: "good", name: "Live fixture", feedURL: "https://example.com/good", homeURL: "https://example.com", description: "test")
        let bad = DirectFeed(id: "bad", name: "Failed fixture", feedURL: "https://example.com/bad", homeURL: "https://example.com", description: "test")
        let retained = NewsItem(id: "cached", site_id: "directrss", site_name: "原站直采", source: "Failed fixture", title: "Cached article", url: "https://example.com/cached", published_at: timestamp(now.addingTimeInterval(-120)), first_seen_at: timestamp(now.addingTimeInterval(-60)), last_seen_at: timestamp(now.addingTimeInterval(-60)))
        let previous = [bad.id: DirectFeedCache(items: [retained], checkedAt: timestamp(now.addingTimeInterval(-60)), fetchedAt: timestamp(now.addingTimeInterval(-60)))]
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FeedFixtureProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let fresh = await DirectFeeds.refresh([good, bad], cached: previous, session: session)
        precondition(fresh[good.id]?.items.count == 1 && fresh[good.id]?.error == nil)
        precondition(fresh[bad.id]?.error != nil && fresh[bad.id]?.items.first?.id == "cached", "One failed source must not remove its cache or block successful sources")
        let snapshot = NewsData(generated_at: timestamp(now.addingTimeInterval(-5 * 3600)), window_hours: 24, total_items: 0, source_count: 0, site_stats: [], items: [])
        let merged = DirectFeeds.merge(snapshot, feeds: [good, bad], cached: fresh, now: Date())
        precondition(merged.items.contains { $0.url == "https://example.com/afternoon" }, "Fetch new articles even when the aggregate snapshot is five hours old")
        precondition(merged.generated_at == snapshot.generated_at, "A successful check must not pretend the upstream snapshot was regenerated")
        precondition(merged.direct_sources?.filter { $0.error != nil }.count == 1)
        print("PASS: live refresh independent of stale snapshots, source failure isolation and honest freshness metadata")
    }
}

private final class FeedFixtureProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let status = request.url?.lastPathComponent == "bad" ? 503 : 200
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/rss+xml"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let xml = "<rss><channel><item><title>Afternoon article</title><link>https://example.com/afternoon</link><pubDate>\(timestamp(Date().addingTimeInterval(-30)))</pubDate></item></channel></rss>"
        client?.urlProtocol(self, didLoad: Data(xml.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
