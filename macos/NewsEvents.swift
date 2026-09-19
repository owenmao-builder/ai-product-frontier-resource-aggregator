import Foundation
import CryptoKit

struct EventArticle: Codable, Equatable {
    var id: String
    var title: String
    var url: String
    var source: String
    var siteID: String
}

struct EventReport: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var kind: String
    var focus: [String]
    var points: [String]
    var basis: String
    var articles: [EventArticle]
}

struct EventInsight: Codable, Equatable {
    var title: String
    var text: String
}

struct NewsEvent: Codable, Equatable {
    var id: String
    var title: String
    var articleCount: Int
    var mediaCount: Int
    var baseScore: Double?
    var bonus: Double
    var reports: [EventReport]
    var insights: [EventInsight]
    var memberIDs: [String]
    var urls: [String]
    var latestAt: String?
    var read: Bool = false
    var label: String {
        mediaCount >= 2 ? "\(mediaCount) 家媒体关注 · \(articleCount) 篇合并" : "\(articleCount) 篇报道合并"
    }
}

enum NewsEvents {
    static let method = "同一事件合并展示。按原始媒体去重：2 家 +0.3，3 家 +0.5，4 家 +0.7，5 家及以上 +1.0，最高 10 分；同一家多篇、聚合转载、官方通告与社交转发不重复计为媒体。基础分取事件中最高关注分，不叠加文章分数；媒体热度不代表说法已证实。"
    struct Group {
        var id: String
        var subject: String?
        var kind: String
        var members: [NewsItem]
    }
    struct Identity {
        var key: String
        var subject: String?
        var kind: String
    }
    struct Publisher {
        var id: String
        var name: String
        var kind: String
    }
    struct Facet {
        var name: String
        var pattern: String
        var implication: String
    }
    static let facets = [
        Facet(name:"架构与 Agent",pattern:"架构|重构|编排|并行|线程|智能体|agent|harness|orchestrat|parallel|thread|architecture",implication:"关注任务如何拆分、执行与管理，以及相对既有工作流的变化。"),
        Facet(name:"模型与多模态",pattern:"全模态|多模态|音视频|音频|语音|omni|multimodal|audio|video",implication:"关注新增输入输出能力，以及这些能力能否在同一任务中协同。"),
        Facet(name:"性能与上下文",pattern:"上下文|评测|跑分|正确率|准确率|速度|tokens?/s|context|benchmark|accuracy|faster|latency",implication:"关注速度、上下文或评测收益的适用条件；不同指标不能直接相互替代。"),
        Facet(name:"成本与定价",pattern:"成本|降价|价格|费用|[0-9].{0,8}元|cost|pricing|price|cheaper",implication:"关注能力变化是否同时降低实际使用成本，比较时需保持用量与任务口径一致。"),
        Facet(name:"检索与数据",pattern:"检索|索引|知识库|search|retrieval|index|[0-9].{0,4}亿.*URL",implication:"关注数据覆盖、更新与检索链路；应用收益不能全部归因于底层模型升级。"),
        Facet(name:"使用场景",pattern:"法律|律师|案件|胜诉|legal|law\\b|practice|教育|医疗|企业|工作流|workflow",implication:"关注目标用户和真实任务收益，区分使用场景宣传与可衡量的效果。"),
        Facet(name:"开放与接入",pattern:"开源|开放|可用|接入|限量|selected|select firms|trusted access|available|open.source|API|SDK",implication:"关注谁能使用、接入方式和开放范围，避免把有限开放理解为普遍可用。")
    ]

