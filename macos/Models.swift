import Foundation

struct NewsItem: Codable, Identifiable {
    var id: String
    var site_id: String
    var site_name: String
    var source: String
    var title: String
    var url: String
    var published_at: String?
    var first_seen_at: String
    var last_seen_at: String
    var title_original: String?
    var title_en: String?
    var title_zh: String?
    var title_bilingual: String?
    var rating: NewsRating?
    var source_publication: SourcePublication? = nil
    var priority: NewsPriority? = nil
    var displayTitle: String { ([title_zh, title_en, title_bilingual, title].compactMap { $0 }.first { !$0.isEmpty } ?? title).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines) }
    var date: Date? { newsTime().date }
    func newsTime(now: Date = Date()) -> NewsTime {
        if let source = source_publication, source.sourceURL == url,
           let published = parseDate(source.publishedAt), published <= now,
           let verified = parseDate(source.verifiedAt), verified <= now {
            return NewsTime(date: published, isCollection: false, explanation: "已核对原站发布时间，按北京时间（UTC+8）显示。")
        }
        let published = parseDate(published_at)
        let collected = parseDate(first_seen_at)
        // These upstream scrapers turn the relative hint "刚刚" into their fetch timestamp.
        let collectionProxy = ["aibase", "tophub"].contains(site_id) && published != nil && published == collected
        // Allow small source-clock skew, but never display a future publication.
        let afterCollection = published.flatMap { date in collected.map { date.timeIntervalSince($0) > 300 } } ?? false
        if let published, published <= now, !afterCollection, !collectionProxy {
            return NewsTime(date: published, isCollection: false, explanation: "信息源发布时间，按北京时间（UTC+8）显示。")
        }
        let reason = collectionProxy ? "来源仅提供相对时间，尚无准确发布时间" : afterCollection ? "来源发布时间晚于收录时间" : published != nil ? "来源发布时间在未来" : "来源未提供有效发布时间"
        if let collected, collected <= now {
            return NewsTime(date: collected, isCollection: true, explanation: "\(reason)，暂显示收录时间；不代表发布时间。")
        }
        return NewsTime(date: nil, isCollection: false, explanation: "发布时间和收录时间均缺失或异常。")
    }
    var safeURL: URL? {
        guard let value = URL(string: url), ["https", "http"].contains(value.scheme?.lowercased() ?? ""), value.host != nil else { return nil }
        return value
    }
}

struct NewsTime {
    var date: Date?
    var isCollection: Bool
    var explanation: String
    var label: String { (isCollection ? "收录 " : "") + beijingTimeLabel(date: date) }
    var isPublished: Bool { date != nil && !isCollection }
    func orderedBefore(_ other: NewsTime) -> Bool {
        if isPublished != other.isPublished { return isPublished }
        return (date ?? .distantPast) > (other.date ?? .distantPast)
    }
}

struct SourcePublication: Codable {
    var publishedAt: String
    var verifiedAt: String
    var sourceURL: String
}

var beijingCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    return calendar
}

func beijingTimeLabel(date: Date?, now: Date = Date()) -> String {
    guard let date else { return "时间未提供" }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.timeZone = beijingCalendar.timeZone
    formatter.dateFormat = beijingCalendar.isDate(date, inSameDayAs: now) ? "HH:mm" : "MM-dd HH:mm"
    return formatter.string(from: date)
}

func aggregateSnapshotLabel(_ raw: String?, now: Date = Date()) -> String {
    guard let date = parseDate(raw) else { return "聚合内容暂未取得" }
    let age = now.timeIntervalSince(date)
    guard age >= 0 else { return "聚合快照时间异常" }
    return "聚合快照 \(beijingTimeLabel(date: date, now: now))" + (age >= 3600 ? " · \(Int(age / 3600))小时未更新" : "")
}

struct SiteStat: Codable {
    var site_id: String
    var site_name: String
    var count: Int
    var raw_count: Int
}

