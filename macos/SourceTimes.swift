import Foundation

enum SourceTimes {
    private struct Post: Decodable {
        var id: Int
        var date: String
        var date_gmt: String?
        var link: String
    }

    static func postID(_ item: NewsItem) -> Int? {
        guard item.site_id == "xinzhiyuan", let url = URLComponents(string: item.url),
              url.scheme == "https", url.host == "aiera.com.cn", url.path == "/asi-post.html",
              let raw = url.queryItems?.first(where: { $0.name == "id" })?.value,
              raw.allSatisfy(\.isNumber), let id = Int(raw), id > 0 else { return nil }
        return id
    }

    static func requestedPosts(_ items: [NewsItem], cached: [String: SourcePublication], now: Date) -> [Int: String] {
        var requested: [Int: String] = [:]
        for item in items {
            guard let id = postID(item) else { continue }
            // Resolve today's news only; don't backfill the historical archive.
            let dates = [parseDate(item.published_at), parseDate(item.first_seen_at)].compactMap { $0 }
            guard dates.contains(where: { beijingCalendar.isDate($0, inSameDayAs: now) }) else { continue }
            if let known = cached[item.url], known.sourceURL == item.url,
               let published = parseDate(known.publishedAt), published <= now,
               let checked = parseDate(known.verifiedAt), (0..<86400).contains(now.timeIntervalSince(checked)) { continue }
            requested[id] = item.url
            if requested.count == 100 { break }
        }
        return requested
    }

    static func parse(_ bytes: Data, requested: [Int: String], now: Date) throws -> [String: SourcePublication] {
        guard bytes.count <= 1_000_000 else { throw NewsError.message("原站时间数据过大") }
        let posts = try JSONDecoder().decode([Post].self, from: bytes)
        var result: [String: SourcePublication] = [:]
        for post in posts {
            guard let expectedURL = requested[post.id], post.link == expectedURL else { continue }
            let fields = [(post.date_gmt, "Z"), (Optional(post.date), "+08:00")]
            let published = fields.compactMap { raw, offset -> Date? in
                guard let raw, raw.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})?$"#, options: .regularExpression) != nil else { return nil }
                let hasZone = raw.range(of: #"(?:Z|[+-]\d{2}:\d{2})$"#, options: .regularExpression) != nil
                return parseDate(hasZone ? raw : raw + offset)
            }.first
            guard let published, published <= now else { continue }
            result[expectedURL] = SourcePublication(publishedAt: timestamp(published), verifiedAt: timestamp(now), sourceURL: expectedURL)
        }
        return result
    }

    static func refresh(_ items: [NewsItem], cached: [String: SourcePublication], session: URLSession, now: Date = Date()) async -> [String: SourcePublication] {
        var result = cached.filter { parseDate($0.value.verifiedAt).map { now.timeIntervalSince($0) < 30 * 86400 } ?? false }
        let requested = requestedPosts(items, cached: result, now: now)
        guard !requested.isEmpty else { return result }
        var url = URLComponents(string: "https://aiera.com.cn/wp-json/wp/v2/posts")!
        url.queryItems = [URLQueryItem(name: "include", value: requested.keys.sorted().map(String.init).joined(separator: ",")),
                         URLQueryItem(name: "per_page", value: "100"), URLQueryItem(name: "_fields", value: "id,date,date_gmt,link")]
        do {
            var request = URLRequest(url: url.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (bytes, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200 else { return result }
            result.merge(try parse(bytes, requested: requested, now: now)) { _, verified in verified }
        } catch { /* Keep previously verified source times during an outage. */ }
        return result
    }

    static func apply(_ snapshot: NewsData, cached: [String: SourcePublication]) -> NewsData {
        var result = snapshot
        result.items = snapshot.items.map { item in
            var result = item
            if let known = cached[item.url], known.sourceURL == item.url { result.source_publication = known }
            return result
        }
        return result
    }
}
