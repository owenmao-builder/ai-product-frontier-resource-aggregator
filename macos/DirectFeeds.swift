import Foundation
import CryptoKit

struct DirectFeed: Codable {
    var id: String
    var name: String
    var feedURL: String
    var homeURL: String
    var description: String

    static var configured: [DirectFeed] {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("direct-feeds.json"),
              let data = try? Data(contentsOf: url),
              let feeds = try? JSONDecoder().decode([DirectFeed].self, from: data) else { return [] }
        return feeds
    }
}

struct DirectFeedCache: Codable {
    var items: [NewsItem] = []
    var checkedAt: String?
    var fetchedAt: String?
    var error: String?
}

struct DirectFeedStatus: Codable {
    var id: String
    var checkedAt: String?
    var fetchedAt: String?
    var error: String?
    var windowCount: Int
    var latestTitle: String?
    var latestURL: String?
    var latestPublishedAt: String?
}

enum DirectFeeds {
    static func refresh(_ feeds: [DirectFeed], cached: [String: DirectFeedCache], session: URLSession) async -> [String: DirectFeedCache] {
        await withTaskGroup(of: (String, DirectFeedCache).self) { group in
            for feed in feeds {
                group.addTask { (feed.id, await fetch(feed, cached: cached[feed.id] ?? DirectFeedCache(), session: session)) }
            }
            var result = cached
            for await (id, entry) in group { result[id] = entry }
            return result
        }
    }