struct NewsData: Codable {
    var generated_at: String
    var window_hours: Int
    var total_items: Int
    var total_items_ai_raw: Int?
    var total_items_raw: Int?
    var total_items_all_mode: Int?
    var topic_filter: String?
    var archive_total: Int?
    var site_count: Int?
    var source_count: Int
    var site_stats: [SiteStat]
    var items: [NewsItem]
    var direct_sources: [DirectFeedStatus]? = nil
    var product_board: ProductBoard? = nil
    var product_discovery: ProductDiscovery? = nil
    var collection: CollectionStatus? = nil
}

struct NewsRating: Codable, Equatable {
    var score: Double?
    var reason: String
    var tags: [String]
    var method: String
    var assessedAt: String
    var model: String?
    var version: String? = nil
    var category: String? = nil
    var evidenceLevel: String? = nil
    var dimensions: [RatingDimension]? = nil
    var sources: [RatingSource]? = nil
    var comparison: String? = nil
    var gaps: [String]? = nil
    var release: ReleaseSignal? = nil
    var chineseTitle: String? = nil
    var highlights: [String]? = nil
    var briefBasis: String? = nil
    var isInterest: Bool { version == InterestScore.version }
    var baseScore: Double? { dimensions.flatMap { Scoring.total($0) } }
    var releaseBonus: Double { Scoring.releaseBonus(for: self) }
    var hasChineseBrief: Bool {
        guard let title = chineseTitle, Scoring.matches(title, "[\\p{Han}]"),
              let points = highlights, (2...4).contains(points.count) else { return false }
        return points.allSatisfy { Scoring.matches($0, "[\\p{Han}]") && !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    var isScored: Bool { (version == Scoring.version || isInterest) && score.map { $0.isFinite && (0...10).contains($0) } == true }
    var sortScore: Double { isScored ? score! : -1 }
    var displayScore: String { isScored ? String(format: "%.1f", score!) : "—" }
    var categoryLabel: String { NewsCategory(rawValue: category ?? "other")?.label ?? "待分类" }
    var statusLabel: String { evidenceLevel == "A" ? "A 充分" : evidenceLevel == "B" ? "B 待验" : "C 不足" }
    var scoreLabel: String { isInterest ? "关注分" : statusLabel }
    var evidenceExplanation: String {
        if evidenceLevel != "A" && evidenceLevel != "B" { return "目前主要依据标题或有限材料，原文及比较结论尚未核实；不影响关注分。" }
        return evidenceLevel == "A" ? "关键判断有充分直接材料支持；涉及性能比较时有相应对照。" : "有原文依据，但关键收益、影响或适用范围仍有待验证。"
    }
}

struct ReleaseSignal: Codable, Equatable {
    var kind: String
    var publisher: String
    var url: String
    var quote: String
    var reason: String
}

struct RatingDimension: Codable, Equatable {
    var key: String
    var value: Double
    var reason: String
    var weight: Double? = nil
}

struct RatingSource: Codable, Equatable {
    var url: String
    var title: String
    var quote: String
}

struct ReviewedEntry: Codable {
    var id: String
    var fingerprint: String
    var rating: NewsRating
}

struct ReviewedArchive: Codable {
    var version: String
    var generatedAt: String
    var entries: [ReviewedEntry]
}

private enum ParsedDates {
    static let lock = NSLock()
    static let cache: NSCache<NSString, NSDate> = { let value = NSCache<NSString, NSDate>(); value.countLimit = 20000; return value }()
    static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    static let whole = ISO8601DateFormatter()
}

func parseDate(_ text: String?) -> Date? {
    guard let text, !text.isEmpty else { return nil }
    if let cached = ParsedDates.cache.object(forKey: text as NSString) { return cached as Date }
    ParsedDates.lock.lock()
    defer { ParsedDates.lock.unlock() }
    let date = ParsedDates.fractional.date(from: text) ?? ParsedDates.whole.date(from: text)
    if let date { ParsedDates.cache.setObject(date as NSDate, forKey: text as NSString) }
    return date
}

func timestamp(_ date: Date = Date()) -> String { ISO8601DateFormatter().string(from: date) }

func timeLabel(_ text: String?) -> String {
    timeLabel(date: parseDate(text))
}

func timeLabel(date: Date?) -> String {
    guard let date else { return "时间未提供" }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "MM-dd HH:mm"
    return formatter.string(from: date)
}
