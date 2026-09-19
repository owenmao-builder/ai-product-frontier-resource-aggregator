import Foundation

struct NewsPriority: Codable {
    var value: Int
    var modelChange: Int
    var architectureChange: Int
    var heat: Int
    var focus: Int
    var reasons: [String]
    var provisional: Bool
}

enum Priority {
    static let defaultWatchlist = ["DeepSeek", "Claude", "GPT", "Codex", "Qwen", "GLM", "Gemini"]
    static let method = InterestScore.method
    static let aliasGroups = [["DeepSeek", "深度求索"], ["Claude", "Anthropic"], ["GPT", "ChatGPT", "OpenAI", "Astra"], ["Codex"], ["Qwen", "千问", "通义"], ["GLM", "智谱", "Z.ai"], ["Gemini", "DeepMind"]]

    private static let expressions = NSCache<NSString, NSRegularExpression>()

    private static func expression(_ pattern: String) -> NSRegularExpression {
        if let cached = expressions.object(forKey: pattern as NSString) { return cached }
        let regex = try! NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        expressions.setObject(regex, forKey: pattern as NSString)
        return regex
    }

    private static func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static func aliasExpression(_ alias: String, family: Bool = false) -> NSRegularExpression {
        let escaped = NSRegularExpression.escapedPattern(for: alias)
        let boundary = family ? "a-z" : "a-z0-9"
        let pattern = matches(expression(#"[\p{Han}]"#), alias) ? escaped : "(?<![" + boundary + "])" + escaped + "(?![" + boundary + "])"
        return expression(pattern)
    }

    // Build once per refresh. Dates, product aliases and popularity are shared by every article.
    struct Context {
        struct ProductHeat {
            var aliases: [NSRegularExpression]
            var sourceURL: String
            var stars: Int
            var points: Int
        }
        var products: [ProductHeat]
        var pointsByURL: [String: Int]
        var watches: [NSRegularExpression]
        var productAliases: [NSRegularExpression]

        init(products: [AIProduct], pulse: ProductPulse, watchlist: [String] = Priority.defaultWatchlist, now: Date = Date()) {
            productAliases = products.flatMap(\.aliases).filter { !$0.isEmpty }.map { Priority.aliasExpression($0) }
            func fresh(_ value: String?) -> Bool {
                guard let date = parseDate(value) else { return false }
                return (0...86400).contains(now.timeIntervalSince(date))
            }
            let stories = fresh(pulse.hnFetchedAt) ? pulse.discussions.filter {
                guard $0.points >= 100, let date = parseDate($0.publishedAt) else { return false }
                return (0...7 * 86400).contains(now.timeIntervalSince(date))
            } : []
            pointsByURL = Dictionary(stories.map { ($0.url, $0.points) }, uniquingKeysWith: max)
            let stars = fresh(pulse.githubFetchedAt) ? Dictionary(pulse.github.map { ($0.repository.lowercased(), $0.weeklyStars) }, uniquingKeysWith: max) : [:]
            self.products = products.compactMap { product in
                let aliases = product.aliases.filter { !$0.isEmpty }.map { Priority.aliasExpression($0) }
                let points = stories.filter { story in
                    aliases.contains { Priority.matches($0, story.title) } || Products.isAnnouncement(story.url, product: product)
                }.map(\.points).max() ?? 0
                let count = product.repository.flatMap { stars[$0.lowercased()] } ?? 0
                guard points >= 100 || count >= 500 else { return nil }
                return ProductHeat(aliases: aliases, sourceURL: product.sourceURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")), stars: count, points: points)
            }
            watches = watchlist.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.flatMap { watch in
                let aliases = Priority.aliasGroups.first { group in group.contains { $0.caseInsensitiveCompare(watch) == .orderedSame } } ?? [watch]
                return aliases.map { Priority.aliasExpression($0, family: true) }
            }
        }
    }

    static func rank(_ item: NewsItem, rating: NewsRating, products: [AIProduct], pulse: ProductPulse,
                     watchlist: [String] = defaultWatchlist, now: Date = Date()) -> NewsPriority {
        rank(item, rating: rating, context: Context(products: products, pulse: pulse, watchlist: watchlist, now: now))
    }

    static func rank(_ item: NewsItem, rating: NewsRating, context: Context, signals: TechnicalSignals = TechnicalSignals()) -> NewsPriority {
        let text = item.title + " " + item.displayTitle
        func has(_ pattern: String) -> Bool { matches(expression(pattern), text) }
        let excluded = has("传闻|据传|疑似|或将|将于|即将|曝料|爆料|偷跑|rumou?r|coming soon|leaked|sneak.launched|融资|估值|收购|诉讼|卸任|董事|退款|会员.*(转让|出售)|账号.*(交易|出一个)|订阅.*强开")
        let integration = has("接入|搭载|集成|基于|整合|标配|预装|以.{0,40}模型为|integrat|powered by|built on|based on|combining")
        let releaseAction = has(#"发布|上线|推出|升级|更新|新增|新出(?:的)?|首发|重构|开放|开源(?!模型|生态)|\b(introduc(?:e[sd]?|ing)|releas(?:e[sd]?|ing)|launch(?:es|ed|ing)?|unveil(?:s|ed|ing)?|upgrad(?:e[sd]?|ing))\b"#)
        let modelSubject = has(#"新模型|模型|\bmodels?\b|GPT.?[0-9]|Qwen.?[0-9]|GLM.?[0-9]|Gemini.?[0-9]|Claude[ -]*(?:(?:Opus|Sonnet|Haiku)[ -]*)?[0-9]"#)
        let modelPolicy = has("认证|授权|条款|监管|评测|测评|跑分|排行榜|领跑.{0,30}榜|数据集|许可|综述|评估指标|报告|技术细节|语音助手|for Law|应.{0,20}发布|should.{0,30}releas|certification|licensing|terms of|benchmark")
        let modelRelease = (signals.modelRelease || (releaseAction && modelSubject && !modelPolicy && !integration)) && !excluded
        let verified = Scoring.releaseBonus(for: rating) > 0
        var model = verified && rating.release?.kind == "model" ? 30 : modelRelease ? 18 : 0
        var architecture = 0
        if verified && rating.release?.kind == "architecture" { architecture = 30 }
        else if releaseAction && !excluded {
            if has("全新架构|架构重构|新架构|训练范式|原生全模态|原生多模态|mixture.of.experts|MoE|new architecture") || (has("大重构|重构") && has("Claude Code|Codex|agent|智能体|框架|harness")) { architecture = 22 }
            else if has("架构|框架|harness|orchestrat|agent runtime|framework|推理引擎") { architecture = 14 }
            else if has("SDK|插件|工具调用|tool.call|MCP") { architecture = 6 }
        }
        architecture = max(architecture, signals.architecture)
        if excluded && !verified { model = 0; architecture = 0 }
        var reasons: [String] = []
        if model > 0 { reasons.append(verified && rating.release?.kind == "model" ? "官方模型升级" : "模型升级线索") }
        if architecture > 0 { reasons.append(verified && rating.release?.kind == "architecture" ? "已核实架构变更" : architecture >= 22 ? "架构大改线索" : architecture >= 14 ? "框架变更线索" : "接口/工具更新") }

        let focused = context.watches.contains { matches($0, text) }
        let namedProduct = context.productAliases.contains { matches($0, text) }
        let technicalEvent = model > 0 || architecture > 0 || !signals.metrics.isEmpty || (releaseAction && (namedProduct || has("产品|工具|功能|能力|API|推理|多模态|上下文|语音|视频|编程|agent|feature|product|inference")))
        var heat = 0
        if !excluded {
            let articleURL = item.url.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let derivative = has("复刻|衍生|平替|替代品|open.source.version.of|alternative to|clone of|[- ]like model")
            let matchingProducts = context.products.filter { product in
                articleURL == product.sourceURL || (!derivative && product.aliases.contains { matches($0, text) })
            }
            if let count = matchingProducts.map(\.stars).max(), count >= 500 {
                heat = min(25, 10 + Int(log2(Double(count) / 500) * 5))
                reasons.append("GitHub 周增 \(count) 星")
            }
            let relevant = focused || technicalEvent || !matchingProducts.isEmpty || has(#"\b(AI|LLM|agent)\b|人工智能|大模型|机器学习|机器人"#)
            let highest = relevant ? max(context.pointsByURL[item.url] ?? 0, matchingProducts.map(\.points).max() ?? 0) : 0
            if highest >= 100 {
                heat = max(heat, min(25, 10 + Int(log2(Double(highest) / 100) * 5)))
                reasons.append("HN \(highest) 赞")
            }
        }
        let focus = focused && technicalEvent && !excluded ? 15 : 0
        if focus > 0 { reasons.append("关注产品") }
        return NewsPriority(value: model + architecture + heat + focus, modelChange:model,architectureChange:architecture,heat:heat,focus:focus,
            reasons:Array(reasons.prefix(4)),provisional:!verified && (model > 0 || architecture > 0))
    }
}