    static func clean(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of:"[‐‑–—_]",with:"-",options:.regularExpression)
            .replacingOccurrences(of:#"\s+"#,with:" ",options:.regularExpression)
            .trimmingCharacters(in:.whitespacesAndNewlines)
    }
    static func compact(_ text: String) -> String {
        clean(text).replacingOccurrences(of:#"[^\p{L}\p{N}.]+"#,with:"",options:.regularExpression)
    }
    static func digest(_ value: String) -> String {
        SHA256.hash(data:Data(value.utf8)).map { String(format:"%02x",$0) }.joined()
    }
    static func canonicalURL(_ raw: String) -> String {
        guard var url = URLComponents(string:raw) else { return raw }
        url.host = url.host?.lowercased().replacingOccurrences(of:"^www\\.",with:"",options:.regularExpression)
        url.fragment = nil
        url.queryItems = url.queryItems?.filter { !$0.name.lowercased().hasPrefix("utm_") && !["fbclid","gclid","ref","source"].contains($0.name.lowercased()) }
        if url.queryItems?.isEmpty == true { url.queryItems = nil }
        return (url.string ?? raw).trimmingCharacters(in:CharacterSet(charactersIn:"/"))
    }

    // Version and action are part of the key: the same brand alone never merges articles.
    static func identity(_ item: NewsItem, products: [AIProduct] = [], document:ArticleDocument? = nil) -> Identity {
        let text = clean(item.title + " " + item.displayTitle)
        func has(_ pattern: String) -> Bool { Scoring.matches(text,pattern) }
        var kind = "release"
        if has("传闻|据传|疑似|即将|或将|rumou?r|leak|coming soon") { kind = "rumor" }
        else if has("宕机|中断|故障|泄露|漏洞|事故|outage|breach|vulnerability|incident") { kind = "incident" }
        else if has("融资|收购|诉讼|估值|funding|acquisition|lawsuit") { kind = "business" }
        else if has("教程|如何使用|入门指南|how to|tutorial|step.by.step") { kind = "tutorial" }
        else if has("复刻|衍生|平替|替代品|open.source.version.of|open.source.alternative|alternative to|clone of") { kind = "derivative" }
        else if has("用.{0,20}玩|语义空间|调用成功|优质案例|Show HN|demo") { kind = "demo" }
        else if has("降价|涨价|调整价格|price cut|price increase|pricing change") && !has("发布|推出|launch|releas|introduc") { kind = "pricing" }
        else if has(#"\bvs\.?\b|对比评测|横向对比|versus"#) { kind = "comparison" }
        var subject: String?
        let context = document?.readable == true ? String(document!.text.prefix(2400)) : ""
        // Explicit features are more specific than models mentioned as their foundations.
        if has(#"(?<![a-z])astra(?![a-z])|阿斯特拉"#) && has("法律|法务|for law") && has("openai|gpt") { subject = "Astra for Law" }
        else if has("claude") && (has(#"\bprojects?\b|项目功能|项目管理"#) ||
            (has("claude code") && has("重构|改版|redesign|relaunch") && Scoring.matches(context,#"\bProjects\b|项目功能"#))) { subject = "Claude Code Projects" }
        else if has("deepseek|深度求索") && has("harness") { subject = "DeepSeek Harness" }
        else {
            let aliases = products.flatMap { product in
                ([product.name] + product.aliases).filter { $0.count >= 3 }.map { (name:$0,canonical:product.name) }
            }
            var candidates: [(name:String,offset:Int,length:Int)] = []
            for alias in aliases {
                let pattern = "(?<![a-z0-9])" + NSRegularExpression.escapedPattern(for:clean(alias.name)).replacingOccurrences(of:"-",with:"[- ]?") + "(?![a-z0-9.-])"
                if let regex = try? NSRegularExpression(pattern:pattern,options:.caseInsensitive),
                   let match = regex.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)) {
                    candidates.append((alias.canonical,match.range.location,match.range.length))
                }
            }
            let pattern = #"(?<![a-z])(?:qwen|glm|gpt|gemini|deepseek|claude(?:[- ](?:opus|sonnet|haiku))?)[- ]?[vr]?\d+(?:\.\d+)*(?:[- ](?:\d+(?:\.\d+)*(?:b|k|m)?|omni|flashx|flash|turbo|plus|pro|lite|thinking|instruct|astra|sonnet|opus|haiku|live|preview|fast|extended|coder|vl|vision|audio|embedding|reranker|distill))*"#
            if let regex = try? NSRegularExpression(pattern:pattern,options:.caseInsensitive),
               let match = regex.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)),
               let range = Range(match.range,in:text) { candidates.append((String(text[range]),match.range.location,match.range.length)) }
            // Prefer the headline's subject over a longer competitor name later in the sentence.
            subject = candidates.sorted {
                if $0.offset != $1.offset { return $0.offset < $1.offset }
                if $0.length != $1.length { return $0.length > $1.length }
                return $0.name < $1.name
            }.first?.name
        }
        if let subject {
            // A short product name is not enough to make SDK support or a named demo
            // another report about its launch. Keep unrelated uses as separate events.
            if kind == "release", let product = products.first(where: { $0.name == subject && $0.name.count <= 4 && $0.technicalHighlights != nil }),
               TechnicalSignals.releaseContext(item,products:[product],now:item.date ?? Date()) == nil {
                kind = "related"
            }
            if kind == "release", has("评测|测评|排行榜|领跑.{0,24}榜|评估|benchmark|evaluation") {
                let name = NSRegularExpression.escapedPattern(for:clean(subject)).replacingOccurrences(of:"-",with:"[- ]?")
                let launch = "(?:发布|上线|推出|introduc(?:es|ing)?|releas(?:es|ed)?|launch(?:es|ed)?)"
                let directRelease = has(launch + "\\s*(?:全新|新一代|模型|了)?\\s*" + name) ||
                    has(name + "\\s*(?:模型)?\\s*" + launch)
                if !directRelease { kind = "evaluation" }
            }
            if kind == "release",
               has("接入|搭载|集成|整合|powered by|built on|combining") { kind = "integration" }
            let suffix = ["release","pricing"].contains(kind) ? "" : "|" + compact(String(item.title.prefix(100)))
            return Identity(key:"subject|" + compact(subject) + "|" + kind + suffix,subject:subject,kind:kind)
        }
        // Exact translated/original headlines across feeds; no fuzzy brand-level merge.
        return Identity(key:"headline|" + compact(item.title),subject:nil,kind:kind)
    }

    static func groups(_ items: [NewsItem], products: [AIProduct] = [], documents:[String:ArticleDocument] = [:], now: Date = Date()) -> [Group] {
        var groups: [Group] = []
        var buckets: [String:[Int]] = [:]
        var urls: [String:Int] = [:]
        for item in items.sorted(by:{ ($0.date ?? .distantPast, $0.id) < ($1.date ?? .distantPast, $1.id) }) {
            let identity = identity(item,products:products,document:documents[item.url])
            let canonical = canonicalURL(item.url)
            let date = item.newsTime(now:now).date
            let index = urls[canonical] ?? buckets[identity.key]?.first { index in
                guard let date, let first = groups[index].members.first?.newsTime(now:now).date else { return false }
                return abs(date.timeIntervalSince(first)) <= 72 * 3600
            }
            if let index {
                if !groups[index].members.contains(where:{ $0.id == item.id }) { groups[index].members.append(item) }
                urls[canonical] = index
            } else {
                let day = date.map { Int(beijingCalendar.startOfDay(for:$0).timeIntervalSince1970) } ?? 0
                let value = Group(id:"event-" + digest(identity.key + "|\(day)").prefix(24),subject:identity.subject,kind:identity.kind,members:[item])
                buckets[identity.key,default:[]].append(groups.count)
                urls[canonical] = groups.count
                groups.append(value)
            }
        }
        return groups
    }

    static func publisher(_ item: NewsItem, products:[AIProduct] = []) -> Publisher {
        let url = URL(string:item.url)
        let host = url?.host?.lowercased().replacingOccurrences(of:"^www\\.",with:"",options:.regularExpression) ?? item.source
        if ["x.com","twitter.com"].contains(host) {
            let handle = url?.pathComponents.dropFirst().first?.lowercased() ?? item.source
            let official = ["openai","anthropicai","claudeai","alibaba_qwen","deepseek_ai","googledeepmind","zai_org"].contains(handle)
            return Publisher(id:"social:" + handle,name:item.source,kind:official ? "official" : "community")
        }
        if ["techmeme.com","news.ycombinator.com","readhub.cn","tophub.today","newsnow.busiyi.world"].contains(host) {
            return Publisher(id:host,name:item.source,kind:"aggregator")
        }
        let known = ["ithome.com":"IT之家","aibase.com":"AIbase","thenextweb.com":"The Next Web","theverge.com":"The Verge","techcrunch.com":"TechCrunch","36kr.com":"36氪","jiqizhixin.com":"机器之心","qbitai.com":"量子位"]
        if let entry = known.first(where:{ host == $0.key || host.hasSuffix("." + $0.key) }) {
            return Publisher(id:entry.key,name:entry.value,kind:"media")
        }
        if let maker = Scoring.majorPublisher(at:item.url) { return Publisher(id:maker,name:maker + " 官方",kind:"official") }
        let sharedHosts = ["github.com","huggingface.co","medium.com","mp.weixin.qq.com"]
        if let product = products.first(where: {
            URL(string:$0.sourceURL)?.host?.lowercased() == host &&
            (!sharedHosts.contains(host) || canonicalURL($0.sourceURL) == canonicalURL(item.url))
        }) {
            return Publisher(id:host,name:product.maker + " 官方",kind:"official")
        }
        if Scoring.matches(item.source,"Hacker News|Techmeme|Readhub|TopHub") {
            return Publisher(id:"aggregator:" + clean(item.source),name:item.source,kind:"aggregator")
        }
        // Distinguish authors on shared hosting without counting social posts as separate media.
        if ["mp.weixin.qq.com","medium.com","zhihu.com","bilibili.com","youtube.com","reddit.com","v2ex.com","juejin.cn","github.com","huggingface.co"].contains(host) {
            return Publisher(id:host + ":" + item.source,name:item.source,kind:"community")
        }
        return Publisher(id:host,name:item.source,kind:"media")
    }
    static func bonus(mediaCount: Int) -> Double {
        switch mediaCount { case 0...1: return 0; case 2: return 0.3; case 3: return 0.5; case 4: return 0.7; default: return 1 }
    }
    static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { !$0.isEmpty && seen.insert(compact($0)).inserted }
    }
    static func focus(_ text: String) -> [String] {
        facets.filter { Scoring.matches(text,$0.pattern) }.map(\.name)
    }
    // Extract only complete, topic-bearing sentences. Never present a title as a body analysis.
    static func excerpts(_ document: ArticleDocument, item: NewsItem) -> [String] {
        guard document.readable else { return [] }
        let identity = identity(item,document:document)
        let subjectTokens = identity.subject.map { compact($0) }
        let keywords = Set(clean(item.title).components(separatedBy:CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && !["the","for","and","with","new","model","openai","launches","introducing"].contains($0) })
        let sentences = document.text.replacingOccurrences(of:#"(?<=[.!?])\s+(?=[A-Z])"#,with:"\n",options:.regularExpression)
            .components(separatedBy:CharacterSet(charactersIn:"。！？\n"))
            .map { $0.trimmingCharacters(in:.whitespacesAndNewlines) }
        var contextUntil = -1
        var candidates: [(index:Int,text:String,weight:Int)] = []
        for (index,sentence) in sentences.enumerated() {
            guard (20...350).contains(sentence.count),
                  !Scoring.matches(sentence,"免责声明|相关阅读|猜你喜欢|广告|cookie|subscribe|copyright|点击关注|扫码|首页|RSS订阅|责编|线索投递|登录.{0,3}注册|sign in|来源[：:]|发自") else { continue }
            let namesSubject = subjectTokens.map { compact(sentence).contains($0) } ?? (keywords.filter { clean(sentence).contains($0) }.count >= 2 || compact(sentence).contains(compact(String(item.title.prefix(12)))))
            if namesSubject { contextUntil = index + 2 }
            let facets = focus(sentence)
            guard !facets.isEmpty, namesSubject || index <= contextUntil else { continue }
            let change = Scoring.matches(sentence,"新增|重构|原生|独立|共享|协调器|覆盖|introduc|native|parallel|memory") ? 4 : 0
            candidates.append((index,sentence,facets.count * 2 + change))
        }
        let selected = candidates.sorted { $0.weight == $1.weight ? $0.index < $1.index : $0.weight > $1.weight }.prefix(2).sorted { $0.index < $1.index }
        return unique(selected.map(\.text))
    }

    static func present(_ group: Group, ratings: [String:NewsRating], documents: [String:ArticleDocument] = [:],
                        translations: [String:String] = [:], products:[AIProduct] = [], now: Date = Date()) -> NewsItem {
        let ranked = group.members.sorted { a,b in
            let ra = ratings[a.id]?.sortScore ?? -1, rb = ratings[b.id]?.sortScore ?? -1
            if ra != rb { return ra > rb }
            let zhA = Scoring.matches(translations[a.title] ?? a.displayTitle,#"[\p{Han}]"#)
            let zhB = Scoring.matches(translations[b.title] ?? b.displayTitle,#"[\p{Han}]"#)
            if zhA != zhB { return zhA }
            return a.id < b.id
        }
        var lead = ranked[0]
        var rating = ratings[lead.id] ?? Scoring.rule(lead)
        let byPublisher = Dictionary(grouping:group.members,by:{ publisher($0,products:products).id })
        let reports = byPublisher.values.map { members -> EventReport in
            let ordered = members.sorted { $0.id < $1.id }
            let publisher = publisher(ordered[0],products:products)
            var points: [String] = []
            var bases = Set<String>()
            for member in ordered {
                if let saved = ratings[member.id], !["headline","official-context"].contains(saved.briefBasis ?? ""), saved.hasChineseBrief {
                    points += saved.highlights ?? []; bases.insert("已有正文分析")
                } else if let document = documents[member.url], !excerpts(document,item:member).isEmpty {
                    points += excerpts(document,item:member).map { translations[$0] ?? $0 }; bases.insert("正文摘录")
                } else {
                    let headline = translations[member.title] ?? ratings[member.id]?.chineseTitle ?? member.displayTitle
                    points.append(translations[headline] ?? headline)
                    bases.insert("标题")
                }
            }
            let material = ordered.map { $0.title + " " + $0.displayTitle }.joined(separator:" ") + " " + points.joined(separator:" ")
            return EventReport(id:publisher.id,name:publisher.name,kind:publisher.kind,
                focus:focus(material),points:Array(unique(points).prefix(3)),basis:bases.sorted().joined(separator:" / "),
                articles:ordered.map { EventArticle(id:$0.id,title:translations[$0.title] ?? ratings[$0.id]?.chineseTitle ?? $0.displayTitle,url:$0.url,source:$0.source,siteID:$0.site_id) })
        }.sorted { a,b in
            let order = ["media":0,"official":1,"community":2,"aggregator":3]
            return (order[a.kind] ?? 4,a.name) < (order[b.kind] ?? 4,b.name)
        }
        let count = reports.filter { $0.kind == "media" }.count
        let base = rating.isScored ? rating.score : nil
        let today = group.members.contains { item in item.newsTime(now:now).date.map { beijingCalendar.isDate($0,inSameDayAs:now) } ?? false }
        let boost = today && rating.isInterest ? bonus(mediaCount:count) : 0
        if let base { rating.score = (min(10,base + boost) * 10).rounded() / 10 }
        if boost > 0 { rating.reason += " 本事件 \(count) 家不同媒体报道，关注加分 +\(String(format:"%.1f",boost))（10 分封顶）。" }
        let title = rating.chineseTitle ?? translations[lead.title] ?? lead.displayTitle
        var insights: [EventInsight] = []
        var quotedPoints = Set<String>()
        let orderedFacets = facets.enumerated().sorted { a,b in
            let ca = reports.filter { $0.focus.contains(a.element.name) }.count
            let cb = reports.filter { $0.focus.contains(b.element.name) }.count
            return ca == cb ? a.offset < b.offset : ca > cb
        }.map(\.element)
        for facet in orderedFacets {
            let sources = reports.filter { $0.focus.contains(facet.name) }
            guard !sources.isEmpty else { continue }
            let sample: (String,String)? = sources.flatMap { report in report.points.filter {
                Scoring.matches($0,facet.pattern) && !quotedPoints.contains(compact($0))
            }.map { (report.name,$0) } }.first
            let attribution: String
            if let sample {
                quotedPoints.insert(compact(sample.1))
                let excerpt = String(sample.1.prefix(135))
                let ellipsis = sample.1.count > 135 ? "…" : ""
                attribution = "\(sample.0) 提到「\(excerpt)\(ellipsis)」。"
            } else {
                attribution = sources.prefix(3).map(\.name).joined(separator:"、") + " 关注这一面向。"
            }
            insights.append(EventInsight(title:facet.name,text:attribution + "解读：" + facet.implication))
        }
        if insights.isEmpty { insights = [EventInsight(title:"事件进展",text:"各家围绕同一项产品或技术进展报道；具体侧重点见下方摘录。")] }
        let event = NewsEvent(id:group.id,title:title,articleCount:Set(group.members.map { canonicalURL($0.url) }).count,
            mediaCount:count,baseScore:base,bonus:boost,reports:reports,insights:Array(insights.prefix(3)),
            memberIDs:group.members.map(\.id),urls:group.members.map(\.url),
            latestAt:group.members.compactMap { $0.newsTime(now:now).date }.max().map { timestamp($0) })
        lead.event = event; lead.rating = rating
        return lead
    }

    static func isRead(_ event: NewsEvent, seenURLs: Set<String>, seenEvents: Set<String>) -> Bool {
        seenEvents.contains(event.id) || event.urls.contains { seenURLs.contains($0) }
    }
}
