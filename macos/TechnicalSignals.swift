import Foundation

// Reading priority uses attributed claims, not an assertion that benchmarks are verified.
struct TechnicalSignals {
    private static let expressions = NSCache<NSString,NSRegularExpression>()
    struct Metric {
        var key: String
        var factor: Double
        var claim: String
        var origin: String
        var value: Double { factor >= 20 ? 5 : factor >= 10 ? 4.5 : factor >= 5 ? 4 : factor >= 2 ? 3 : 2 }
        var reason: String { "\(origin)：\(claim)。按宣称的变化幅度计分，区间取较小倍数；适用任务及对照以来源说明为准。" }
    }
    var modelRelease = false
    var architecture = 0
    var metrics: [Metric] = []
    var sources: [RatingSource] = []
    var highlights: [String] = []
    var basis = "headline"
    var tags: [String] {
        (metrics.contains { $0.key == "speed_gain" } ? ["推理加速"] : []) +
        (metrics.contains { $0.key == "cost_gain" } ? ["成本下降"] : []) +
        (architecture >= 22 ? ["架构创新"] : [])
    }

    static func names(_ alias: String, in text: String) -> Bool {
        let name = NSRegularExpression.escapedPattern(for: alias)
        return Scoring.matches(text, "(?<![a-z0-9])" + name + "(?![a-z0-9-])")
    }
    static func shouldRead(_ item: NewsItem) -> Bool {
        Scoring.matches(item.title + " " + item.displayTitle,
            #"模型|架构|框架|范式|推理|成本|延迟|吞吐|加速|\b(model|inference|latency|throughput|architecture|framework|paradigm)\b"#)
    }
    static func releaseContext(_ item: NewsItem, products: [AIProduct], now: Date) -> AIProduct? {
        let text = item.title + " " + item.displayTitle
        // A model's launch gains do not belong to a clone, tutorial or a different product integrating it.
        guard !Scoring.matches(text, #"传闻|疑似|或将|即将|复刻|衍生|平替|替代品|接入|集成|搭载|调用|教程|语义空间|可在.{0,30}使用|用.{0,20}(玩|构建)|\bvs\.?\b|rumou?r|clone|alternative|[- ]like\b|using|integrat|available in|AI SDK|Question Classifier|how to|Show HN|价格调整|降价|宕机|融资"#),
              shouldRead(item) || Scoring.matches(text,"发布|首发|介绍|上线|推出|introduc|releas|launch|debuts") else { return nil }
        return products.filter { product in
            product.technicalHighlights?.isEmpty == false && Products.isRecentRelease(product,now:now) &&
            ([product.name] + product.aliases).contains { names($0,in:text) }
        }.sorted { $0.name.count > $1.name.count }.first
    }

    static func analyze(_ item: NewsItem, document: ArticleDocument? = nil, products: [AIProduct] = [], now: Date = Date()) -> TechnicalSignals {
        let headline = item.title + " " + item.displayTitle
        guard !Scoring.matches(headline,"传闻|据传|疑似|或将|即将|rumou?r|coming soon|融资|估值|收购|账号.*交易") else { return TechnicalSignals() }
        var result = TechnicalSignals()
        var materials: [(text:String,origin:String,url:String)] = [(headline,"标题宣称",item.url)]
        if let doc = document, doc.readable, shouldRead(item) {
            // Do not absorb a site's recommended articles or comment section into the article's claims.
            var body = String(doc.text.prefix(9000))
            if let stop = body.range(of:"相关阅读|相关推荐|猜你喜欢|Related articles|You may also like|\\d+ 条回复",options:.regularExpression) {
                body = String(body[..<stop.lowerBound])
            }
            materials.append((body,"原文宣称",doc.url))
        }
        if let product = releaseContext(item,products:products,now:now) {
            let points = Array((product.technicalHighlights ?? []).prefix(4))
            materials.append((points.joined(separator:"。"),product.maker + " 官网宣称",product.sourceURL))
            result.modelRelease = product.releaseKind == "新模型" || product.releaseKind == "模型升级"
            result.highlights = points
            result.basis = "official-context"
            result.sources = [RatingSource(url:product.sourceURL,title:product.maker + " 官方发布说明",quote:"")]
        }
        guard shouldRead(item) || result.modelRelease else { return result }
        for material in materials {
            let text = material.text
            let architectureClaim = text.components(separatedBy:CharacterSet(charactersIn:"。！？.!?\n")).contains {
                Scoring.matches($0,"全新架构|新架构|新模型架构|架构重构|新训练(?:方法|算法|范式)|new (?:model )?architecture|new training (?:method|algorithm)|Reinforcement Learning for Calibrated Decisions|RLCD") &&
                !Scoring.matches($0,"并非|不是|没有|并未|not.{0,24}(?:new|architecture)|no new")
            }
            if architectureClaim &&
                !Scoring.matches(headline,"接入|集成|搭载|教程|Show HN|using|integrat") {
                result.architecture = 22
            }
            for metric in extractMetrics(text,origin:material.origin) {
                if let index = result.metrics.firstIndex(where: { $0.key == metric.key }) {
                    if metric.factor > result.metrics[index].factor { result.metrics[index] = metric }
                } else { result.metrics.append(metric) }
                if !result.sources.contains(where: { $0.url == material.url }) {
                    result.sources.append(RatingSource(url:material.url,title:material.origin,quote:""))
                }
            }
        }
        result.metrics.sort { $0.key > $1.key }
        if result.highlights.isEmpty && !result.metrics.isEmpty {
            result.highlights = result.metrics.map { metric in
                let factor = String(format:"%g",metric.factor)
                return metric.key == "speed_gain" ? "\(metric.origin)：速度提升约 \(factor) 倍；若为区间，按较小倍数估分。" : "\(metric.origin)：成本约为对照的 1/\(factor)；若为区间，按较小降本倍数估分。"
            }
            result.highlights.append("关注点：这种效率变化可能影响高频调用和自动化工作流；具体任务、对照条件与限制见来源。")
            result.basis = materials.count > 1 ? "body-claims" : "headline"
        }
        return result
    }

    static func extractMetrics(_ text: String, origin: String) -> [Metric] {
        guard Scoring.matches(text,#"\d"#), Scoring.matches(text,#"倍|[%×/／]|\b(?:faster|cheaper|speedup|cost|times)\b"#) else { return [] }
        // Every pattern captures the conservative lower endpoint as group 1.
        let number = #"(\d+(?:\.\d+)?)"#
        let range = #"\s*(?:[x×倍]?\s*[-–—~～至到]\s*\d+(?:\.\d+)?)?\s*"#
        let multiple = number + range
        let patterns: [(String,String,String)] = [
            ("speed_gain",multiple + #"(?:x|×|times)\s*(?:faster|speedup|quicker)"#,"factor"),
            ("speed_gain",#"(?:速度|推理速度|吞吐量|性能)\s*(?:提升|提高|加快|快|增加)(?:了|可达|达|约|至)?\s*"# + multiple + "倍","factor"),
            ("speed_gain",#"(?:加速|快)\s*(?:了|约|达)?\s*"# + multiple + "倍","factor"),
            ("cost_gain",multiple + #"(?:x|×|times)\s*(?:cheaper|less expensive|lower cost)"#,"factor"),
            ("cost_gain",#"(?:成本|费用|价格)\s*(?:降低|下降|减少|低)(?:了|约|达)?\s*"# + multiple + "倍","factor"),
            ("cost_gain",#"(?:成本|费用|价格)[^。！？.!?\n]{0,28}?(?:降至|降为|降到|仅为|为)[^。！？.!?\n]{0,16}?1\s*[/／]\s*"# + number,"factor"),
            ("speed_gain",#"(?:速度|吞吐量)\s*(?:提升|提高|增加)\s*"# + number + "%","increase"),
            ("cost_gain",#"(?:成本|费用)\s*(?:降低|下降|减少)\s*"# + number + "%","reduction"),
            ("cost_gain",#"(?:cost|costs)\s*(?:reduced|reduction|lowered|decreased)\s*(?:by|of)?\s*"# + number + "%","reduction")
        ]
        var results: [Metric] = []
        for (key,pattern,mode) in patterns {
            let regex: NSRegularExpression
            if let cached = expressions.object(forKey:pattern as NSString) { regex = cached }
            else {
                guard let compiled = try? NSRegularExpression(pattern:pattern,options:.caseInsensitive) else { continue }
                expressions.setObject(compiled,forKey:pattern as NSString); regex = compiled
            }
            for match in regex.matches(in:text,range:NSRange(text.startIndex...,in:text)) {
                guard let captured = Range(match.range(at:1),in:text), let raw = Double(text[captured]),
                      let matchRange = Range(match.range,in:text) else { continue }
                let before = String(text[..<matchRange.lowerBound].suffix(32))
                    .components(separatedBy:CharacterSet(charactersIn:"。！？.!?\n；;")).last ?? ""
                if Scoring.matches(before,#"并未|没有|未能|不是|无法|不可能|并非|谣言|\b(?:not|never|isn't|doesn't|cannot)\b"#) { continue }
                let factor: Double
                if mode == "increase" { factor = 1 + raw / 100 }
                else if mode == "reduction" { guard raw > 0 && raw < 100 else { continue }; factor = 1 / (1 - raw / 100) }
                else { factor = raw }
                guard factor.isFinite && factor > 1 && factor <= 1_000_000_000 else { continue }
                results.append(Metric(key:key,factor:factor,claim:String(text[matchRange]),origin:origin))
            }
        }
        return results
    }
}
