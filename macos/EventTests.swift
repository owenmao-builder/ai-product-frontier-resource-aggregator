import Foundation

enum EventTests {
    static func run() throws {
        let now = parseDate("2026-09-18T09:00:00Z")!
        func item(_ id:String,_ title:String,_ url:String,_ source:String = "Test",age:Double = 0) -> NewsItem {
            let time = timestamp(now.addingTimeInterval(-age))
            return NewsItem(id:id,site_id:"test",site_name:"Test",source:source,title:title,url:url,
                published_at:time,first_seen_at:time,last_seen_at:time)
        }
        let law = AIProduct(id:"law",name:"Astra for Law",maker:"OpenAI",major:true,category:"专业应用",summary:"",difference:"",access:"",homepage:"https://openai.com",sourceURL:"https://openai.com/index/law",aliases:["Astra for Law"])
        let a = item("a","OpenAI 推出 Astra for Law：索引 2.3 亿 URL","https://www.aibase.com/zh/news/1","AIbase")
        let b = item("b","打官司 AI 助手：OpenAI 推出 Astra for Law","https://www.ithome.com/1/004/001.htm","IT之家")
        let c = item("c","OpenAI launches Astra for Law and its legal research index","https://thenextweb.com/news/astra-law","The Next Web")
        let repost = item("repost",a.title,"https://www.aibase.com/zh/news/2","Readhub · AI")
        let social = item("social","Astra for Law: New offering","https://x.com/OpenAI/status/1","OpenAI")
        let aggregation = item("aggregate","OpenAI launches Astra for Law","https://www.techmeme.com/260918/p1","Techmeme")
        let members = [a,b,c,repost,social,aggregation]
        let groups = NewsEvents.groups(members,products:[law],now:now)
        precondition(groups.count == 1 && groups[0].members.count == 6,"Cross-language coverage must collapse to one event")
        let translatedAlias = item("alias","OpenAI推出面向法律行业的AI工具Astra","https://techinasia.com/news/astra-law")
        precondition(NewsEvents.groups([a,translatedAlias],products:[law],now:now).count == 1,"A translated use-case qualifier should still identify the same named product")
        let scores = Dictionary(uniqueKeysWithValues:members.map { value in
            let rule = Scoring.rule(value)
            return (value.id,InterestScore.rating(value,priority:Priority.rank(value,rating:rule,products:[law],pulse:ProductPulse(),now:now),previous:rule,now:now))
        })
        let row = NewsEvents.present(groups[0],ratings:scores,now:now)
        precondition(row.event?.mediaCount == 3 && row.event?.articleCount == 6 && row.event?.coverage?.sourceCount == 3,"Count original outlets, not aggregator labels or official tweets")
        precondition(row.event?.reports.first(where:{$0.id == "aibase.com"})?.articles.count == 2)
        precondition(row.rating!.score == max(8,row.event!.baseScore!))
        precondition(NewsEvents.present(groups[0],ratings:scores,now:now).rating?.score == row.rating?.score,"Refreshes must not compound coverage bonuses")
        let historical = NewsEvents.present(groups[0],ratings:scores,now:now.addingTimeInterval(86400))
        precondition(historical.event?.bonus == 0,"Do not rescore old articles")
        let decoded = try JSONDecoder().decode(NewsItem.self,from:JSONEncoder().encode(row))
        precondition(decoded.event == row.event,"Native dashboard event payload must round-trip")
        precondition(row.event?.reports.first(where:{$0.id == "aibase.com"})?.focus.contains("检索与数据") == true)
        precondition(row.event?.insights.contains(where:{$0.text.contains("AIbase") && $0.text.contains("解读")}) == true)
        let qwen = [
            item("q1","阿里发布 Qwen3.8-Omni-Flash 模型","https://one.test/q"),
            item("q2","Qwen3.8-Omni-Flash: native omni model","https://two.test/q"),
            item("q3","阿里发布 Qwen3.9-Omni-Flash 模型","https://three.test/q"),
            item("q4","Qwen3.8-Omni-Flash 服务宕机","https://four.test/q"),
            item("q5","疑似 Qwen3.8-Omni-Flash 即将发布","https://five.test/q"),
            item("q6","Qwen3.8-Omni-Flash 宣布降价","https://six.test/q")
        ]
        precondition(NewsEvents.groups(qwen,now:now).count == 5,"Do not mix versions, outages, rumors or later price changes into a launch")
        let projects = [
            item("p1","Claude Code 的 Projects 改版：Claude Tag 的架构 + Slack 的 Thread 功能","https://x.com/author/status/1"),
            item("p2","Claude Code relaunches Projects to manage multiple AI agents in the cloud","https://theverge.com/news/projects")
        ]
        precondition(NewsEvents.groups(projects,now:now).count == 1)
        let clone = item("clone","Open-source version of Claude Projects that gives you context ownership","https://myproject.test","Hacker News")
        precondition(NewsEvents.groups(projects+[clone],now:now).count == 2,"A third-party alternative is not coverage of the original release")
        precondition(NewsEvents.publisher(clone).kind == "aggregator","A direct link to an unknown project from HN is not an additional media outlet")
        var knownMedia = a; knownMedia.source = "Hacker News"
        precondition(NewsEvents.publisher(knownMedia).id == "aibase.com","Known original publishers still count when reached through aggregators")
        let vague = item("p3","刚刚，Claude Code 大重构！内部 Agent 管理技术开放","https://qbitai.com/projects")
        let projectDoc = ArticleDocument(url:vague.url,title:vague.title,text:"Claude Code 这次重构的重点是 Projects，可以拆分任务并行执行。" + String(repeating:"补充公开正文。",count:65),fetchedAt:timestamp(now),truncated:false)
        precondition(NewsEvents.groups(projects+[vague],documents:[vague.url:projectDoc],now:now).count == 1,"A body-named feature can connect an otherwise ambiguous title")
        precondition(NewsEvents.groups(projects+[vague],now:now).count == 2,"Do not guess a missing feature from the brand alone")
        var architectureDoc = projectDoc
        architectureDoc.text = "最新亮相的 Claude Code Projects 重构版，把静态资料夹改为协作中心。这次重构的核心是一个协调器，负责并行工作线程和共享记忆。" + String(repeating:"其他普通描述，没有额外主题。",count:50)
        precondition(NewsEvents.excerpts(architectureDoc,item:vague).contains(where:{$0.contains("协调器")}),"Carry the named subject into adjacent architecture detail instead of repeating only the headline")
        let generic = [item("g1","OpenAI 更新产品政策","https://one.test/a"),item("g2","OpenAI 更新语音产品","https://two.test/b")]
        precondition(NewsEvents.groups(generic,now:now).count == 2,"Brand alone is insufficient")
        let integrations = [item("model","发布 GPT-6 Astra 新模型","https://one.test/model"),item("int","其他产品接入 GPT-6 Astra 模型","https://two.test/integration")]
        precondition(NewsEvents.groups(integrations,now:now).count == 2,"Integrations are separate from the model's original release")
        let gpt = AIProduct(id:"gpt",name:"GPT-6 Astra",maker:"OpenAI",major:true,category:"模型",summary:"",difference:"",access:"",homepage:"https://openai.com",sourceURL:"https://openai.com/model",aliases:["GPT-6 Astra"])
        let compared = item("compare","Qwen3.9 发布，性能领先 GPT-6 Astra","https://one.test/q39")
        precondition(NewsEvents.identity(compared,products:[gpt]).subject == "qwen3.9","A mentioned competitor must not become the event subject")
        precondition(NewsEvents.groups([item("d1","DeepSeek-R1-0528 发布","https://one.test/d"),item("d2","DeepSeek-R1 发布","https://two.test/d")],now:now).count == 2)
        let benchmark = item("bench","LongDS 发布 v1.1，GPT-6 Astra 领跑数据分析榜","https://one.test/benchmark")
        precondition(NewsEvents.groups([benchmark,integrations[0]],products:[gpt],now:now).count == 2,"A new benchmark mentioning a model is not the model release")
        let benchmarkModel = item("new-qwen","千问上线 Qwen3.8-Omni-Flash：30项评测提升","https://q.test/launch")
        precondition(NewsEvents.groups([qwen[0],benchmarkModel],now:now).count == 1,"A launch can still report benchmark results without becoming a separate benchmark event")
        var duplicate = a; duplicate.id = "urlcopy"; duplicate.url += "?utm_source=rss"
        let duplicateRow = NewsEvents.present(NewsEvents.groups([a,duplicate],products:[law],now:now)[0],ratings:scores,now:now)
        precondition(duplicateRow.event?.articleCount == 1 && duplicateRow.event?.bonus == 0)
        let old = item("old",a.title,"https://aibase.com/old",age:4*86400)
        precondition(NewsEvents.groups([old,a],products:[law],now:now).count == 2,"Unrelated release cycles outside the merge window remain separate")
        precondition(NewsEvents.coverageMinimum(sourceCount:100) == 9.5)
        var maxScores = scores; for key in maxScores.keys { maxScores[key]?.score = 9.8 }
        precondition(NewsEvents.present(groups[0],ratings:maxScores,now:now).rating?.score == 9.8,"Coverage must not dilute a higher content score or compound into an automatic 10")
        precondition(NewsEvents.isRead(row.event!,seenURLs:[a.url],seenEvents:[]))
        var refreshed = row.event!; refreshed.urls = [c.url]
        precondition(NewsEvents.isRead(refreshed,seenURLs:[],seenEvents:[row.event!.id]),"New coverage must not reset read status")
        precondition(!NewsEvents.isRead(row.event!,seenURLs:[],seenEvents:[]))
        let doc = ArticleDocument(url:a.url,title:a.title,text:"Astra for Law 提供独立法律检索索引，覆盖法律查询和文书处理场景。" + String(repeating:"广告和其他产品内容。",count:50),fetchedAt:timestamp(now),truncated:false)
        let excerpt = NewsEvents.excerpts(doc,item:a)
        precondition(excerpt.count == 1 && excerpt[0].contains("法律检索"))
        let withBody = NewsEvents.present(groups[0],ratings:scores,documents:[a.url:doc],now:now)
        precondition(withBody.event?.reports.first(where:{$0.id=="aibase.com"})?.basis.contains("正文摘录") == true)
        var withNavigation = doc
        withNavigation.text = "首页 RSS订阅 法律新产品 Astra for Law 来源 IT之家 责编 评论 感谢网友线索投递。" + doc.text
        precondition(NewsEvents.excerpts(withNavigation,item:a).allSatisfy { !$0.contains("首页") },"Do not mistake a publisher navigation/header block for an article insight")
        let unknown = [
            item("n1","发布新模型 NebulaX：结构化决策","https://aibase.com/news/n"),
            item("n2","NebulaX 模型发布，开发者开始讨论","https://ithome.com/n"),
            item("n3","Introducing the model NebulaX","https://x.com/analyst/status/n","分析作者")
        ]
        let unknownGroups = NewsEvents.groups(unknown,now:now)
        precondition(unknownGroups.count == 1,"New model names can group before a catalog entry exists")
        precondition(NewsEvents.identity(item("new-compare","NebulaX 模型发布，领先 GPT-6 Astra","https://new.test/news"),products:[gpt]).subject == "nebulax", "A new model is the subject, not its known competitor")
        precondition(NewsEvents.namedModel(in:"模型 API 新增费用说明") == nil && NewsEvents.namedModel(in:"world model advances") == nil, "Technical categories are not product names")
        let noDetails = NewsEvents.present(unknownGroups[0],ratings:[:],now:now)
        precondition(noDetails.rating?.score == 8 && noDetails.rating?.evidenceLevel == "C", "Concentrated coverage alone must surface an event without performance, cost, API or documents")
        precondition(noDetails.event?.coverage?.mediaCount == 2 && noDetails.event?.coverage?.authorCount == 1)
        let many = (0..<8).map { item("wave\($0)","NebulaX 模型发布 · 第\($0)家独立报道","https://publisher\($0).test/news") }
        precondition(NewsEvents.present(NewsEvents.groups(many,now:now)[0],ratings:[:],now:now).rating?.score == 9)
        let copies = (0..<8).map { item("copy\($0)","NebulaX 模型发布 · 相同转载标题","https://publisher\($0).test/repost") }
        precondition(NewsEvents.coverage(copies,now:now).sourceCount == 1,"Identical syndicated headlines must not manufacture a reporting wave")
        let sameOutlet = (0..<8).map { item("same\($0)","NebulaX 模型发布 · 跟进\($0)","https://aibase.com/news/\($0)","RSS \($0)") }
        precondition(NewsEvents.coverage(sameOutlet,now:now).sourceCount == 1)
        let staleWave = (0..<8).map { item("old-wave\($0)","NebulaX 模型发布 · 较早报道\($0)","https://older\($0).test/news",age:49*3600) }
        precondition(NewsEvents.coverage(staleWave+[unknown[0]],now:now).minimumScore == 0)
        precondition(NewsEvents.coverage([social,aggregation],now:now).sourceCount == 0)
        let retweet = item("retweet","RT @analyst: NebulaX 模型发布","https://x.com/retweeter/status/2")
        precondition(NewsEvents.coverage([retweet],now:now).sourceCount == 0)
        var future = unknown[0]; future.published_at = timestamp(now.addingTimeInterval(3600)); future.first_seen_at = future.published_at!; future.last_seen_at = future.published_at!
        precondition(NewsEvents.coverage([future],now:now).sourceCount == 0)
        precondition(NewsEvents.groups([unknown[0],item("other-version","NebulaX2 模型发布","https://other.test/news")],now:now).count == 2)
        precondition(NewsEvents.coverageMinimum(sourceCount:2) == 7 && NewsEvents.coverageMinimum(sourceCount:5) == 8.5)
        print("PASS: coverage alone lifts unknown models, counts media/authors, deduplicates reposts, expires old attention and preserves historical scores")
        print("PASS: event deduplication, versions/actions, origin-based coverage bonus, cap/idempotence, read persistence, source attribution and body-vs-title labels")
    }
    static func sampleToday(cachePath:String) throws {
        let cache = URL(fileURLWithPath:cachePath)
        let snapshot = try JSONDecoder().decode(NewsData.self,from:Data(contentsOf:cache.appendingPathComponent("latest-24h.json")))
        let saved = try JSONDecoder().decode([String:ReviewedEntry].self,from:Data(contentsOf:cache.appendingPathComponent("interest-ratings.json")))
        let bundled = try JSONDecoder().decode(ProductBoard.self,from:Data(contentsOf:URL(fileURLWithPath:"data/products.json")))
        let catalog = Products.mergedCatalog(bundled,discovery:snapshot.product_discovery)
        let now = Date()
        let sample = snapshot.items.filter { item in
            guard let date = item.newsTime(now:now).date, beijingCalendar.isDate(date,inSameDayAs:now) else { return false }
            return Scoring.matches(item.title,"\\bJev\\b")
        }
        let todayIDs = Set(sample.map(\.id))
        let related = snapshot.items.filter { Scoring.matches($0.title,"\\bJev\\b") }
        for group in NewsEvents.groups(related,products:catalog.items,now:now).filter({ $0.members.contains { todayIDs.contains($0.id) } }).prefix(3) {
            let row = NewsEvents.present(group,ratings:saved.mapValues(\.rating),products:catalog.items,now:now)
            let withoutDetails = NewsEvents.present(group,ratings:[:],products:catalog.items,now:now)
            let names = row.event!.reports.map { $0.name + ":" + $0.kind }.joined(separator:", ")
            print("SAMPLE \(row.event!.articleCount) articles, \(row.event!.coverage?.sourceCount ?? 0) counted sources, score \(row.rating!.displayScore), without technical details \(withoutDetails.rating!.displayScore): \(group.subject ?? row.title)\n\(names)\nCounted: \(row.event!.coverage?.sourceNames.joined(separator:", ") ?? "")")
        }
    }
}
