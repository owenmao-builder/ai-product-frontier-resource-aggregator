import Foundation

struct AIProduct: Codable, Identifiable {
    var id: String
    var name: String
    var maker: String
    var major: Bool
    var category: String
    var summary: String
    var difference: String
    var access: String
    var homepage: String
    var sourceURL: String
    var repository: String?
    var aliases: [String]
    // Official announcement date, not the date we fetched or edited the entry.
    var releasedOn: String? = nil
    var releaseKind: String? = nil
    var signals: [ProductSignal]? = nil
    var relatedNews: [ProductNews]? = nil
    var isHot: Bool { !(signals ?? []).isEmpty }
}

struct ProductSignal: Codable {
    var kind: String
    var label: String
    var title: String
    var url: String
    var observedAt: String
}

struct ProductNews: Codable {
    var title: String
    var url: String
    var date: String
}

struct ProductBoard: Codable {
    var verifiedAt: String
    var items: [AIProduct]
    var checkedAt: String? = nil
    var githubFetchedAt: String? = nil
    var hnFetchedAt: String? = nil
    var errors: [String: String]? = nil
}

struct GitHubTrend: Codable {
    var repository: String
    var weeklyStars: Int
}

struct HNProductStory: Codable {
    var id: String
    var title: String
    var url: String
    var points: Int
    var comments: Int
    var publishedAt: String
}

struct ProductPulse: Codable {
    var github: [GitHubTrend] = []
    var discussions: [HNProductStory] = []
    var checkedAt: String?
    var githubFetchedAt: String?
    var hnFetchedAt: String?
    var errors: [String: String] = [:]
}

enum Products {
    static let trendingURL = "https://github.com/trending?since=weekly"
    static let method = "大厂上新：官方确认、最近 7 个自然日（含今天）发布的具体模型、版本或新功能，显示官方发布日期；过期或日期未核实的不展示。近期热门：GitHub 周榜本周新增 ≥500 星，或近 7 天相关 HN 话题 ≥100 赞；大厂条目仍须满足发布时限。仅覆盖已核实条目，热度不代表质量。超过 24 小时的热度停止计入。"

