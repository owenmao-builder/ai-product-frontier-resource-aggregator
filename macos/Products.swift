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
    var discoveredAutomatically: Bool? = nil
    var verifiedAt: String? = nil
    var dateBasis: String? = nil
    // Attributed release context, used only for this recent product announcement.
    var technicalHighlights: [String]? = nil
    var discoveryBasis: String? = nil
    var firstSeenAt: String? = nil
    var lastSeenAt: String? = nil
    var isHot: Bool { !(signals ?? []).isEmpty }
}

struct ProductSignal: Codable {
    var kind: String
    var label: String
    var title: String
    var url: String
    var observedAt: String
    var sourceCount: Int? = nil
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
    var discovery: ProductDiscovery? = nil
}

struct PendingProduct: Codable {
    var name: String
    var maker: String
    var newsTitle: String
    var newsURL: String
    var reason: String
    var officialURL: String? = nil
}

struct ProductDiscovery: Codable {
    var checkedAt: String
    var items: [AIProduct]
    var pending: [PendingProduct]
    var errors: [String]
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
    static let method = "每轮从新闻、X/Twitter 作者讨论和开源社区发现具体产品，不限已有清单或大厂。近 7 天的独立作者与媒体讨论可进入近期热门，热度按原始来源去重；社区讨论日期不冒充首发日期。大厂上新仍只展示最近 7 个北京时间自然日内已核实的官方发布；较早发布但最近走红的大厂产品也可进入热门。Hugging Face 趋势榜、GitHub 周增 ≥500 星或近 7 天 HN ≥100 赞也计入热度，榜单核对超过 24 小时失效。"

