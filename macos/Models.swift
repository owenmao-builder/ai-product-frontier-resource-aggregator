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
    var displayTitle: String { ([title_zh, title_en, title_bilingual, title].compactMap { $0 }.first { !$0.isEmpty } ?? title).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines) }
    var date: Date? { parseDate(published_at) ?? parseDate(first_seen_at) }
    var safeURL: URL? {
        guard let value = URL(string: url), ["https", "http"].contains(value.scheme?.lowercased() ?? ""), value.host != nil else { return nil }
        return value
    }
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
    var baseScore: Double? { dimensions.flatMap { Scoring.total($0) } }
    var releaseBonus: Double { Scoring.releaseBonus(for: self) }
    var hasChineseBrief: Bool {
        guard let title = chineseTitle, Scoring.matches(title, "[\\p{Han}]"),
              let points = highlights, (2...4).contains(points.count) else { return false }
        return points.allSatisfy { Scoring.matches($0, "[\\p{Han}]") && !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    var isScored: Bool { version == Scoring.version && score != nil }
    var sortScore: Double { isScored ? score! : -1 }
    var displayScore: String { isScored ? String(format: "%.1f", score!) : "—" }
    var categoryLabel: String { NewsCategory(rawValue: category ?? "other")?.label ?? "待分类" }
    var statusLabel: String { !isScored ? "C 不足" : evidenceLevel == "A" ? "A 充分" : "B 待验" }
    var evidenceExplanation: String {
        if !isScored { return "材料不足，只有标题或缺少关键依据；暂不评分，等待补充材料。" }
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

func parseDate(_ text: String?) -> Date? {
    guard let text else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
}

func timestamp(_ date: Date = Date()) -> String { ISO8601DateFormatter().string(from: date) }

func timeLabel(_ text: String?) -> String {
    guard let date = parseDate(text) else { return "时间未提供" }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "MM-dd HH:mm"
    return formatter.string(from: date)
}
