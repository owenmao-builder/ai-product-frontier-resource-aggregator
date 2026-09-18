import Foundation

enum SourceTimeTests {
    @MainActor static func run() throws {
        let now = parseDate("2026-09-18T06:00:00Z")!
        let url = "https://aiera.com.cn/asi-post.html?id=114307"
        let raw = NewsItem(id: "time-fixture", site_id: "xinzhiyuan", site_name: "新智元", source: "新智元", title: "时间测试", url: url,
                           published_at: "2026-09-18T08:03:39Z", first_seen_at: "2026-09-18T02:06:03Z", last_seen_at: "2026-09-18T02:06:03Z")
        let payload = #"[{"id":114307,"date":"2026-09-18T08:03:39","date_gmt":"2026-09-18T00:03:39","link":"https://aiera.com.cn/asi-post.html?id=114307"}]"#
        let requested = SourceTimes.requestedPosts([raw], cached: [:], now: now)
        precondition(requested == [114307: url])
        let verified = try SourceTimes.parse(Data(payload.utf8), requested: requested, now: now)
        precondition(verified[url]?.publishedAt == "2026-09-18T00:03:39Z")
        let snapshot = NewsData(generated_at: timestamp(now), window_hours: 24, total_items: 1, source_count: 1, site_stats: [], items: [raw])
        let resolved = SourceTimes.apply(snapshot, cached: verified).items[0]
        precondition(!resolved.newsTime(now: now).isCollection)
        precondition(resolved.newsTime(now: now).date == parseDate("2026-09-18T00:03:39Z"))
        precondition(resolved.published_at == raw.published_at && Scoring.fingerprint(resolved) == Scoring.fingerprint(raw))
        precondition(resolved.newsTime(now: now).orderedBefore(raw.newsTime(now: now)), "Batch collection time must not rank ahead of known publication time")
        var approximate = raw; approximate.site_id = "aibase"; approximate.published_at = approximate.first_seen_at
        precondition(approximate.newsTime(now: now).isCollection, "Do not label a scraped 'just now' hint as exact publication time")
        approximate.site_id = "tophub"
        precondition(approximate.newsTime(now: now).isCollection)
        approximate.site_id = "directrss"
        precondition(!approximate.newsTime(now: now).isCollection, "Keep an explicit RSS timestamp even if collection happened simultaneously")
        precondition(NewsStore.isToday(resolved, now: now))
        precondition(SourceTimes.requestedPosts([raw], cached: verified, now: now).isEmpty, "Reuse verified time instead of fetching on every refresh")
        let persisted = try JSONDecoder().decode([String: SourcePublication].self, from: JSONEncoder().encode(verified))
        precondition(!SourceTimes.apply(snapshot, cached: persisted).items[0].newsTime(now: now).isCollection, "Survive restart and fresh upstream snapshots")

        let originalZone = NSTimeZone.default
        defer { NSTimeZone.default = originalZone }
        for zone in ["UTC", "America/Los_Angeles", "Asia/Shanghai"] {
            NSTimeZone.default = TimeZone(identifier: zone)!
            precondition(beijingTimeLabel(date: resolved.newsTime(now: now).date, now: now) == "08:03")
            precondition(beijingTimeLabel(date: parseDate("2026-09-17T16:00:00Z"), now: now) == "00:00")
        }
        let localOnly = #"[{"id":114307,"date":"2026-09-18T08:03:39","link":"https://aiera.com.cn/asi-post.html?id=114307"}]"#
        let localResult = try SourceTimes.parse(Data(localOnly.utf8), requested: requested, now: now)
        precondition(localResult[url]?.publishedAt == "2026-09-18T00:03:39Z")
        let future = payload.replacingOccurrences(of: "2026-09-18T00:03:39", with: "2026-09-18T08:03:39")
        let futureResult = try SourceTimes.parse(Data(future.utf8), requested: requested, now: now)
        precondition(futureResult.isEmpty)
        let mismatch = payload.replacingOccurrences(of: "aiera.com.cn", with: "example.com")
        let mismatchResult = try SourceTimes.parse(Data(mismatch.utf8), requested: requested, now: now)
        precondition(mismatchResult.isEmpty)
        var wrongSource = raw; wrongSource.url = "https://aiera.com.cn.evil.example/asi-post.html?id=114307"
        precondition(SourceTimes.postID(wrongSource) == nil)
        var yesterday = raw; yesterday.published_at = "2026-09-17T00:03:39Z"; yesterday.first_seen_at = "2026-09-17T02:06:03Z"
        precondition(SourceTimes.requestedPosts([yesterday], cached: [:], now: now).isEmpty, "Do not backfill old news")
        print("PASS: verified source publication times, Beijing display, URL matching, future rejection, cache persistence and today's scope")
    }
}
