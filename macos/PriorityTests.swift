import Foundation

enum PriorityTests {
    static func run() {
        let now = parseDate("2026-09-18T07:30:00Z")!
        func item(_ title: String) -> NewsItem { NewsItem(id:title,site_id:"fixture",site_name:"Fixture",source:"Fixture",title:title,url:"https://example.com/article",published_at:timestamp(now),first_seen_at:timestamp(now),last_seen_at:timestamp(now)) }
        func rank(_ title: String, pulse: ProductPulse = ProductPulse(), products: [AIProduct] = []) -> NewsPriority {
            let article = item(title)
            return Priority.rank(article,rating:Scoring.rule(article),products:products,pulse:pulse,now:now)
        }
        let model = rank("千问发布 Qwen3.8-Omni-Flash 原生全模态模型")
        let integration = rank("特斯拉接入旧版千问模型，新增语音功能")
        precondition(model.value > integration.value && model.modelChange > 0 && integration.modelChange == 0)
        precondition(model.provisional && Scoring.rule(item("千问发布新模型")).score == nil, "Priority clues must not fabricate evidence scores")
        precondition(rank("DeepSeek 发布全新 MoE 架构").architectureChange > rank("DeepSeek SDK 新增插件支持").architectureChange)
        precondition(rank("OpenAI 高管卸任董事").value == 0 && rank("Claude 用后感").value == 0, "Ordinary brand mentions do not get focus points")
        precondition(rank("疑似 OpenAI 即将发布新模型").modelChange == 0, "Rumors are not confirmed upgrades")
        precondition(rank("Gemini 4 Pro 偷跑上线").modelChange == 0 && rank("Gemini 4 Pro Sneak-Launched Online").modelChange == 0)
        precondition(rank("Anthropic 推出生命科学认证计划，三款模型纳入授权条款").modelChange == 0, "Licensing changes are not model upgrades")
        precondition(rank("Qwen 模型评测更新：跑分提升").modelChange == 0, "Benchmark reports are not model upgrades")
        precondition(rank("EMNLP 2026 浙大 LongDS 发布 v1.1，GPT-6 Astra 领跑长程数据分析 Lite 榜").modelChange == 0)
        precondition(rank("OpenAI launches Astra for Law, combining GPT-6 Astra with a legal search index").modelChange == 0)
        precondition(rank("OpenAI 推出 Astra for Law：以 GPT-6 Astra 模型为内核，叠加法律检索索引").modelChange == 0)
        precondition(rank("OpenAI 推出 Astra for Law：索引 2.3 亿 URL，法律问答正确率 54% 力压通用模型").modelChange == 0)
        precondition(rank("Claude Code 大重构！内部 3 万 Agent 管理技术免费开放").modelChange == 0)
        precondition(rank("Claude Code 大重构！内部 3 万 Agent 管理技术免费开放").architectureChange == 22)
        precondition(rank("OpenAI discovered an unreleased Astra model").modelChange == 0)
        precondition(rank("特斯拉推送更新：豆包大模型语音助手扩至更多车型").modelChange == 0)
        precondition(rank("亚马逊表示，人工智能模型应在准备就绪且安全时发布").modelChange == 0)
        precondition(rank("发布最新世界动作模型综述").modelChange == 0)
        precondition(rank("开源模型是否被夸大了").modelChange == 0)
        precondition(rank("Qwen新模型发布").focus > 0 && rank("Qwen新模型发布", products:[]).heat == 0)
        let product = AIProduct(id:"alpha",name:"AlphaAI",maker:"Example",major:false,category:"开发",summary:"Fixture",difference:"Fixture",access:"Fixture",homepage:"https://example.com",sourceURL:"https://example.com/release",repository:"example/alpha",aliases:["AlphaAI"])
        let pulse = ProductPulse(github:[GitHubTrend(repository:"example/alpha",weeklyStars:2000)],discussions:[],githubFetchedAt:timestamp(now))
        let hot = rank("AlphaAI 发布 Agent framework",pulse:pulse,products:[product])
        precondition(hot.heat == 20 && hot.reasons.contains { $0.contains("2000") })
        var stale=pulse; stale.githubFetchedAt=timestamp(now.addingTimeInterval(-86401))
        precondition(rank("AlphaAI 发布 Agent framework",pulse:stale,products:[product]).heat == 0, "Old popularity must expire")
        let cleared=Priority.rank(item("千问发布新模型"),rating:Scoring.rule(item("千问发布新模型")),products:[],pulse:ProductPulse(),watchlist:[],now:now)
        precondition(cleared.focus == 0, "Respect the user's watchlist, including an empty list")
        let story = HNProductStory(id:"100", title:"AlphaAI launches", url:"https://example.com/launch", points:400, comments:10, publishedAt:timestamp(now))
        let context = Priority.Context(products:[product], pulse:ProductPulse(discussions:[story], hnFetchedAt:timestamp(now)), now:now)
        let article = item("AlphaAI 发布 Agent framework")
        precondition(Priority.rank(article, rating:Scoring.rule(article), context:context).heat == 20)
        var unrelated = item("Local sports finals")
        unrelated.url = story.url
        precondition(Priority.rank(unrelated, rating:Scoring.rule(unrelated), context:context).heat == 0, "Unrelated HN popularity is not AI product heat")
        let expiredStory = HNProductStory(id:"101", title:story.title, url:story.url, points:1000, comments:10, publishedAt:timestamp(now.addingTimeInterval(-8 * 86400)))
        precondition(rank(article.title, pulse:ProductPulse(discussions:[expiredStory], hnFetchedAt:timestamp(now)), products:[product]).heat == 0)
        let aliases = (0..<265).flatMap { ["CatalogProduct\($0)","Catalog Product \($0)"] } + ["星河","Orbit (Preview)","C++","Nébula","CatalogProduct264",""]
        let largeCatalog=aliases.enumerated().map { index,alias -> AIProduct in
            var value=product; value.id = "large-\(index)"; value.name = alias; value.aliases = [alias]; return value
        }
        let largeContext=Priority.Context(products:largeCatalog,pulse:ProductPulse(),watchlist:[],now:now)
        let originalExpressions=aliases.filter { !$0.isEmpty }.map { alias -> NSRegularExpression in
            let escaped=NSRegularExpression.escapedPattern(for:alias)
            let chinese=alias.range(of:#"[\p{Han}]"#,options:.regularExpression) != nil
            return try! NSRegularExpression(pattern:chinese ? escaped : "(?<![a-z0-9])" + escaped + "(?![a-z0-9])",options:.caseInsensitive)
        }
        let aliasCases:[(String,Bool)] = [
            ("CatalogProduct264 发布",true),("catalog product 264 发布",true),("SuperCatalogProduct264",false),
            ("CatalogProduct264Extra",false),("介绍最新星河工具",true),("Orbit (Preview) 发布",true),("Orbit Preview 发布",false),
            ("C++ 发布",true),("C++Builder 发布",false),("NÉBULA 发布",true),("完全无关的消息",false)
        ]
        for (title,expected) in aliasCases {
            let range=NSRange(title.startIndex...,in:title)
            let original=originalExpressions.contains { $0.firstMatch(in:title,range:range) != nil }
            let combined=largeContext.productAliases?.firstMatch(in:title,range:range) != nil
            precondition(combined == original && combined == expected,"One compiled alternation preserves original alias boundaries, Unicode, Chinese substrings, escaped punctuation and case-insensitive matching")
        }
        precondition(Priority.Context(products:[],pulse:ProductPulse(),now:now).productAliases == nil,"An empty catalog must never match every headline")
        let watched=Priority.Context(products:largeCatalog,pulse:ProductPulse(),watchlist:["CatalogProduct264"],now:now)
        let namedArticle=item("CatalogProduct264 发布")
        let namedRank=Priority.rank(namedArticle,rating:Scoring.rule(namedArticle),context:watched)
        precondition(namedRank.focus == 15 && namedRank.modelChange == 0 && namedRank.architectureChange == 0,"The combined lookup changes performance, not scoring rules")
        print("PASS: interest ranking, model upgrades versus integrations, architecture magnitude, verified fresh heat, rumors and watchlist preferences")
    }
}
