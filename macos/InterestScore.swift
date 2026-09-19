import Foundation

enum InterestScore {
    static let version = "interest-v2"
    static let method = "优先看事件的集中报道：48 小时内，2/3/5/8/12 个独立来源分别至少 7/8/8.5/9/9.5 分，无需技术细节齐全。最终分取该最低分与内容关注分的较高值。内容按模型升级、架构各 30，速度、成本、产品热度各 25，关注匹配 15，只计算适用维度。媒体、资讯作者及社区分别展示，同源转载不重复计数；证据状态单独显示。"
    static let names = ["model_change":"模型升级", "architecture_change":"架构变化", "product_change":"产品/技术进展", "speed_gain":"速度提升", "cost_gain":"成本下降", "heat":"产品热度", "focus":"关注匹配"]

    static func rating(_ item: NewsItem, priority: NewsPriority, previous: NewsRating, signals: TechnicalSignals = TechnicalSignals(), translatedTitle: String? = nil, now: Date = Date()) -> NewsRating {
        let text = item.title + " " + item.displayTitle
        func has(_ pattern: String) -> Bool { Scoring.matches(text, pattern) }
        let excluded = has("传闻|据传|疑似|或将|即将|偷跑|rumou?r|coming soon|sneak.launched|融资|估值|收购|会员.*(转让|出售)|账号.*交易|订阅.*强开")
        let integration = has("接入|搭载|集成|基于|整合|标配|语音助手|powered by|based on|combining")
        let event = has("发布|上线|推出|升级|更新|新增|重构|开放|开源|introduc|releas|launch|unveil|upgrad|available")
        var dimensions: [RatingDimension] = []
        func add(_ key: String, _ value: Double, _ weight: Double, _ reason: String) {
            dimensions.append(RatingDimension(key:key,value:value,reason:reason,weight:weight))
        }
        if priority.modelChange > 0 && !excluded {
            let magnitude = (signals.modelRelease || has("新一代|全新模型|原生全模态|原生多模态|next.generation")) ? 4.5 : 4.0
            add("model_change", magnitude, 30, "报道涉及具体模型发布或版本升级；按当前信息判断变化幅度。")
        }
        if priority.architectureChange > 0 && !excluded {
            let magnitude = priority.architectureChange >= 22 ? 4.5 : priority.architectureChange >= 14 ? 3.5 : 2.0
            add("architecture_change", magnitude, 30, magnitude >= 4.5 ? "报道涉及架构重构、原生能力或 Agent 执行结构变化。" : magnitude >= 3.5 ? "报道涉及框架、运行时或编排方式更新。" : "主要是接口、插件或工具调用层的更新。")
        }
        if dimensions.isEmpty {
            let category = NewsCategory(rawValue:previous.category ?? "other") ?? .other
            let magnitude: Double = excluded ? 1 : !signals.metrics.isEmpty ? 4 : event && [.product,.developer,.model].contains(category) ? (integration ? 2.5 : 4) : [.research,.analysis,.safety,.policy].contains(category) ? 2.5 : 1.5
            add("product_change", magnitude, 30, excluded ? "非正式发布或非产品技术事件，关注优先级较低。" : integration ? "属于现有能力接入或集成，不当作底层模型升级。" : "按这条消息提供的产品、技术或使用场景进展估分。")
        }
        if !excluded {
            for metric in signals.metrics {
                add(metric.key, metric.value, 25, metric.reason)
            }
        }
        let knownHeat = priority.heat > 0
        add("heat", knownHeat ? Double(priority.heat) / 5 : excluded ? 0 : 2.5, 25,
            knownHeat ? priority.reasons.filter { $0.contains("HN") || $0.contains("GitHub") }.joined(separator:"；") : excluded ? "没有符合本条产品技术主题的热度加分。" : "缺少可用热度统计，暂取 2.5/5 中性估值；不代表实际热度。")
        let technicalMatch = !excluded && (priority.modelChange > 0 || priority.architectureChange > 0 || !signals.metrics.isEmpty)
        add("focus", priority.focus > 0 ? 5 : technicalMatch ? 3 : 0, 15,
            priority.focus > 0 ? "命中你的关注产品，并有技术或产品事件。" : technicalMatch ? "符合你关注的模型、架构或效率变化；新名字不因未进入品牌名单而归零（3/5）。" : "未命中关注产品或技术变化；普通品牌提及不加分。")
        let weight = dimensions.reduce(0) { $0 + ($1.weight ?? 0) }
        let total = dimensions.reduce(0) { $0 + $1.value * ($1.weight ?? 0) } / weight * 2
        var result = previous
        result.score = (min(10,max(0,total)) * 10).rounded() / 10
        result.method = "interest-rule"; result.version = version; result.assessedAt = timestamp(now)
        result.model = "本机关注规则 · 无需 API Key"
        result.dimensions = dimensions; result.release = nil
        result.reason = "按模型、架构、速度、成本与热度等适用维度计算阅读优先级；不要求每条消息同时满足所有维度。效率提升按来源宣称估分，证据等级不限制分数。"
        result.tags = Array(NewsEvents.unique(signals.tags + (priority.architectureChange >= 22 ? ["架构创新"] : []) + previous.tags).prefix(5))
        if signals.modelRelease { result.category = "model" }
        if previous.sources?.isEmpty != false { result.sources = [RatingSource(url:item.url,title:item.source,quote:"")] }
        for source in signals.sources {
            if let index = result.sources?.firstIndex(where: { $0.url == source.url }) {
                if source.title.contains("官方发布说明") { result.sources?[index].title = source.title }
            } else { result.sources = (result.sources ?? []) + [source] }
        }
        if previous.evidenceLevel == nil { result.evidenceLevel = "C" }
        result.gaps = previous.evidenceLevel == "A" ? [] : ["关注分不表示性能宣称或竞品结论已经核实。"]
        let zh = [translatedTitle, previous.chineseTitle, item.title_zh, item.displayTitle].compactMap { $0 }.first { Scoring.matches($0,"[\\p{Han}]") }
        result.chineseTitle = zh
        if !previous.hasChineseBrief {
            result.highlights = zh.map { headline in
                let pieces = headline.components(separatedBy:CharacterSet(charactersIn:"：:，,；;\n")).map { $0.trimmingCharacters(in:.whitespacesAndNewlines) }.filter { $0.count >= 8 }
                return pieces.count >= 2 ? Array(pieces.prefix(3)).map { String($0.prefix(140)) } : ["报道要点：" + String(headline.prefix(180)), "版本差异、适用范围及限制可在原文中继续查看。"]
            }
            result.briefBasis = "headline"
        }
        if !signals.highlights.isEmpty {
            result.highlights = signals.highlights
            result.briefBasis = signals.basis
        }
        return result
    }

    static func translatedText(_ data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with:data) as? [Any],
              let segments = root.first as? [[Any]] else { return nil }
        let title = segments.compactMap { $0.first as? String }.joined().trimmingCharacters(in:.whitespacesAndNewlines)
        return !title.isEmpty && Scoring.matches(title,"[\\p{Han}]") ? title : nil
    }

    // Reuse the public headline translation service already used by the collector.
    static func translate(_ title: String, session: URLSession) async -> String? {
        var url = URLComponents(string:"https://translate.googleapis.com/translate_a/single")!
        url.queryItems = ["client":"gtx","sl":"auto","tl":"zh-CN","dt":"t","q":title].map { URLQueryItem(name:$0.key,value:$0.value) }
        do {
            let (data,response) = try await session.data(for:URLRequest(url:url.url!,timeoutInterval:12))
            guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 100_000 else { return nil }
            return translatedText(data)
        } catch { return nil }
    }
}
