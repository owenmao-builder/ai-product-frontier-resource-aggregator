import Foundation

func publicArticleURL(_ text: String) -> URL? {
    guard let url = URL(string: text), url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
          let host = url.host?.lowercased(), !host.isEmpty, host.contains("."), !host.hasSuffix(".local"), !host.hasSuffix(".localhost"),
          !host.contains(":"), !["localhost", "metadata.google.internal"].contains(host) else { return nil }
    let numbers = host.split(separator: ".").compactMap { Int($0) }
    if numbers.count == 4 {
        let a = numbers[0], b = numbers[1]
        if a == 0 || a == 10 || a == 127 || a >= 224 || (a == 169 && b == 254) || (a == 172 && (16...31).contains(b)) || (a == 192 && b == 168) { return nil }
    }
    return url
}

final class PublicArticleRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.flatMap { publicArticleURL($0.absoluteString) } == nil ? nil : request)
    }
}

struct ArticleDocument: Codable {
    var url: String
    var title: String
    var text: String
    var fetchedAt: String
    var error: String?
    var truncated: Bool
    var readable: Bool { error == nil && text.count >= 400 }

    static func extract(_ html: String) -> String {
        var value = html
        // A quoted attribute can contain '>'; stop only at a real tag boundary.
        let attributes = #"(?:"[^"]*"|'[^']*'|[^'">])*"#
        for name in ["script", "style", "nav", "header", "footer", "aside", "noscript", "svg"] {
            value = value.replacingOccurrences(of: "(?is)<" + name + "\\b" + attributes + ">.*?</" + name + ">", with: " ", options: .regularExpression)
        }
        for name in ["article", "main", "body"] {
            if let expression = try? NSRegularExpression(pattern: "(?is)<" + name + "\\b" + attributes + ">(.*?)</" + name + ">"),
               let match = expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
               let range = Range(match.range(at: 1), in: value) { value = String(value[range]); break }
        }
        value = value.replacingOccurrences(of: "(?s)<!--.*?-->", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "<" + attributes + ">", with: " ", options: .regularExpression)
        for (code, text) in [("&nbsp;", " "), ("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&mdash;", "—"), ("&ndash;", "–")] { value = value.replacingOccurrences(of: code, with: text) }
        if let re = try? NSRegularExpression(pattern: "&#(x[0-9a-fA-F]+|[0-9]+);") {
            for match in re.matches(in: value, range: NSRange(value.startIndex..., in: value)).reversed() {
                guard let part = Range(match.range(at: 1), in: value), let full = Range(match.range, in: value) else { continue }
                let raw = String(value[part]); let n = raw.hasPrefix("x") ? UInt32(raw.dropFirst(), radix: 16) : UInt32(raw)
                if let n, let scalar = UnicodeScalar(n) { value.replaceSubrange(full, with: String(scalar)) }
            }
        }
        return value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func fetch(url raw: String, title: String) async -> ArticleDocument {
        var result = ArticleDocument(url: raw, title: title, text: "", fetchedAt: timestamp(), error: nil, truncated: false)
        guard let url = publicArticleURL(raw) else { result.error = "原文地址不支持自动读取"; return result }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12; config.timeoutIntervalForResource = 18
        config.httpCookieAcceptPolicy = .never; config.httpShouldSetCookies = false
        let session = URLSession(configuration: config, delegate: PublicArticleRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            var request = URLRequest(url: url)
            request.setValue("AI-News-Menu/2.0 (public article reader)", forHTTPHeaderField: "User-Agent")
            request.setValue("text/html,application/xhtml+xml,text/plain", forHTTPHeaderField: "Accept")
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), data.count <= 4_000_000,
                  let mime = http.mimeType, ["text/html", "application/xhtml+xml", "text/plain"].contains(mime), let text = String(data: data, encoding: .utf8) else {
                result.error = "未取得可读正文（HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)）"; return result
            }
            let clean = mime == "text/plain" ? text : extract(text)
            result.truncated = clean.count > 18000
            result.text = String(clean.prefix(18000))
            if clean.count < 400 || Scoring.matches(String(clean.prefix(600)), "Just a moment|Checking your browser|Access Denied|Enable JavaScript and cookies to continue") { result.error = "页面缺少足够正文，可能需要浏览器加载"; result.text = "" }
        } catch { result.error = "正文暂不可读：\(error.localizedDescription)" }
        return result
    }
}
