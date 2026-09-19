import Foundation

enum TechnicalSignalsTests {
    static func run() throws {
        let now = parseDate("2026-09-19T03:00:00Z")!
        func item(_ title:String) -> NewsItem {
            NewsItem(id:title,site_id:"test",site_name:"Test",source:"Test",title:title,url:"https://example.com/news",published_at:timestamp(now),first_seen_at:timestamp(now),last_seen_at:timestamp(now))
        }
        func rate(_ article:NewsItem, document:ArticleDocument? = nil, products:[AIProduct] = [], pulse:ProductPulse = ProductPulse()) -> NewsRating {
            let signals = TechnicalSignals.analyze(article,document:document,products:products,now:now)
            let context = Priority.Context(products:products,pulse:pulse,now:now)
            let priority = Priority.rank(article,rating:Scoring.rule(article),context:context,signals:signals)
            return InterestScore.rating(article,priority:priority,previous:Scoring.rule(article),signals:signals,now:now)
        }
        let range = item("Nova 发布新模型，速度快20–200倍，成本低40–400倍")
        let signals = TechnicalSignals.analyze(range,now:now)
        precondition(signals.metrics.first { $0.key == "speed_gain" }?.factor == 20)
        precondition(signals.metrics.first { $0.key == "cost_gain" }?.factor == 40)
        let generic = rate(range)
        precondition(generic.sortScore >= 8 && generic.evidenceLevel == "C", "Unknown products with massive gains deserve high interest without evidence/API gates")
        precondition(generic.tags.contains("推理加速") && generic.tags.contains("成本下降"))
        precondition(rate(item("Nova 发布新模型，速度快2倍，成本低2倍")).sortScore < generic.sortScore)
        precondition(rate(item("今天新出的 AI 模型：Nova")).dimensions?.contains { $0.key == "model_change" } == true)
        let english = TechnicalSignals.extractMetrics("20x-200x faster, 40–400 times cheaper",origin:"test")
        precondition(english.contains { $0.key == "speed_gain" && $0.factor == 20 })
        precondition(english.contains { $0.key == "cost_gain" && $0.factor == 40 })
        let percent = TechnicalSignals.extractMetrics("速度提升100%，成本下降50%",origin:"test")
        precondition(percent.count == 2 && percent.allSatisfy { $0.factor == 2 }, "Percentages aren't multipliers")
        for title in ["Nova model is not 200x faster", "Nova 模型并未速度快20倍", "模型有200个参数", "模型成本下降100%"] {
            precondition(TechnicalSignals.extractMetrics(title,origin:"test").isEmpty, "Reject negations, unrelated numbers and unbounded ratios: " + title)
        }
        precondition(rate(item("疑似 Nova 即将发布模型：速度快200倍")).sortScore < 4)
        let short = item("Nova 模型带来效率变化")
        let doc = ArticleDocument(url:short.url,title:short.title,text:"Nova 模型速度快30倍，成本低40倍。" + String(repeating:"这是结构化决策任务下的比较。",count:35),fetchedAt:timestamp(now),truncated:false)
        precondition(rate(short,document:doc).tags.contains("推理加速"), "Read the body even when the title lacks numeric claims")
        precondition(rate(short,document:doc).sortScore >= 8, "A short headline must not keep major body-reported gains below the reading cutoff")
        let noise = ArticleDocument(url:short.url,title:short.title,text:String(repeating:"这篇文章讨论模型的适用场景。",count:35) + " 相关推荐：另一个模型速度快200倍",fetchedAt:timestamp(now),truncated:false)
        precondition(TechnicalSignals.analyze(short,document:noise,now:now).metrics.isEmpty)
        let catalog = try JSONDecoder().decode(ProductBoard.self,from:Data(contentsOf:URL(fileURLWithPath:"data/products.json")))
        let jev = catalog.items.first { $0.id == "typesafe-jev" }!
        let article = item("[程序员] 今天新出的挺有意思的 AI 模型： TypeSafe Jev")
        let story = HNProductStory(id:"test",title:"Introducing System One Models and Jev",url:jev.sourceURL,points:1892,comments:496,publishedAt:"2026-09-15T19:25:03Z")
        let pulse = ProductPulse(discussions:[story],hnFetchedAt:timestamp(now))
        let rating = rate(article,products:[jev],pulse:pulse)
        precondition(rating.score == 9.2 && rating.briefBasis == "official-context" && rating.hasChineseBrief)
        precondition(rating.tags.prefix(3) == ["推理加速","成本下降","架构创新"])
        precondition(rating.dimensions?.first { $0.key == "cost_gain" }?.value == 5)
        precondition(rating.sources?.contains { $0.url == jev.sourceURL } == true)
        precondition(rate(article,products:[jev]).score == 8.4, "Large gains deserve high interest even with neutral unknown heat")
        for title in ["Bespoke 复刻 Jev 发布 Nimble 模型", "Dify 接入 Jev 模型", "OpenJev 模型发布", "Jev-like model released", "用 Jev 模型玩宝可梦"] {
            precondition(TechnicalSignals.releaseContext(item(title),products:[jev],now:now) == nil, "Do not inherit Jev's launch gains: " + title)
        }
        precondition(TechnicalSignals.releaseContext(article,products:[jev],now:now.addingTimeInterval(8*86400)) == nil)
        let identity = NewsEvents.identity(article,products:[jev])
        precondition(identity.key == NewsEvents.identity(item("Jev 模型发布三天"),products:[jev]).key, "Short product names and their full aliases share one event")
        precondition(identity.key != NewsEvents.identity(item("Dify 接入 Jev 模型"),products:[jev]).key)
        precondition(identity.key != NewsEvents.identity(item("用 Jev 模型玩宝可梦"),products:[jev]).key)
        for title in ["Jev is now available in Dify's Question Classifier node", "Use the latest Jev model with AI SDK", "Jev Ultrafast: A browser agent with a dynamic indexed action space"] {
            precondition(identity.key != NewsEvents.identity(item(title),products:[jev]).key, "SDK integrations and named demos are separate from the original model launch")
            precondition(TechnicalSignals.releaseContext(item(title),products:[jev],now:now) == nil)
        }
        precondition(TechnicalSignals.analyze(item("Nova model does not have a new architecture")).architecture == 0)
        let clonePriority = Priority.rank(item("复刻 Jev 发布 Nimble 模型"),rating:Scoring.rule(article),context:Priority.Context(products:[jev],pulse:pulse,now:now))
        precondition(clonePriority.heat == 0, "Derivative projects do not inherit the original launch's HN popularity")
        var official = article; official.url = jev.sourceURL
        precondition(NewsEvents.publisher(official,products:[jev]).kind == "official")
        var old = rating; old.version = "interest-v1"
        precondition(old.isInterest && old.isScored, "Preserve historical interest-v1 scores")
        print("PASS: unknown-model relevance, speed/cost magnitudes, percentages, body enrichment, attributed Jev 9.2, scope exclusions and historical compatibility")
    }