    static func releaseDate(_ product: AIProduct, calendar: Calendar = .current) -> Date? {
        guard let day = product.releasedOn, day.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
              let kind = product.releaseKind, ["新模型", "新版本", "新功能", "新工具", "新架构"].contains(kind),
              publicArticleURL(product.sourceURL) != nil else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: day), formatter.string(from: date) == day else { return nil }
        return date
    }

    static func isRecentRelease(_ product: AIProduct, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let date = releaseDate(product, calendar: calendar),
              let firstDay = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) else { return false }
        return date >= firstDay && date <= now
    }

    static func bundled<T: Decodable>(_ name: String, as type: T.Type) -> T? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("seed/" + name), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func refresh(cached: ProductPulse, session: URLSession, now: Date = Date()) async -> ProductPulse {
        var result = cached
        result.checkedAt = timestamp(now)
        var query = URLComponents(string: "https://hn.algolia.com/api/v1/search")!
        query.queryItems = [URLQueryItem(name: "tags", value: "story"), URLQueryItem(name: "numericFilters", value: "created_at_i>\(Int(now.timeIntervalSince1970) - 7 * 86400),points>=100"), URLQueryItem(name: "hitsPerPage", value: "500")]
        let discussionURL = query.url!
        async let github = fetch(URL(string: trendingURL)!, session: session)
        async let hn = fetch(discussionURL, session: session)
        do {
            let data = try await github.get()
            result.github = try parseGitHub(data)
            result.githubFetchedAt = timestamp(now)
            result.errors.removeValue(forKey: "GitHub")
        } catch { result.errors["GitHub"] = "GitHub 热度更新失败，保留上次数据。" }
        do {
            let data = try await hn.get()
            result.discussions = try parseHN(data, now: now)
            result.hnFetchedAt = timestamp(now)
            result.errors.removeValue(forKey: "Hacker News")
        } catch { result.errors["Hacker News"] = "Hacker News 热度更新失败，保留上次数据。" }
        return result
    }

    private static func fetch(_ url: URL, session: URLSession) async -> Result<Data, Error> {
        do {
            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 20)
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count <= 4_000_000 else { throw NewsError.message("热度源暂不可用") }
            return .success(data)
        } catch { return .failure(error) }
    }

    static func parseGitHub(_ data: Data) throws -> [GitHubTrend] {
        guard let html = String(data: data, encoding: .utf8) else { throw NewsError.message("无法读取 GitHub 周榜") }
        let rows = captures(#"(?s)<article\b[^>]*class="[^"]*\bBox-row\b[^"]*"[^>]*>(.*?)</article>"#, in: html)
        var seen = Set<String>()
        let results = rows.compactMap { row -> GitHubTrend? in
            guard let heading = captures(#"(?s)<h2\b[^>]*>(.*?)</h2>"#, in: row).first,
                  let repo = captures(#"href="/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)""#, in: heading).first,
                  let count = captures(#"([0-9,]+)\s+stars? this week"#, in: row).first,
                  let stars = Int(count.replacingOccurrences(of: ",", with: "")), seen.insert(repo.lowercased()).inserted else { return nil }
            return GitHubTrend(repository: repo, weeklyStars: stars)
        }
        guard !results.isEmpty else { throw NewsError.message("GitHub 周榜格式发生变化") }
        return results
    }

    static func parseHN(_ data: Data, now: Date) throws -> [HNProductStory] {
        struct Hit: Decodable {
            var objectID: String
            var title: String?
            var url: String?
            var points: Int?
            var num_comments: Int?
            var created_at_i: Double
        }
        struct Envelope: Decodable { var hits: [Hit] }
        var seen = Set<String>()
        return try JSONDecoder().decode(Envelope.self, from: data).hits.compactMap { hit in
            let date = Date(timeIntervalSince1970: hit.created_at_i)
            guard let title = hit.title, !title.isEmpty, let url = hit.url, publicArticleURL(url) != nil,
                  let points = hit.points, points >= 100, date >= now.addingTimeInterval(-7 * 86400), date <= now,
                  hit.objectID.allSatisfy(\.isNumber), !hit.objectID.isEmpty, seen.insert(hit.objectID).inserted else { return nil }
            return HNProductStory(id: hit.objectID, title: title, url: url, points: points, comments: hit.num_comments ?? 0, publishedAt: timestamp(date))
        }
    }

    static func matches(_ title: String, product: AIProduct) -> Bool {
        product.aliases.contains { alias in
            let escaped = NSRegularExpression.escapedPattern(for: alias)
            let pattern = alias.range(of: #"[\p{Han}]"#, options: .regularExpression) == nil ? "(?i)(?<![a-z0-9])" + escaped + "(?![a-z0-9])" : "(?i)" + escaped
            return Scoring.matches(title, pattern)
        }
    }

    static func isAnnouncement(_ url: String, product: AIProduct) -> Bool {
        url.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == product.sourceURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    static func board(catalog: ProductBoard, pulse: ProductPulse, news: [NewsItem], now: Date = Date()) -> ProductBoard {
        func fresh(_ value: String?) -> Bool {
            guard let date = parseDate(value) else { return false }
            return date <= now && date >= now.addingTimeInterval(-86400)
        }
        // Parse dates once for the shared news list, not once per product on the UI thread.
        let todayNews: [(item: NewsItem, date: Date)] = news.compactMap { item in
            guard let date = item.date, date <= now, Calendar.current.isDate(date, inSameDayAs: now), item.safeURL != nil else { return nil }
            return (item, date)
        }.sorted { $0.date > $1.date }
        var board = catalog
        board.checkedAt = pulse.checkedAt; board.githubFetchedAt = pulse.githubFetchedAt; board.hnFetchedAt = pulse.hnFetchedAt; board.errors = pulse.errors
        board.items = catalog.items.filter { !$0.major || isRecentRelease($0, now: now) }.map { product in
            var value = product
            var signals: [ProductSignal] = []
            if fresh(pulse.githubFetchedAt), let repo = product.repository,
               let trend = pulse.github.first(where: { $0.repository.lowercased() == repo.lowercased() && $0.weeklyStars >= 500 }) {
                signals.append(ProductSignal(kind: "github", label: "本周 +\(trend.weeklyStars.formatted()) 星", title: "GitHub 本周趋势榜 · " + trend.repository, url: trendingURL, observedAt: pulse.githubFetchedAt!))
            }
            if fresh(pulse.hnFetchedAt) {
                let related = pulse.discussions.filter { story in
                    guard let date = parseDate(story.publishedAt), date <= now, date >= now.addingTimeInterval(-7 * 86400) else { return false }
                    return story.points >= 100 && (matches(story.title, product: product) || isAnnouncement(story.url, product: product))
                }.sorted { a, b in
                    let ownHost = URL(string: product.sourceURL)?.host
                    let ownA = URL(string: a.url)?.host == ownHost, ownB = URL(string: b.url)?.host == ownHost
                    if ownA != ownB { return ownA }
                    return a.points > b.points
                }
                for story in related.prefix(2) {
                    signals.append(ProductSignal(kind: "hn", label: "HN \(story.points) 赞 · \(story.comments) 评论", title: story.title, url: "https://news.ycombinator.com/item?id=" + story.id, observedAt: pulse.hnFetchedAt!))
                }
            }
            value.signals = signals
            var seen = Set<String>()
            value.relatedNews = Array(todayNews.filter { (matches($0.item.title, product: product) || isAnnouncement($0.item.url, product: product)) && seen.insert($0.item.url).inserted }.prefix(2))
                .map { ProductNews(title: $0.item.displayTitle, url: $0.item.url, date: timestamp($0.date)) }
            return value
        }.filter { $0.major || $0.isHot }.sorted {
            if $0.major != $1.major { return $0.major }
            if ($0.releaseKind == "新模型") != ($1.releaseKind == "新模型") { return $0.releaseKind == "新模型" }
            if $0.releasedOn != $1.releasedOn { return ($0.releasedOn ?? "") > ($1.releasedOn ?? "") }
            return $0.name < $1.name
        }
        return board
    }

    private static func captures(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }; return String(text[range])
        }
    }
}