    static func nameKey(_ name:String) -> String { name.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "." } }

    static func repositoryKey(_ raw:String) -> String? {
        let value=raw.trimmingCharacters(in:.whitespacesAndNewlines)
        let path:String
        if value.contains("://") {
            guard let url=URL(string:value),["github.com","www.github.com"].contains(url.host?.lowercased() ?? "") else { return nil }; path=url.path
        } else { path=value }
        let parts=path.split(separator:"/")
        guard parts.count >= 2 else { return nil }
        return (String(parts[0]) + "/" + String(parts[1])).lowercased()
    }

    static func isRecentMajorRelease(_ product: AIProduct, now: Date = Date()) -> Bool {
        product.major && product.discoveryBasis != "community" && isRecentRelease(product,now:now)
    }

    static func freshSignal(_ signal:ProductSignal, now:Date = Date()) -> Bool {
        guard let date=parseDate(signal.observedAt),publicArticleURL(signal.url) != nil else { return false }
        let lifetime:Double = ["x","community"].contains(signal.kind) ? 7 * 86400 : 86400
        return (0...lifetime).contains(now.timeIntervalSince(date))
    }

    static func mergeSignals(_ first:[ProductSignal]?, _ second:[ProductSignal]?, now:Date = Date()) -> [ProductSignal] {
        var signals:[String:ProductSignal] = [:]
        for signal in (first ?? []) + (second ?? []) where freshSignal(signal,now:now) {
            let key = signal.kind == "hn" ? signal.kind + ":" + signal.url : signal.kind
            if signals[key].map({ (parseDate(signal.observedAt) ?? .distantPast) >= (parseDate($0.observedAt) ?? .distantPast) }) ?? true { signals[key] = signal }
        }
        func order(_ signal:ProductSignal) -> Int { signal.kind == "x" ? 0 : ["community","coverage"].contains(signal.kind) ? 1 : 2 }
        return signals.values.sorted { order($0) == order($1) ? ($0.sourceCount ?? 0) > ($1.sourceCount ?? 0) : order($0) < order($1) }
    }

    static func mergeNews(_ first:[ProductNews]?, _ second:[ProductNews]?, now:Date = Date()) -> [ProductNews] {
        var news:[String:ProductNews] = [:]
        for item in (first ?? []) + (second ?? []) {
            if let date=parseDate(item.date), (0...Double(7 * 86400)).contains(now.timeIntervalSince(date)),publicArticleURL(item.url) != nil { news[item.url] = item }
        }
        return Array(news.values.sorted { $0.date > $1.date }.prefix(8))
    }

    static func compatibleMaker(_ first:String, _ second:String) -> Bool {
        let generic:Set<String> = ["","开发者社区","开发者","社区","未知","unknown","community"]
        let a=nameKey(first),b=nameKey(second)
        return a == b || generic.contains(a) || generic.contains(b)
    }

    static func repositoryIdentity(_ product:AIProduct, host:String) -> String? {
        for value in [product.repository,product.homepage,product.sourceURL].compactMap({ $0 }) {
            let raw=value.contains("://") ? value : "https://github.com/" + value
            guard let url=URL(string:raw),[host,"www." + host].contains(url.host?.lowercased() ?? "") else { continue }
            let parts=url.path.split(separator:"/").map(String.init)
            guard parts.count >= 2, !(host == "huggingface.co" && ["spaces","datasets","models","api"].contains(parts[0])) else { continue }
            return parts.prefix(2).joined(separator:"/").lowercased()
        }
        return nil
    }

    static func compatibleIdentity(_ first:AIProduct, _ second:AIProduct) -> Bool {
        guard compatibleMaker(first.maker,second.maker) else { return false }
        for host in ["github.com","huggingface.co"] {
            if let a=repositoryIdentity(first,host:host),let b=repositoryIdentity(second,host:host),a != b { return false }
        }
        return true
    }

    static func mergedCatalog(_ bundled: ProductBoard, discovery: ProductDiscovery?, now: Date = Date()) -> ProductBoard {
        guard let discovery else { return bundled }
        func key(_ name: String) -> String { nameKey(name) }
        func names(_ product:AIProduct) -> Set<String> { Set(([product.name] + product.aliases).map(key)) }
        var result = bundled
        for product in discovery.items {
            let signals=mergeSignals(product.signals,nil,now:now)
            let recentCommunity = product.discoveryBasis == "community" && parseDate(product.lastSeenAt).map { (0...Double(7 * 86400)).contains(now.timeIntervalSince($0)) } == true
            guard (product.discoveryBasis != "community" && isRecentRelease(product,now:now)) || !signals.isEmpty || recentCommunity else { continue }
            if let index=result.items.firstIndex(where:{ compatibleIdentity($0,product) && (names($0).contains(key(product.name)) || names(product).contains(key($0.name))) }) {
                var existing=result.items[index]
                if existing.discoveryBasis == "community" && product.discoveryBasis == "official" {
                    existing.discoveryBasis = "official"; existing.releasedOn = product.releasedOn; existing.releaseKind = product.releaseKind
                    existing.sourceURL = product.sourceURL; existing.homepage = product.homepage; existing.verifiedAt = product.verifiedAt
                    existing.dateBasis = product.dateBasis; existing.major = product.major; existing.maker = product.maker
                }
                existing.repository = existing.repository ?? product.repository
                existing.signals = mergeSignals(existing.signals,signals,now:now)
                existing.relatedNews = mergeNews(existing.relatedNews,product.relatedNews,now:now)
                existing.firstSeenAt = existing.firstSeenAt ?? product.firstSeenAt
                existing.lastSeenAt = [existing.lastSeenAt,product.lastSeenAt].compactMap { $0 }.max()
                result.items[index] = existing
            } else { result.items.append(product) }
        }
        var status = discovery
        let confirmed = result.items.filter { $0.discoveryBasis != "community" && isRecentRelease($0, now: now) }
        status.pending = status.pending.filter { pending in !confirmed.contains { compatibleMaker($0.maker,pending.maker) && names($0).contains(key(pending.name)) } }
        result.discovery = status
        if discovery.items.contains(where:{ $0.discoveryBasis != "community" }) { result.verifiedAt = discovery.checkedAt }
        return result
    }

    static func releaseDate(_ product: AIProduct, calendar: Calendar = beijingCalendar) -> Date? {
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

    static func isRecentRelease(_ product: AIProduct, now: Date = Date(), calendar: Calendar = beijingCalendar) -> Bool {
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

    static func reportingSignal(_ product: AIProduct, events: [NewsItem], now: Date = Date(), catalog:[AIProduct] = []) -> ProductSignal? {
        let names = Set(([product.name] + product.aliases).map(nameKey))
        // Use the event's subject, not incidental competitor mentions or all articles about a brand.
        let matching = events.compactMap { row -> NewsEvent? in
            guard let event = row.event, let coverage = event.coverage, coverage.sourceCount >= 2,
                  let date = parseDate(event.latestAt), date <= now, beijingCalendar.isDate(date,inSameDayAs:now) else { return nil }
            if let subject=event.subject { return names.contains(nameKey(subject)) ? event : nil }
            let shared=catalog.contains { nameKey($0.name) != nameKey(product.name) && isAnnouncement($0.sourceURL,product:product) }
            return !shared && event.urls.contains(where:{ isAnnouncement($0,product:product) }) ? event : nil
        }.sorted { ($0.coverage!.sourceCount,$0.latestAt ?? "") > ($1.coverage!.sourceCount,$1.latestAt ?? "") }
        guard let event = matching.first, let coverage = event.coverage,
              let url = event.urls.first(where:{ publicArticleURL($0) != nil }), let date = event.latestAt else { return nil }
        return ProductSignal(kind:"coverage",label:coverage.label,title:"报道来源：" + coverage.sourceNames.joined(separator:"、"),
                             url:url,observedAt:date,sourceCount:coverage.sourceCount)
    }

    static func board(catalog: ProductBoard, pulse: ProductPulse, news: [NewsItem], events:[NewsItem] = [], now: Date = Date()) -> ProductBoard {
        func fresh(_ value: String?) -> Bool {
            guard let date = parseDate(value) else { return false }
            return date <= now && date >= now.addingTimeInterval(-86400)
        }
        // Parse dates once for the shared news list, not once per product on the UI thread.
        let todayNews: [(item: NewsItem, date: Date)] = news.compactMap { item in
            guard let date = item.date, date <= now, beijingCalendar.isDate(date, inSameDayAs: now), item.safeURL != nil else { return nil }
            return (item, date)
        }.sorted { $0.date > $1.date }
        var board = catalog
        board.checkedAt = pulse.checkedAt; board.githubFetchedAt = pulse.githubFetchedAt; board.hnFetchedAt = pulse.hnFetchedAt; board.errors = pulse.errors
        board.items = catalog.items.map { product in
            var value = product
            var signals = mergeSignals(product.signals,[reportingSignal(product,events:events,now:now,catalog:catalog.items)].compactMap { $0 },now:now)
            if fresh(pulse.githubFetchedAt), let rawRepo = product.repository, let repo=repositoryKey(rawRepo),
               let trend = pulse.github.first(where: { repositoryKey($0.repository) == repo && $0.weeklyStars >= 500 }) {
                signals.append(ProductSignal(kind: "github", label: "本周 +\(trend.weeklyStars.formatted()) 星", title: "GitHub 本周趋势榜 · " + trend.repository, url: trendingURL, observedAt: pulse.githubFetchedAt!))
            }
            let sharedAnnouncement=catalog.items.contains { nameKey($0.name) != nameKey(product.name) && isAnnouncement($0.sourceURL,product:product) }
            if fresh(pulse.hnFetchedAt) {
                let related = pulse.discussions.filter { story in
                    guard let date = parseDate(story.publishedAt), date <= now, date >= now.addingTimeInterval(-7 * 86400) else { return false }
                    return story.points >= 100 && (matches(story.title, product: product) || (!sharedAnnouncement && isAnnouncement(story.url, product: product)))
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
            value.signals = mergeSignals(signals,nil,now:now)
            var seen = Set<String>()
            let related = Array(todayNews.filter { (matches($0.item.title, product: product) || (!sharedAnnouncement && isAnnouncement($0.item.url, product: product))) && seen.insert($0.item.url).inserted }.prefix(2))
                .map { ProductNews(title: $0.item.displayTitle, url: $0.item.url, date: timestamp($0.date)) }
            value.relatedNews = mergeNews(product.relatedNews,related,now:now)
            return value
        }.filter { isRecentMajorRelease($0,now:now) || $0.isHot }.sorted {
            let a = $0.signals?.compactMap(\.sourceCount).max() ?? 0
            let b = $1.signals?.compactMap(\.sourceCount).max() ?? 0
            if a != b { return a > b }
            let ax = $0.signals?.contains(where:{ $0.kind == "x" }) == true, bx = $1.signals?.contains(where:{ $0.kind == "x" }) == true
            if ax != bx { return ax }
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