    // Read-only, bounded to today's Jev articles; never writes or rerates the history cache.
    @MainActor static func sample(cachePath:String) throws {
        let cache = URL(fileURLWithPath:cachePath)
        let data = try JSONDecoder().decode(NewsData.self,from:Data(contentsOf:cache.appendingPathComponent("latest-24h.json")))
        let catalog = try JSONDecoder().decode(ProductBoard.self,from:Data(contentsOf:URL(fileURLWithPath:"data/products.json")))
        let pulse = try JSONDecoder().decode(ProductPulse.self,from:Data(contentsOf:cache.appendingPathComponent("product-pulse.json")))
        let previous = try JSONDecoder().decode([String:ReviewedEntry].self,from:Data(contentsOf:cache.appendingPathComponent("interest-ratings.json")))
        let now = Date()
        let context = Priority.Context(products:catalog.items,pulse:pulse,now:now)
        for article in data.items.filter({ NewsStore.isToday($0,now:now) && TechnicalSignals.names("Jev",in:$0.title) }).prefix(5) {
            let signals = TechnicalSignals.analyze(article,products:catalog.items,now:now)
            let priority = Priority.rank(article,rating:Scoring.rule(article),context:context,signals:signals)
            let rating = InterestScore.rating(article,priority:priority,previous:Scoring.rule(article),signals:signals,now:now)
            print("TODAY \(previous[article.id]?.rating.displayScore ?? "—") → \(rating.displayScore) | \(rating.tags.joined(separator:" / ")) | \(article.title.prefix(95))")
        }
    }
}
