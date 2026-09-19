import Foundation
import Combine
import Security
import CryptoKit

struct Preferences: Codable {
    var dataBaseURL = "https://suyxh.github.io/ai-news-aggregator/data"
    var refreshMinutes = 15
    var compactTitle = true
    var aiEnabled = false
    var apiBaseURL = ""
    var model = ""
    var watchedProducts: [String]? = nil
}

enum KeyStore {
    private static let service = "local.owen.ai-news-menubar"
    static func read() -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: "scoring-api", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func write(_ key: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "scoring-api"]
        if key.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw NewsError.message("无法清除钥匙串中的 API Key。") }
            return
        }
        let value: [String: Any] = [kSecValueData as String: Data(key.utf8)]
        var status = SecItemUpdate(query as CFDictionary, value as CFDictionary)
        if status == errSecItemNotFound {
            var add = query.merging(value) { _, new in new }
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw NewsError.message("无法保存 API Key 到 macOS 钥匙串。") }
    }
}

final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

struct RatingCache: Codable {
    var profile: String
    var ratings: [String: NewsRating]
    var fingerprints: [String: String]
}

@MainActor
final class NewsStore: ObservableObject {
    @Published var snapshots: [String: NewsData] = [:]
    @Published var preferences: Preferences
    @Published var loading = false
    @Published var scoring = false
    @Published var error: String?
    @Published var aiError: String?
    @Published var lastChecked: Date?
    @Published var ratings: [String: NewsRating] = [:]
    @Published var seen: Set<String>
    @Published var filter = "today"
    @Published var query = ""
    @Published var section = "news" { didSet { onUpdate?() } }
    @Published var productBoard = ProductBoard(verifiedAt: "", items: [])
    @Published private(set) var groupedSnapshots: [String:[NewsItem]] = [:]
    private var seenEvents = Set<String>()
    private var eventByArticle: [String:NewsEvent] = [:]
    var onUpdate: (() -> Void)?
    private var timer: Timer?
    private var cachedAI: RatingCache
    private var ruleCache: [String: NewsRating] = [:]
    private var priorities: [String: NewsPriority] = [:]
    private var interestRatings: [String: ReviewedEntry] = [:]
    private var titleTranslations: [String: String] = [:]
    private var reviewed: [String: ReviewedEntry] = [:]
    private var documents: [String: ArticleDocument] = [:]
    private var apiKey: String?
    private var scoringTask: Task<Void, Never>?
    private var generation = 0
    private let cacheDirectory: URL
    private let session: URLSession
    private let collector = LocalCollector()
    private let directFeeds = DirectFeed.configured
    private var directFeedCache: [String: DirectFeedCache] = [:]
    private let bundledProductCatalog = Products.bundled("products.json", as: ProductBoard.self) ?? ProductBoard(verifiedAt: "", items: [])
    private var productCatalog: ProductBoard {
        Products.mergedCatalog(bundledProductCatalog, discovery: snapshots["24h"]?.product_discovery ?? snapshots["7d"]?.product_discovery)
    }
    private var productPulse = ProductPulse()
    private var sourceTimes: [String: SourcePublication] = [:]
    private var initialCollectorSeed: [NewsItem] = []

