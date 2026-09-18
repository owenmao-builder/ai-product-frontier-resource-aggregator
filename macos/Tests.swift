import Foundation

@main
enum ScoringTests {
    @MainActor static func main() async throws {
        try DirectFeedTests.run()
        try await DirectFeedTests.refreshTests()
        try SourceTimeTests.run()
        try ProductTests.run()
        PriorityTests.run()
        InterestScoreTests.run()
        try EventTests.run()
        if let index = CommandLine.arguments.firstIndex(of:"--event-sample"), CommandLine.arguments.count > index + 1 {
            try EventTests.sampleToday(cachePath:CommandLine.arguments[index+1])
        }
        let now = timestamp()
        let item = NewsItem(id: "known", site_id: "rss", site_name: "RSS", source: "Official", title: "DeepSeek 发布开源 Agent Harness SDK，新增 plugin middleware tracing", url: "https://example.com/article", published_at: now, first_seen_at: now, last_seen_at: now)
        let pending = Scoring.rule(item)
        precondition(pending.score == nil && !pending.isScored && pending.displayScore == "—")
        precondition(pending.category == "developer" && pending.evidenceLevel == "C")
        var variant = item
        for headline in ["优惠码限时优惠", "New model release", "OpenAI Claude DeepSeek Agent Harness 可插拔 黑箱可见"] {
            variant.title = headline
            precondition(Scoring.rule(variant).score == nil, "Titles and brand keywords cannot produce a score")
        }
        variant.title = "Company raises $19M in funding"
        precondition(Scoring.category(for: variant) == .business)
        variant.title = "New AI legislation approved by lawmakers"
        precondition(Scoring.category(for: variant) == .policy)
        precondition(!NewsCategory.business.questions.contains("可观测性"))
        precondition(!NewsCategory.policy.questions.contains("插件"))
        precondition(Scoring.fingerprint(item) != Scoring.fingerprint(variant))

        func dimensions(_ values: [Double]) -> [RatingDimension] {
            zip(Scoring.keys, values).map { RatingDimension(key: $0.0, value: $0.1, reason: "Provided evidence supports this assessment") }
        }
        precondition(Scoring.total(dimensions([4, 3, 4, 4])) == 7.4)
        precondition(Scoring.total(dimensions([0, 0, 0, 0])) == 0)
        precondition(Scoring.total(dimensions([6, 3, 3, 3])) == nil)
        precondition(Scoring.total(dimensions([3.5, 3, 3, 3])) == nil)
        var duplicate = dimensions([3, 3, 3, 3]); duplicate[3].key = "impact"
        precondition(Scoring.total(duplicate) == nil)
        let quote = "The new version adds a documented export interface."
        var reviewed = NewsRating(score: 10, reason: "具体变化和适用范围已说明", tags: [], method: "reviewed", assessedAt: now, version: Scoring.version, category: "developer", evidenceLevel: "B", dimensions: dimensions([4, 3, 4, 4]), sources: [RatingSource(url: item.url, title: "原文", quote: quote)], comparison: "原文明确对照旧接口")
        precondition(Scoring.validated(reviewed)?.score == 7.4, "Recompute totals instead of accepting model totals")
        reviewed.comparison = nil
        precondition(Scoring.validated(reviewed) == nil, "An increment above 2 needs a comparison")
        reviewed.comparison = "已有方案与新方案"
        reviewed.dimensions = dimensions([4, 4, 4, 4])
        precondition(Scoring.validated(reviewed) == nil, "High scores need sufficient evidence")
        reviewed.evidenceLevel = "A"
        precondition(Scoring.validated(reviewed) == nil, "One source cannot support an 8+ assessment")
        reviewed.sources?.append(RatingSource(url: "https://example.org/baseline", title: "对照", quote: quote))
        precondition(Scoring.validated(reviewed)?.score == 8)
        reviewed.version = "rules-v1"
        precondition(Scoring.validated(reviewed) == nil && !reviewed.isScored, "Legacy keyword scores must not survive migration")
        let legacy = #"{"score":7.9,"reason":"old","tags":["Agent"],"method":"rule","assessedAt":"2026-09-17T00:00:00Z"}"#
        let old = try JSONDecoder().decode(NewsRating.self, from: Data(legacy.utf8))
        precondition(!old.isScored && old.sortScore == -1 && old.displayScore == "—")

        let doc = ArticleDocument(url: item.url, title: item.title, text: quote + String(repeating: " Verified article body.", count: 30), fetchedAt: now, error: nil, truncated: false)
        var row: [String: Any] = ["id": item.id, "status": "assessed", "category": "developer", "evidenceLevel": "B", "reason": "有正文与旧版对照", "chineseTitle": "新版本增加有文档支持的导出接口", "highlights": ["新增导出接口，便于开发者接入。", "适用条件见原文，效果仍待独立验证。"], "comparison": "对照旧版接口", "dimensions": zip(Scoring.keys, [4, 3, 4, 4]).map { ["key": $0.0, "value": $0.1, "reason": "正文依据"] }, "sources": [["url": item.url, "quote": quote]], "tags": ["开发工具"], "gaps": ["独立验证"]]
        func decode(_ row: [String: Any], docs: [ArticleDocument] = [doc]) throws -> NewsRating {
            var unknown = row; unknown["id"] = "unknown"
            let json = String(data: try JSONSerialization.data(withJSONObject: ["ratings": [row, unknown, row]]), encoding: .utf8)!
            let parsed = try Scoring.decodeAI(json, items: [item], documents: [item.id: docs], model: "test")
            precondition(parsed.count == 1, "Ignore unknown and duplicate IDs")
            return parsed[item.id]!
        }
        let accepted = try decode(row); precondition(accepted.score == 7.4)
        var missingBrief = row; missingBrief.removeValue(forKey: "highlights")
        let incomplete = try decode(missingBrief); precondition(!incomplete.isScored, "A newly assessed high-score item needs a Chinese brief")
        precondition(accepted.hasChineseBrief)
        let noBody = try decode(row, docs: []); precondition(noBody.score == nil, "No body means pending")
        row["sources"] = [["url": item.url, "quote": "This sentence never appeared in the source material."]]
        let invented = try decode(row); precondition(invented.score == nil, "Reject invented quotations")
        row["sources"] = [["url": "https://example.org/unprovided", "quote": quote]]
        let unprovided = try decode(row); precondition(unprovided.score == nil, "Reject unprovided sources")
        row["status"] = "pending"
        let returnedPending = try decode(row); precondition(returnedPending.score == nil)

        let official = "https://openai.com/index/test-new-model"
        var launch = pending
        launch.score = 7.4; launch.category = "model"; launch.evidenceLevel = "B"
        launch.dimensions = dimensions([4, 3, 4, 4]); launch.comparison = "前代模型对照"
        launch.sources = [RatingSource(url: official, title: "Synthetic release fixture", quote: quote)]
        launch.release = ReleaseSignal(kind: "model", publisher: "OpenAI", url: official, quote: quote, reason: "测试：官方新模型发布")
        let boosted = Scoring.validated(launch)!
        precondition(boosted.score == 8.4 && boosted.baseScore == 7.4 && boosted.evidenceLevel == "B")
        launch.release?.kind = "architecture"
        precondition(Scoring.validated(launch)?.score == 8.4)
        launch.category = "product"
        precondition(Scoring.validated(launch)?.score == 7.4, "An ordinary product integration earns no architecture bonus")
        launch.category = "model"; launch.release?.publisher = "Google"
        precondition(Scoring.releaseBonus(for: launch) == 0, "Publisher must match the official evidence")
        launch.release?.publisher = "OpenAI"; launch.release?.url = "https://openai.com.evil.example/news"
        precondition(Scoring.releaseBonus(for: launch) == 0)
        precondition(Scoring.majorPublisher(at: "https://huggingface.co/ukisai/Swift-Qwen3.8-27b") == nil, "Third-party derivatives aren't official major-lab releases")
        launch.release?.url = official; launch.release?.quote = "This quotation is not in the provided evidence."
        precondition(Scoring.releaseBonus(for: launch) == 0)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        var dated = item; dated.published_at = "2026-09-16T16:00:00Z"
        let sampleNow = parseDate("2026-09-17T08:00:00Z")!
        precondition(NewsStore.isToday(dated, now: sampleNow, calendar: calendar))
        dated.published_at = "2026-09-16T15:59:59Z"
        precondition(!NewsStore.isToday(dated, now: sampleNow, calendar: calendar), "Today follows local midnight, not a rolling 24-hour window")

        let clockNow = parseDate("2026-09-18T06:00:00Z")! // 14:00 Shanghai
        dated.published_at = "2026-09-18T08:03:39Z" // Misparsed source-local 08:03
        dated.first_seen_at = "2026-09-18T02:06:03.931Z"
        let sourceTimestamp = dated.published_at
        let corrected = dated.newsTime(now: clockNow)
        precondition(corrected.isCollection && corrected.date == parseDate(dated.first_seen_at))
        precondition(corrected.label.hasPrefix("收录 ") && corrected.explanation.contains("不代表发布时间"))
        precondition(dated.published_at == sourceTimestamp, "Preserve the original source timestamp")
        precondition(NewsStore.isToday(dated, now: clockNow, calendar: calendar))
        precondition(dated.newsTime(now: clockNow.addingTimeInterval(8 * 3600)).isCollection, "A bad timestamp remains invalid after the clock catches up")
        dated.published_at = "2026-09-18T00:03:39Z"
        precondition(!dated.newsTime(now: clockNow).isCollection && dated.newsTime(now: clockNow).date == parseDate(dated.published_at))
        for missing in [nil, "invalid"] as [String?] {
            dated.published_at = missing
            precondition(dated.newsTime(now: clockNow).isCollection)
        }
        dated.published_at = "2026-09-18T08:03:39Z"
        dated.first_seen_at = "2026-09-18T08:04:00Z"
        precondition(dated.newsTime(now: clockNow).date == nil && !NewsStore.isToday(dated, now: clockNow, calendar: calendar))
        dated.first_seen_at = "2026-09-17T15:59:59Z"
        precondition(!NewsStore.isToday(dated, now: clockNow, calendar: calendar), "A future publication cannot move yesterday's collected item into today")
        dated.published_at = "2026-09-18T02:05:00Z"; dated.first_seen_at = "2026-09-18T02:00:00Z"
        precondition(!dated.newsTime(now: clockNow).isCollection)
        dated.published_at = "2026-09-18T02:05:01Z"
        precondition(dated.newsTime(now: clockNow).isCollection)

        if CommandLine.arguments.count > 1 {
            let archive = try JSONDecoder().decode(ReviewedArchive.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
            for entry in archive.entries {
                guard let valid = Scoring.validated(entry.rating) else { preconditionFailure("Invalid bundled rating: \(entry.id)") }
                precondition(valid.score == entry.rating.score)
                if valid.sortScore >= 7 { precondition(valid.hasChineseBrief, "Missing bundled Chinese brief: \(entry.id)") }
            }
        }

        let html = #"<html><body><nav>MENU</nav><main data-json='{"value":"2 > 1"}'><h1>Real news</h1><script>secret()</script><p>AT&amp;T &#x4e2d; &#25991; &lt;test&gt;</p><a title="a > b">Read body</a></main><footer>FOOTER</footer></body></html>"#
        let extracted = ArticleDocument.extract(html)
        precondition(extracted == "Real news AT&T 中 文 <test> Read body", extracted)
        for url in ["http://example.com", "https://localhost/a", "https://127.0.0.1/a", "https://192.168.1.1/a", "https://user:pass@example.com/a", "file:///etc/passwd", "javascript:alert(1)"] { precondition(publicArticleURL(url) == nil) }
        precondition(publicArticleURL("https://openai.com/index/example") != nil)
        variant.url = "https://openai.com.evil.example/news"
        precondition(!Scoring.isOfficial(variant))
        variant.url = "javascript:alert(1)"
        precondition(variant.safeURL == nil)
        let snapshot = NewsData(generated_at: now, window_hours: 24, total_items: 3, source_count: 1, site_stats: [], items: [item, item, variant])
        let decoded = try NewsStore.decode(JSONEncoder().encode(snapshot))
        precondition(decoded.items.count == 1 && decoded.total_items == 1)
        print("PASS: scoring and evidence validation, release bonus and ownership, Chinese high-score briefs, local-day scope and timestamp fallback, bundled assessments, HTML extraction and deduplication")
    }
}
