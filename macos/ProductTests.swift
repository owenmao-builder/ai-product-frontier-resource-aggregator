import Foundation

enum ProductTests {
    static func run() throws {
        let now = parseDate("2026-09-17T08:00:00Z")!
        let html = #"<article class="Box-row"><h2><a href="/example/alpha-ai">Alpha</a></h2><span>2,031 stars this week</span></article>"#
        let trends = try Products.parseGitHub(Data((html + html).utf8))
        precondition(trends.count == 1 && trends[0].weeklyStars == 2031, "Use weekly growth, not lifetime stars, and deduplicate")
        do { _ = try Products.parseGitHub(Data("<html>Please log in</html>".utf8)); preconditionFailure("A changed or blocked page must fail instead of clearing cached heat") } catch { }
        let base: [String: Any] = ["objectID":"123", "title":"AlphaAI ships a product update", "url":"https://example.com/update", "points":200, "num_comments":50, "created_at_i":now.timeIntervalSince1970 - 3600]
        var low = base; low["objectID"] = "124"; low["points"] = 99
        var old = base; old["objectID"] = "125"; old["created_at_i"] = now.timeIntervalSince1970 - 8 * 86400
        var future = base; future["objectID"] = "126"; future["created_at_i"] = now.timeIntervalSince1970 + 3600
        var unsafe = base; unsafe["objectID"] = "127"; unsafe["url"] = "javascript:alert(1)"
        let discussions = try Products.parseHN(JSONSerialization.data(withJSONObject: ["hits":[base, base, low, old, future, unsafe]]), now: now)
        precondition(discussions.count == 1 && discussions[0].points == 200)
        var product = AIProduct(id:"alpha",name:"AlphaAI",maker:"Example",major:true,category:"知识研究",summary:"Fixture",difference:"Fixture",access:"Fixture",homepage:"https://example.com/",sourceURL:"https://example.com/",repository:"example/alpha-ai",aliases:["AlphaAI"])
        product.releasedOn = "2026-09-17"; product.releaseKind = "新模型"
        precondition(Products.matches("AlphaAI releases a new feature", product: product))
        precondition(!Products.matches("SuperAlphaAI is a different app", product: product), "Avoid substring collisions")
        let catalog = ProductBoard(verifiedAt:timestamp(now),items:[product])
        let pulse = ProductPulse(github:trends,discussions:discussions,checkedAt:timestamp(now),githubFetchedAt:timestamp(now),hnFetchedAt:timestamp(now))
        let item = NewsItem(id:"product-news",site_id:"test",site_name:"Test",source:"Test",title:"AlphaAI update",url:"https://example.com/news",published_at:timestamp(now.addingTimeInterval(-60)),first_seen_at:timestamp(now),last_seen_at:timestamp(now))
        var staleNews = item; staleNews.id = "old"; staleNews.url += "/old"; staleNews.published_at = timestamp(now.addingTimeInterval(-86400))
        let board = Products.board(catalog:catalog,pulse:pulse,news:[item,item,staleNews],now:now)
        precondition(board.items[0].signals?.count == 2 && board.items[0].isHot)
        precondition(board.items[0].relatedNews?.count == 1, "Link only today's news without duplicates or rescoring history")
        let expired = Products.board(catalog:catalog,pulse:pulse,news:[],now:now.addingTimeInterval(86401))
        precondition(!expired.items[0].isHot && expired.items[0].major, "Heat expires without deleting the official catalog")
        product.repository = nil
        var oldPulse = pulse; oldPulse.discussions[0].publishedAt = timestamp(now.addingTimeInterval(-8 * 86400))
        let oldBoard = Products.board(catalog:ProductBoard(verifiedAt:timestamp(now),items:[product]),pulse:oldPulse,news:[],now:now)
        precondition(!oldBoard.items[0].isHot, "Fresh observation cannot renew an old discussion")
        var failed = pulse; failed.errors = ["GitHub":"Network failure"]
        let cached = Products.board(catalog:catalog,pulse:failed,news:[],now:now)
        precondition(cached.errors?["GitHub"] != nil && cached.items[0].isHot, "Report failure while retaining still-fresh evidence")
        var boundary = product
        boundary.releasedOn = "2026-09-11"
        precondition(Products.isRecentRelease(boundary, now:now), "Include today and six preceding local calendar days")
        boundary.releasedOn = "2026-09-10"
        precondition(!Products.isRecentRelease(boundary, now:now), "Do not show releases on the eighth calendar day")
        boundary.releasedOn = "2026-09-18"
        precondition(!Products.isRecentRelease(boundary, now:now), "Future announcements do not qualify")
        boundary.releasedOn = "2026-09-31"
        precondition(Products.releaseDate(boundary) == nil, "Reject impossible dates")
        boundary.releasedOn = nil
        precondition(!Products.isRecentRelease(boundary, now:now), "Unknown release dates do not qualify")
        var oldMajor = product; oldMajor.id = "old-major"; oldMajor.releasedOn = "2026-09-03"
        let filtered = Products.board(catalog:ProductBoard(verifiedAt:timestamp(now),items:[product,oldMajor,boundary]),pulse:pulse,news:[item],now:now)
        precondition(filtered.items.map(\.id) == [product.id], "Fresh heat, verification and related news must not renew an old or undated release")
        let aged = Products.board(catalog:catalog,pulse:pulse,news:[],now:now.addingTimeInterval(7 * 86400))
        precondition(aged.items.isEmpty, "Automatically remove a release once it passes seven calendar days")
        var indie = product; indie.major = false; indie.releasedOn = nil
        let indieCatalog = ProductBoard(verifiedAt:timestamp(now),items:[indie])
        precondition(Products.board(catalog:indieCatalog,pulse:pulse,news:[],now:now).items.count == 1, "An older independent tool can trend this week")
        precondition(Products.board(catalog:indieCatalog,pulse:pulse,news:[],now:now.addingTimeInterval(86401)).items.isEmpty, "Do not retain a non-trending tool as a permanent directory")
        var exactRelease = product; exactRelease.name = "AlphaAI Docs"; exactRelease.aliases = ["AlphaAI Docs"]; exactRelease.sourceURL = base["url"] as! String
        precondition(Products.board(catalog:ProductBoard(verifiedAt:timestamp(now),items:[exactRelease]),pulse:pulse,news:[],now:now).items[0].isHot, "A linked official announcement can cover a specifically named feature without generic brand aliases")
        var timezone = Calendar(identifier: .gregorian); timezone.timeZone = TimeZone(secondsFromGMT:8 * 3600)!
        boundary.releasedOn = "2026-09-11"
        precondition(Products.isRecentRelease(boundary,now:parseDate("2026-09-17T15:59:59Z")!,calendar:timezone))
        precondition(!Products.isRecentRelease(boundary,now:parseDate("2026-09-17T16:00:00Z")!,calendar:timezone), "Date-only publication follows the user's local day at midnight")
        print("PASS: product release windows, invalid and unknown dates, local midnight expiry, exact announcements, heat thresholds and today's related news")
    }
}