    init() {
        let defaults = UserDefaults.standard
        preferences = defaults.data(forKey: "preferences").flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) } ?? Preferences()
        seen = Set(defaults.stringArray(forKey: "seen-urls") ?? [])
        seenEvents = Set(defaults.stringArray(forKey:"seen-events") ?? [])
        lastChecked = defaults.object(forKey: "last-checked") as? Date
        cacheDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("AINewsMenu", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        cachedAI = (try? Data(contentsOf: cacheDirectory.appendingPathComponent("ratings.json"))).flatMap { try? JSONDecoder().decode(RatingCache.self, from: $0) } ?? RatingCache(profile: "", ratings: [:], fingerprints: [:])
        interestRatings = (try? Data(contentsOf:cacheDirectory.appendingPathComponent("interest-ratings.json"))).flatMap { try? JSONDecoder().decode([String:ReviewedEntry].self,from:$0) } ?? [:]
        titleTranslations = (try? Data(contentsOf:cacheDirectory.appendingPathComponent("headline-translations.json"))).flatMap { try? JSONDecoder().decode([String:String].self,from:$0) } ?? [:]
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 35
        session = URLSession(configuration: config)
        for range in ["24h", "7d"] {
            let cached = cacheDirectory.appendingPathComponent("latest-\(range).json")
            let bundled = Bundle.main.resourceURL?.appendingPathComponent("seed/latest-\(range).json")
            if let data = (try? Data(contentsOf: cached)) ?? bundled.flatMap({ try? Data(contentsOf: $0) }), let snapshot = try? Self.decode(data) {
                snapshots[range] = snapshot
                // Seed the archive before the 24-hour view expires yesterday's articles.
                initialCollectorSeed.append(contentsOf: snapshot.items)
            }
        }
        if let url = Bundle.main.resourceURL?.appendingPathComponent("seed/assessments-v2.json"),
           let data = try? Data(contentsOf: url), let archive = try? JSONDecoder().decode(ReviewedArchive.self, from: data), archive.version == Scoring.version {
            reviewed = Dictionary(archive.entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }
        documents = (try? Data(contentsOf: cacheDirectory.appendingPathComponent("documents-v2.json"))).flatMap { try? JSONDecoder().decode([String: ArticleDocument].self, from: $0) } ?? [:]
        directFeedCache = (try? Data(contentsOf: cacheDirectory.appendingPathComponent("direct-feeds.json"))).flatMap { try? JSONDecoder().decode([String: DirectFeedCache].self, from: $0) } ?? [:]
        productPulse = (try? Data(contentsOf: cacheDirectory.appendingPathComponent("product-pulse.json"))).flatMap { try? JSONDecoder().decode(ProductPulse.self, from: $0) } ?? Products.bundled("product-pulse.json", as: ProductPulse.self) ?? ProductPulse()
        sourceTimes = (try? Data(contentsOf: cacheDirectory.appendingPathComponent("source-times.json"))).flatMap { try? JSONDecoder().decode([String: SourcePublication].self, from: $0) } ?? [:]
        mergeSourceTimes()
        mergeDirectFeeds()
        recalculate()
    }

    static func decode(_ bytes: Data) throws -> NewsData {
        guard bytes.count <= 20_000_000 else { throw NewsError.message("资讯数据过大，已保留上次内容。") }
        var value = try JSONDecoder().decode(NewsData.self, from: bytes)
        guard parseDate(value.generated_at) != nil else { throw NewsError.message("数据的更新时间无效。") }
        var urls = Set<String>()
        var ids = Set<String>()
        value.items = value.items.filter { item in
            !item.id.isEmpty && !item.title.isEmpty && item.safeURL != nil && urls.insert(item.url).inserted && ids.insert(item.id).inserted
        }
        value.items = Array(value.items.prefix(15000))
        value.total_items = value.items.count
        let counts = Dictionary(grouping: value.items, by: \.site_id).mapValues(\.count)
        value.site_stats = value.site_stats.map { stat in var stat = stat; stat.count = counts[stat.site_id] ?? 0; return stat }
        value.source_count = Set(value.items.map(\.source)).count
        return value
    }

    var items: [NewsItem] { snapshots["24h"]?.items ?? [] }
    var todayItems: [NewsItem] { items.filter { Self.isToday($0) } }
    var newsItems: [NewsItem] { groupedSnapshots["24h"] ?? items }
    var todayEvents: [NewsItem] { newsItems.filter { Self.isToday($0) } }
    static func isToday(_ item: NewsItem, now: Date = Date(), calendar: Calendar = beijingCalendar) -> Bool {
        (item.event.flatMap { parseDate($0.latestAt) } ?? item.newsTime(now: now).date).map { $0 <= now && calendar.isDate($0, inSameDayAs: now) } ?? false
    }
    var unreadCount: Int { newsItems.filter { !isRead($0) }.count }
    var directRefreshLabel: String {
        let sources = snapshots["24h"]?.direct_sources ?? []
        let ready = sources.filter { $0.error == nil && $0.fetchedAt != nil }.count
        let checked = sources.compactMap { parseDate($0.checkedAt) }.max()
        return "原站直采 \(ready)/\(directFeeds.count) · 检查 \(beijingTimeLabel(date: checked))"
    }
    var snapshotLabel: String {
        if loading { return "正在逐一采集资讯平台与订阅源…" }
        if let collection = snapshots["24h"]?.collection {
            return collection.label + (collection.failures > 0 ? " · \(collection.failures)源异常" : "")
        }
        return aggregateSnapshotLabel(snapshots["24h"]?.generated_at)
    }
    func stop() { timer?.invalidate(); collector.cancel(); scoringTask?.cancel() }
    var visible: [NewsItem] {
        newsItems.filter { item in
            let rating = rating(for: item)
            if filter == "today" && !Self.isToday(item) { return false }
            if filter == "high" && rating.sortScore < 7 { return false }
            if filter == "pending" && rating.isScored { return false }
            if filter == "unread" && isRead(item) { return false }
            let coverage = item.event?.reports.flatMap { $0.articles.map { $0.title + " " + $0.source } }.joined(separator:" ") ?? ""
            return query.isEmpty || (title(for: item) + " " + item.displayTitle + " " + item.title + " " + item.source + " " + coverage).localizedCaseInsensitiveContains(query)
        }.sorted { first, second in
            let a = rating(for: first).sortScore, b = rating(for: second).sortScore
            if a != b { return a > b }
            let pa = priority(for: first).value, pb = priority(for: second).value
            if pa != pb { return pa > pb }
            return first.newsTime().orderedBefore(second.newsTime())
        }
    }
    var lead: NewsItem? { visible.first }
    func rating(for item: NewsItem) -> NewsRating { (item.event == nil ? nil : item.rating) ?? ratings[item.id] ?? ruleCache[item.id] ?? Scoring.rule(item) }
    func priority(for item: NewsItem) -> NewsPriority {
        priorities[item.id] ?? Priority.rank(item, rating: rating(for: item), products: productCatalog.items, pulse: productPulse, watchlist: preferences.watchedProducts ?? Priority.defaultWatchlist)
    }
    func title(for item: NewsItem) -> String {
        if let event = item.event { return event.title }
        let rating = rating(for: item)
        if rating.sortScore >= 7, let title = rating.chineseTitle, Scoring.matches(title, "[\\p{Han}]") { return title }
        return item.displayTitle
    }

    private func fingerprint(_ item: NewsItem) -> String { Scoring.fingerprint(item) }
    private var profile: String { Scoring.version + "/" + Scoring.policyRevision + "/" + preferences.apiBaseURL + "/" + preferences.model }
    var assessedCount: Int { items.filter { rating(for: $0).isScored }.count }

    func recalculate() {
        var next: [String: NewsRating] = [:]
        ruleCache = [:]
        for snapshot in ["24h", "7d"].compactMap({ snapshots[$0] }) {
            for item in snapshot.items where next[item.id] == nil {
                let rule = Scoring.rule(item)
                ruleCache[item.id] = rule
                if !Self.isToday(item), let saved = interestRatings[item.id], saved.fingerprint == fingerprint(item), saved.rating.isInterest {
                    next[item.id] = saved.rating
                } else if let saved = reviewed[item.id], saved.fingerprint == fingerprint(item), let valid = Scoring.validated(saved.rating) {
                    next[item.id] = valid
                } else if preferences.aiEnabled, cachedAI.profile == profile, cachedAI.fingerprints[item.id] == fingerprint(item), let ai = cachedAI.ratings[item.id], let valid = Scoring.validated(ai) {
                    next[item.id] = valid
                } else { next[item.id] = rule }
            }
        }
        // Publish the completed batch once; per-article @Published mutations stall the menu.
        var calculated = next
        priorities = [:]
        let products = productCatalog.items
        let priorityContext = Priority.Context(products: products, pulse: productPulse, watchlist: preferences.watchedProducts ?? Priority.defaultWatchlist)
        for snapshot in snapshots.values {
            for item in snapshot.items where priorities[item.id] == nil {
                let base = next[item.id] ?? Scoring.rule(item)
                let signals = Self.isToday(item) ? TechnicalSignals.analyze(item,document:documents[item.url],products:products) : TechnicalSignals()
                let priority = Priority.rank(item, rating: base, context: priorityContext,signals:signals)
                priorities[item.id] = priority
                if Self.isToday(item) {
                    let direct = InterestScore.rating(item,priority:priority,previous:base,signals:signals,translatedTitle:titleTranslations[item.title])
                    calculated[item.id] = direct
                    interestRatings[item.id] = ReviewedEntry(id:item.id,fingerprint:fingerprint(item),rating:direct)
                }
            }
        }
        ratings = calculated
        var allByID: [String:NewsItem] = [:]
        for range in ["24h","7d"] {
            for item in snapshots[range]?.items ?? [] where allByID[item.id] == nil { allByID[item.id] = item }
        }
        let groups = NewsEvents.groups(Array(allByID.values),products:products,documents:documents)
        let rows = groups.flatMap { group -> [NewsItem] in
            // Only today's active events get new analysis; preserve older article assessments.
            guard group.members.contains(where:{ Self.isToday($0) }) else { return group.members }
            return [NewsEvents.present(group,ratings:calculated,documents:documents,translations:titleTranslations,products:products)]
        }
        var grouped: [String:[NewsItem]] = [:]
        for (range,snapshot) in snapshots {
            let ids = Set(snapshot.items.map(\.id))
            grouped[range] = rows.filter { row in row.event?.memberIDs.contains(where:{ ids.contains($0) }) ?? ids.contains(row.id) }
        }
        eventByArticle = [:]
        for row in rows {
            guard let event = row.event else { continue }
            for id in event.memberIDs { eventByArticle[id] = event }
            if NewsEvents.isRead(event,seenURLs:seen,seenEvents:seenEvents) { seenEvents.insert(event.id) }
        }
        groupedSnapshots = grouped
        seenEvents.formIntersection(Set(rows.compactMap { $0.event?.id }))
        UserDefaults.standard.set(Array(seenEvents),forKey:"seen-events")
        let currentIDs = Set(snapshots.values.flatMap(\.items).map(\.id))
        interestRatings = interestRatings.filter { currentIDs.contains($0.key) }
        if let bytes = try? JSONEncoder().encode(interestRatings) { try? bytes.write(to:cacheDirectory.appendingPathComponent("interest-ratings.json"),options:.atomic) }
        productBoard = Products.board(catalog: productCatalog, pulse: productPulse, news: todayItems.map { item in
            var value = item; value.title_zh = title(for: item); return value
        })
        onUpdate?()
    }

    func start() {
        schedule()
        Task { await refresh() }
    }
    func schedule() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Double(max(5, preferences.refreshMinutes) * 60), repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.refresh() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }
    func markRead(_ item: NewsItem) {
        if let event = item.event ?? eventByArticle[item.id] {
            seen.formUnion(event.urls); seenEvents.insert(event.id)
            UserDefaults.standard.set(Array(seenEvents),forKey:"seen-events")
        } else { seen.insert(item.url) }
        let retained = Array(seen.intersection(Set(snapshots.values.flatMap { $0.items.map(\.url) })))
        UserDefaults.standard.set(Array(retained.prefix(15000)), forKey: "seen-urls")
        onUpdate?()
    }
    func markAllRead() {
        seen.formUnion(items.map(\.url))
        seenEvents.formUnion(newsItems.compactMap { $0.event?.id })
        UserDefaults.standard.set(Array(seenEvents),forKey:"seen-events")
        UserDefaults.standard.set(Array(seen.prefix(15000)), forKey: "seen-urls")
        onUpdate?()
    }
    func isRead(_ item: NewsItem) -> Bool {
        if let event = item.event ?? eventByArticle[item.id] { return NewsEvents.isRead(event,seenURLs:seen,seenEvents:seenEvents) }
        return seen.contains(item.url)
    }

    func refresh(range: String = "24h") async {
        guard !loading, ["24h", "7d"].contains(range) else { return }
        loading = true; error = nil; onUpdate?()
        defer { loading = false; onUpdate?() }
        // Every refresh runs the full collector; original feeds can update while it is still running.
        async let directUpdates = DirectFeeds.refresh(directFeeds, cached: directFeedCache, session: session)
        async let productUpdates = Products.refresh(cached: productPulse, session: session)
        let seed = ["24h", "7d"].compactMap { snapshots[$0] }.flatMap(\.items) + initialCollectorSeed
        async let collected = collector.collect(directory: cacheDirectory, seed: seed)
        directFeedCache = await directUpdates
        mergeDirectFeeds(); recalculate(); onUpdate?()
        do {
            for parsed in try await collected {
                let key = parsed.window_hours == 24 ? "24h" : "7d"
                snapshots[key] = SourceTimes.apply(parsed, cached: sourceTimes)
                if let bytes = try? JSONEncoder().encode(parsed) { try? bytes.write(to: cacheDirectory.appendingPathComponent("latest-\(key).json"), options: .atomic) }
            }
            initialCollectorSeed = []
        } catch { self.error = error.localizedDescription }
        // Show newly fetched original-source news even if the aggregate host is stale or failed.
        if snapshots[range] == nil {
            snapshots[range] = NewsData(generated_at: "", window_hours: range == "24h" ? 24 : 168,
                total_items: 0, source_count: 0, site_stats: [], items: [])
        }
        mergeDirectFeeds()
        sourceTimes = await SourceTimes.refresh(snapshots[range]?.items ?? [], cached: sourceTimes, session: session)
        if let bytes = try? JSONEncoder().encode(sourceTimes) { try? bytes.write(to: cacheDirectory.appendingPathComponent("source-times.json"), options: .atomic) }
        mergeSourceTimes()
        productPulse = await productUpdates
        if let bytes = try? JSONEncoder().encode(productPulse) { try? bytes.write(to: cacheDirectory.appendingPathComponent("product-pulse.json"), options: .atomic) }
        if let bytes = try? JSONEncoder().encode(directFeedCache) {
            try? bytes.write(to: cacheDirectory.appendingPathComponent("direct-feeds.json"), options: .atomic)
        }
        mergeDirectFeeds()
        lastChecked = Date()
        UserDefaults.standard.set(lastChecked, forKey: "last-checked")
        recalculate()
        await enrichTodayEvents()
        await translateTodayHeadlines()
        if range == "24h" { startScoring() }
    }

    private func enrichTodayEvents() async {
        // Small daily batch; grouping and scores are visible before any body retrieval.
        func needsReading(_ article:EventArticle) -> Bool {
            guard let fetched = documents[article.url].flatMap({parseDate($0.fetchedAt)}) else { return true }
            return Date().timeIntervalSince(fetched) >= 6 * 3600
        }
        func needsBody(_ row:NewsItem) -> Bool {
            row.event?.reports.contains { $0.articles.first.map(needsReading) == true } == true
        }
        let candidatesForReading = todayEvents.filter { row in
            guard rating(for:row).sortScore >= 7 || TechnicalSignals.shouldRead(row) else { return false }
            return row.event?.reports.contains { report in
                (report.articles.first.map(needsReading) == true) ||
                report.points.contains { !Scoring.matches($0,#"[\p{Han}]"#) && titleTranslations[$0] == nil }
            } == true
        }.sorted { a,b in
            if needsBody(a) != needsBody(b) { return needsBody(a) }
            return rating(for:a).sortScore > rating(for:b).sortScore
        }
        // Reserve one of the same three slots for a technical article below the old cutoff.
        let discovery = candidatesForReading.first { rating(for:$0).sortScore < 7 && needsBody($0) }
        let leaders = Array(([discovery].compactMap { $0 } + candidatesForReading.filter { $0.id != discovery?.id }).prefix(3))
        let articles = leaders.flatMap { row in
            (row.event?.reports ?? []).prefix(3).compactMap { $0.articles.first }
        }
        let candidates = articles.filter(needsReading)
        if !candidates.isEmpty {
            let fetched = await withTaskGroup(of:ArticleDocument.self) { group in
                for article in candidates { group.addTask { await ArticleDocument.fetch(url:article.url,title:article.title) } }
                var values: [ArticleDocument] = []
                for await document in group { values.append(document) }
                return values
            }
            for document in fetched { documents[document.url] = document }
            if let bytes = try? JSONEncoder().encode(documents) { try? bytes.write(to:cacheDirectory.appendingPathComponent("documents-v2.json"),options:.atomic) }
            recalculate()
        }
        let selectedIDs = Set(leaders.flatMap { $0.event?.memberIDs ?? [$0.id] })
        let points = NewsEvents.unique(todayEvents.filter { row in row.event?.memberIDs.contains(where:{selectedIDs.contains($0)}) == true }
            .flatMap { $0.event?.reports.flatMap(\.points) ?? [] })
            .filter { !Scoring.matches($0,#"[\p{Han}]"#) && titleTranslations[$0] == nil }.prefix(6)
        let session = self.session
        let translated = await withTaskGroup(of:(String,String?).self) { group in
            for point in points { group.addTask { (point,await InterestScore.translate(point,session:session)) } }
            var values:[String:String] = [:]
            for await (point,value) in group { if let value { values[point] = value } }
            return values
        }
        if !translated.isEmpty {
            titleTranslations.merge(translated) { _,new in new }
            if let bytes = try? JSONEncoder().encode(titleTranslations) { try? bytes.write(to:cacheDirectory.appendingPathComponent("headline-translations.json"),options:.atomic) }
            recalculate()
        }
    }

    private func translateTodayHeadlines() async {
        // Coverage alone can lift an event above 7 even when each raw headline scores low.
        let candidates = todayEvents.filter { rating(for:$0).sortScore >= 7 && !rating(for:$0).hasChineseBrief }
            .sorted { rating(for:$0).sortScore > rating(for:$1).sortScore }.prefix(5)
        let session = self.session
        let translations = await withTaskGroup(of:(String,String?).self) { group in
            for item in candidates { group.addTask { (item.title, await InterestScore.translate(item.title,session:session)) } }
            var result:[String:String] = [:]
            for await (title,translated) in group { if let translated { result[title] = translated } }
            return result
        }
        guard !translations.isEmpty else { return }
        titleTranslations.merge(translations) { _, new in new }
        if let bytes = try? JSONEncoder().encode(titleTranslations) { try? bytes.write(to:cacheDirectory.appendingPathComponent("headline-translations.json"),options:.atomic) }
        recalculate()
    }

    private func mergeSourceTimes() {
        for range in Array(snapshots.keys) {
            if let snapshot = snapshots[range] { snapshots[range] = SourceTimes.apply(snapshot, cached: sourceTimes) }
        }
    }

    private func mergeDirectFeeds() {
        for range in Array(snapshots.keys) {
            if let snapshot = snapshots[range] { snapshots[range] = DirectFeeds.merge(snapshot, feeds: directFeeds, cached: directFeedCache) }
        }
    }

    func save(_ newPreferences: Preferences, key: String?) throws {
        if newPreferences.aiEnabled {
            guard let base = URL(string: newPreferences.apiBaseURL), base.scheme == "https", base.host != nil, base.user == nil, base.password == nil, base.query == nil, base.fragment == nil, !newPreferences.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw NewsError.message("启用 AI 评分前，请填写 HTTPS API 地址和模型名称。") }
            let usableKey = key ?? apiKey ?? KeyStore.read()
            guard !usableKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw NewsError.message("启用 AI 评分需要填写 API Key。") }
        }
        if let key { try KeyStore.write(key); apiKey = key }
        generation += 1
        scoringTask?.cancel(); scoring = false
        preferences = newPreferences
        if cachedAI.profile != profile { cachedAI = RatingCache(profile: profile, ratings: [:], fingerprints: [:]) }
        UserDefaults.standard.set(try JSONEncoder().encode(preferences), forKey: "preferences")
        aiError = nil
        recalculate(); schedule(); startScoring()
    }

    func startScoring() {
        guard preferences.aiEnabled, !scoring else { return }
        scoringTask = Task { await scoreNewItems() }
    }
    private func scoreNewItems() async {
        guard preferences.aiEnabled, !scoring else { return }
        // Scoring must not depend on the currently selected UI filter.
        let candidates = items.filter { item in
            guard Self.isToday(item) else { return false }
            guard rating(for:item).sortScore >= 7, rating(for:item).briefBasis == "headline" || !rating(for:item).hasChineseBrief else { return false }
            if cachedAI.profile == profile, cachedAI.fingerprints[item.id] == fingerprint(item),
               let previous = cachedAI.ratings[item.id], previous.method == "ai",
               let attemptedAt = parseDate(previous.assessedAt), Date().timeIntervalSince(attemptedAt) < 6 * 3600 { return false }
            return true
        }
        let batch = Array(candidates.sorted { first, second in
            // This only orders body retrieval; a headline never earns release points.
            let pa = priority(for: first).value, pb = priority(for: second).value
            if pa != pb { return pa > pb }
            let a = Scoring.majorPublisher(at: first.url) != nil
            let b = Scoring.majorPublisher(at: second.url) != nil
            return a != b ? a : (first.date ?? .distantPast) > (second.date ?? .distantPast)
        }.prefix(5))
        guard !batch.isEmpty else { return }
        if apiKey == nil { apiKey = KeyStore.read() }
        guard let key = apiKey, !key.isEmpty else { aiError = "尚未配置 API Key；关注分已显示，暂不补充正文分析。"; onUpdate?(); return }
        scoring = true; aiError = nil; onUpdate?()
        let requestGeneration = generation
        defer { if requestGeneration == generation { scoring = false; onUpdate?() } }
        do {
            var base = preferences.apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !base.hasSuffix("/chat/completions") { base += "/chat/completions" }
            guard let url = URL(string: base), url.scheme == "https" else { throw NewsError.message("评分 API 地址无效。") }
            var evidenceByID: [String: [ArticleDocument]] = [:]
            var payload: [[String: Any]] = []
            for item in batch {
                try Task.checkCancellation()
                var related: [ArticleDocument] = []
                let current: ArticleDocument
                if let cached = documents[item.url], let fetched = parseDate(cached.fetchedAt), Date().timeIntervalSince(fetched) < 6 * 3600 { current = cached }
                else { current = await ArticleDocument.fetch(url: item.url, title: item.displayTitle); documents[item.url] = current }
                related.append(current)
                // Retrieved historical bodies are context, never inferred competitor facts.
                let terms = Set(item.title.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count >= 4 })
                let history = (snapshots["7d"]?.items ?? []).filter { old in
                    old.id != item.id && old.url != item.url && (old.date ?? .distantPast) < (item.date ?? .distantPast) && Scoring.category(for: old) == Scoring.category(for: item)
                }.sorted { a, b in
                    func overlap(_ value: NewsItem) -> Int { terms.filter { value.title.lowercased().contains($0) }.count }
                    return overlap(a) > overlap(b)
                }.filter { old in terms.filter { old.title.lowercased().contains($0) }.count >= 2 }.prefix(2)
                for old in history {
                    var doc = documents[old.url]
                    if doc == nil { doc = await ArticleDocument.fetch(url: old.url, title: old.displayTitle); documents[old.url] = doc }
                    if let doc, doc.readable { related.append(doc) }
                }
                evidenceByID[item.id] = related
                payload.append(["id": item.id, "title": item.displayTitle, "source": item.source, "url": item.url,
                    "categoryHint": Scoring.category(for: item).rawValue,
                    "documents": related.map { ["url": $0.url, "title": $0.title, "text": String($0.text.prefix(9000)), "truncated": $0.truncated || $0.text.count > 9000, "error": $0.error as Any? ?? NSNull()] }])
            }
            if let data = try? JSONEncoder().encode(documents) { try? data.write(to: cacheDirectory.appendingPathComponent("documents-v2.json"), options: .atomic) }
            try Task.checkCancellation()
            guard requestGeneration == generation else { return }
            let input = String(data: try JSONSerialization.data(withJSONObject: payload), encoding: .utf8)!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"; request.timeoutInterval = 60
            request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["model": preferences.model, "messages": [["role": "system", "content": Scoring.systemPrompt], ["role": "user", "content": input]], "temperature": 0.1, "max_tokens": 10000])
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForResource = 75
            let client = URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
            defer { client.invalidateAndCancel() }
            let (bytes, response) = try await client.data(for: request)
            try Task.checkCancellation()
            guard requestGeneration == generation else { return }
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                throw NewsError.message("评分服务返回 HTTP \(code)，请检查 API 配置；已评估结果保留。")
            }
            guard bytes.count < 2_000_000,
                let json = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                let choices = json["choices"] as? [[String: Any]], let message = choices.first?["message"] as? [String: Any], let content = message["content"] as? String else { throw NewsError.message("无法读取模型返回的评分。") }
            let scored = try Scoring.decodeAI(content, items: batch, documents: evidenceByID, model: preferences.model)
            if cachedAI.profile != profile { cachedAI = RatingCache(profile: profile, ratings: [:], fingerprints: [:]) }
            for item in batch { if let score = scored[item.id] { cachedAI.ratings[item.id] = score; cachedAI.fingerprints[item.id] = fingerprint(item) } }
            let ids = Set(snapshots.values.flatMap { $0.items.map(\.id) })
            cachedAI.ratings = cachedAI.ratings.filter { ids.contains($0.key) }
            cachedAI.fingerprints = cachedAI.fingerprints.filter { ids.contains($0.key) }
            if let data = try? JSONEncoder().encode(cachedAI) { try? data.write(to: cacheDirectory.appendingPathComponent("ratings.json"), options: .atomic) }
            recalculate()
        } catch is CancellationError { } catch { if requestGeneration == generation { aiError = error.localizedDescription } }
    }

    func dashboardData(range: String) -> NewsData? {
        guard var result = snapshots[range] else { return nil }
        result.product_board = productBoard
        result.items = (groupedSnapshots[range] ?? result.items).map { item in
            var item = item; item.rating = rating(for:item); item.priority = priority(for:item)
            let read = isRead(item)
            if item.event != nil { item.event?.read = read }
            if (item.rating?.sortScore ?? -1) >= 7 { item.title_zh = title(for:item) }
            return item
        }
        result.total_items = result.items.count
        return result
    }
}