    private static func fetch(_ feed: DirectFeed, cached: DirectFeedCache, session: URLSession) async -> DirectFeedCache {
        var entry = cached
        entry.checkedAt = timestamp()
        do {
            guard let url = publicArticleURL(feed.feedURL) else { throw NewsError.message("订阅地址无效") }
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 20)
            request.setValue("application/rss+xml, application/xml, text/xml", forHTTPHeaderField: "Accept")
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            let (bytes, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw NewsError.message("订阅源暂不可用") }
            let now = Date()
            entry.items = retain(try parse(bytes, feed: feed, now: now), previous: entry.items, now: now)
            entry.fetchedAt = timestamp(now)
            entry.error = nil
        } catch { entry.error = error.localizedDescription }
        return entry
    }

    static func retain(_ incoming: [NewsItem], previous: [NewsItem], now: Date) -> [NewsItem] {
        let cutoff = now.addingTimeInterval(-7 * 86400)
        var byURL = Dictionary(previous.filter { parseDate($0.published_at).map { $0 >= cutoff && $0 <= now } ?? false }.map { ($0.url, $0) }, uniquingKeysWith: { first, _ in first })
        let firstSeen = Dictionary(previous.map { ($0.url, $0.first_seen_at) }, uniquingKeysWith: { first, _ in first })
        for var item in incoming {
            item.first_seen_at = firstSeen[item.url] ?? item.first_seen_at
            byURL[item.url] = item
        }
        // Preserve recent posts when a short RSS feed rotates, plus the latest old post for source status.
        let sorted = byURL.values.sorted { ($0.published_at ?? "") > ($1.published_at ?? "") }
        return Array(sorted.filter { $0.id == sorted.first?.id || (parseDate($0.published_at).map { $0 >= cutoff } ?? false) }.prefix(500))
    }

    static func parse(_ bytes: Data, feed: DirectFeed, now: Date) throws -> [NewsItem] {
        guard bytes.count <= 8_000_000 else { throw NewsError.message("订阅内容过大") }
        let reader = RSSReader()
        // Some WordPress feeds truncate a multibyte character in an unused excerpt.
        // Repair declared UTF-8 so valid article fields survive; reject damaged fields below.
        let header = String(decoding: bytes.prefix(256), as: UTF8.self).lowercased()
        let isUTF8 = header.range(of: #"encoding\s*=\s*['"]utf-8['"]"#, options: .regularExpression) != nil
        let xml = isUTF8 ? Data(String(decoding: bytes, as: UTF8.self).utf8) : bytes
        let parser = XMLParser(data: xml)
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        guard parser.parse(), reader.isRSS else { throw NewsError.message("无法解析 RSS 订阅") }
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        var urls = Set<String>()
        return reader.entries.compactMap { fields -> NewsItem? in
            let title = (fields["title"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let link = (fields["link"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let rawDate = (fields["pubDate"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, !title.contains("\u{FFFD}"), !link.contains("\u{FFFD}"), let url = publicArticleURL(link),
                  let published = dateFormatter.date(from: rawDate) ?? parseDate(rawDate), published <= now else { return nil }
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            components.fragment = nil
            let tracking = Set(["ref", "spm", "fbclid", "gclid", "igshid", "mkt_tok", "mc_cid", "mc_eid", "_hsenc", "_hsmi"])
            components.queryItems = components.queryItems?.filter { !tracking.contains($0.name.lowercased()) && !$0.name.lowercased().hasPrefix("utm_") }
            if components.queryItems?.isEmpty == true { components.queryItems = nil }
            // Xinzhiyuan's RSS uses WordPress permalinks; its site and aggregate feed use these article URLs.
            if feed.id == "xinzhiyuan", components.host == "aiera.com.cn" {
                let parts = components.path.split(separator: "/")
                if parts.count == 7, parts[0].count == 4, parts.prefix(3).allSatisfy({ $0.allSatisfy(\.isNumber) }),
                   let postID = Int(parts[5]), postID > 0 {
                    components.path = "/asi-post.html"
                    components.queryItems = [URLQueryItem(name: "id", value: String(postID))]
                }
            }
            guard var canonical = components.url?.absoluteString else { return nil }
            if canonical.hasSuffix("/"), components.path != "/" { canonical.removeLast() }
            guard urls.insert(canonical).inserted else { return nil }
            let hash = SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
            return NewsItem(id: "directrss-" + hash, site_id: "directrss", site_name: "原站直采", source: feed.name,
                title: title, url: canonical, published_at: timestamp(published), first_seen_at: timestamp(now), last_seen_at: timestamp(now))
        }.sorted { ($0.published_at ?? "") > ($1.published_at ?? "") }
    }

    static func merge(_ snapshot: NewsData, feeds: [DirectFeed], cached: [String: DirectFeedCache], now: Date = Date()) -> NewsData {
        var result = snapshot
        let cutoff = now.addingTimeInterval(-Double(snapshot.window_hours) * 3600)
        func inWindow(_ item: NewsItem) -> Bool {
            guard let published = parseDate(item.published_at) else { return false }
            return published >= cutoff && published <= now
        }
        // Always rebuild this slice: old posts must age out even when the feed fails.
        result.items.removeAll { $0.site_id == "directrss" }
        var urls = Set(result.items.map(\.url))
        var ids = Set(result.items.map(\.id))
        var indices = Dictionary(result.items.enumerated().map { ($0.element.url, $0.offset) }, uniquingKeysWith: { first, _ in first })
        for feed in feeds {
            for item in cached[feed.id]?.items ?? [] where inWindow(item) && item.safeURL != nil {
                if let index = indices[item.url], let published = item.published_at, let fetched = cached[feed.id]?.fetchedAt {
                    // Use the original feed's publication date while preserving IDs, scores and reading state.
                    result.items[index].source_publication = SourcePublication(publishedAt: published, verifiedAt: fetched, sourceURL: item.url)
                } else if urls.insert(item.url).inserted && ids.insert(item.id).inserted {
                    indices[item.url] = result.items.count
                    result.items.append(item)
                }
            }
        }
        result.items = result.items.filter { $0.newsTime(now: now).date.map { $0 >= cutoff && $0 <= now } ?? false }
        let oldRawCount = result.site_stats.first { $0.site_id == "directrss" }?.raw_count ?? 0
        result.site_stats.removeAll { $0.site_id == "directrss" }
        let addedCount = result.items.filter { $0.site_id == "directrss" }.count
        if !feeds.isEmpty { result.site_stats.append(SiteStat(site_id: "directrss", site_name: "原站直采", count: addedCount, raw_count: addedCount)) }
        let counts = Dictionary(grouping: result.items, by: \.site_id).mapValues(\.count)
        result.site_stats = result.site_stats.map { stat in var stat = stat; stat.count = counts[stat.site_id] ?? 0; return stat }
        result.total_items = result.items.count
        if let total = result.total_items_raw { result.total_items_raw = total - oldRawCount + addedCount }
        result.site_count = result.site_stats.count
        result.source_count = Set(result.items.map(\.source)).union(feeds.map(\.name)).count
        result.direct_sources = feeds.map { feed in
            let entry = cached[feed.id] ?? DirectFeedCache()
            let latest = entry.items.max { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
            return DirectFeedStatus(id: feed.id, checkedAt: entry.checkedAt, fetchedAt: entry.fetchedAt, error: entry.error,
                windowCount: entry.items.filter(inWindow).count, latestTitle: latest?.title, latestURL: latest?.url, latestPublishedAt: latest?.published_at)
        }
        return result
    }
}

private final class RSSReader: NSObject, XMLParserDelegate {
    var entries: [[String: String]] = []
    var isRSS = false
    private var path: [String] = []
    private var fields: [String: String] = [:]
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
        path.append(elementName)
        if path == ["rss", "channel"] { isRSS = true }
        if path == ["rss", "channel", "item"] { fields = [:] }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard path.count == 4, path[2] == "item", let key = path.last, ["title", "link", "pubDate"].contains(key) else { return }
        fields[key, default: ""] += string
    }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let text = String(data: CDATABlock, encoding: .utf8) { self.parser(parser, foundCharacters: text) }
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if path == ["rss", "channel", "item"] { entries.append(fields) }
        path.removeLast()
    }
}
