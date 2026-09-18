import Foundation

enum InterestScoreTests {
    static func run() {
        let now = parseDate("2026-09-18T08:00:00Z")!
        func item(_ title:String) -> NewsItem { NewsItem(id:title,site_id:"test",site_name:"Test",source:"Test",title:title,url:"https://example.com/news",published_at:timestamp(now),first_seen_at:timestamp(now),last_seen_at:timestamp(now)) }
        func score(_ title:String, watchlist:[String] = Priority.defaultWatchlist) -> NewsRating {
            let value=item(title), pending=Scoring.rule(value)
            let priority=Priority.rank(value,rating:pending,products:[],pulse:ProductPulse(),watchlist:watchlist,now:now)
            return InterestScore.rating(value,priority:priority,previous:pending,now:now)
        }
        let model=score("智谱发布 GLM-5.3-FlashX 模型")
        precondition(model.score == 7.4 && model.isScored && model.evidenceLevel == "C" && model.statusLabel == "C 不足", "Evidence C and absent documents must not block a direct interest score")
        precondition(model.dimensions?.contains { $0.key == "architecture_change" } == false, "Models need not also change architecture")
        precondition(model.dimensions?.first { $0.key == "heat" }?.reason.contains("中性估值") == true, "Do not fabricate popularity when no signal exists")
        precondition(model.hasChineseBrief && model.briefBasis == "headline")
        precondition(score("Claude Code 大重构！内部 3 万 Agent 管理技术免费开放").sortScore >= 7)
        precondition(score("DeepSeek 发布全新 MoE 架构").sortScore > score("DeepSeek SDK 新增插件支持").sortScore)
        precondition(model.sortScore > score("智谱旧模型接入另一款产品").sortScore)
        precondition(score("疑似 OpenAI 即将发布新模型").sortScore < 4)
        precondition(score("OpenAI Claude DeepSeek Agent Harness 可插拔 黑箱可见").sortScore < 5, "Keyword stuffing is not a release")
        precondition(score("智谱发布 GLM-5.3-FlashX 模型",watchlist:[]).sortScore < model.sortScore)
        let app = item("OpenAI 推出 Astra for Law：新增法律检索服务")
        let known = AIProduct(id:"law",name:"Astra for Law",maker:"OpenAI",major:true,category:"专业应用",summary:"",difference:"",access:"",homepage:app.url,sourceURL:app.url,aliases:["Astra for Law"])
        let appPriority = Priority.rank(app,rating:Scoring.rule(app),products:[known],pulse:ProductPulse(),now:now)
        precondition(appPriority.focus == 15 && appPriority.modelChange == 0, "A specific new application is a focused product event even without measured heat, not a new model")
        let data = Data(#"[[["阿里发布千问新模型","Alibaba releases Qwen",null,null,10]],null,"en"]"#.utf8)
        precondition(InterestScore.translatedText(data) == "阿里发布千问新模型")
        precondition(InterestScore.translatedText(Data("{}".utf8)) == nil)
        let restored = try! JSONDecoder().decode(NewsRating.self,from:JSONEncoder().encode(model))
        precondition(restored.score == model.score && restored.dimensions?.first?.weight == 30)
        print("PASS: direct interest scores without evidence/API gates, applicable dimensions, neutral missing heat, watchlist, integration exclusions and Chinese headline briefs")
    }
}
