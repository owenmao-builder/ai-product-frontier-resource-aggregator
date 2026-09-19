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
        var firstReport = item; firstReport.title = "AlphaAI 模型发布"; firstReport.url = "https://first-media.test/release"
        var secondReport = firstReport; secondReport.id = "second-report"; secondReport.title = "新模型 AlphaAI 开放使用"; secondReport.url = "https://second-media.test/release"
        let releaseGroup = NewsEvents.groups([firstReport,secondReport],products:[indie],now:now)[0]
        let releaseEvent = NewsEvents.present(releaseGroup,ratings:[:],products:[indie],now:now)
        let reportingBoard = Products.board(catalog:indieCatalog,pulse:ProductPulse(),news:[firstReport],events:[releaseEvent],now:now)
        precondition(reportingBoard.items.first?.isHot == true && reportingBoard.items.first?.signals?.first?.sourceCount == 2,
                     "An independent model with concentrated reporting must appear in products without GitHub/HN data")
        precondition(reportingBoard.items.first?.signals?.first?.label == "2 家集中报道")
        var competitorEvent = releaseEvent; competitorEvent.event?.subject = "AlphaAI Next"
        precondition(Products.reportingSignal(indie,events:[competitorEvent],now:now) == nil, "Do not borrow a different version's heat through a mention of this product")
        var datedEvent = releaseEvent; datedEvent.event?.latestAt = timestamp(now.addingTimeInterval(-86400))
        precondition(Products.reportingSignal(indie,events:[datedEvent],now:now) == nil, "Yesterday's event does not become today's product heat by refreshing")
        datedEvent.event?.latestAt = timestamp(now.addingTimeInterval(3600))
        precondition(Products.reportingSignal(indie,events:[datedEvent],now:now) == nil)
        var singleSource = releaseEvent; singleSource.event?.coverage?.sourceCount = 1
        precondition(Products.reportingSignal(indie,events:[singleSource],now:now) == nil)
        precondition(Products.board(catalog:ProductBoard(verifiedAt:timestamp(now),items:[oldMajor]),pulse:ProductPulse(),news:[],events:[releaseEvent],now:now).items.isEmpty,
                     "Reporting heat still cannot bypass a major vendor's seven-day release window")
        var otherMajor = product; otherMajor.id = "other-major"; otherMajor.name = "Other Model"; otherMajor.aliases = [otherMajor.name]
        let ranked = Products.board(catalog:ProductBoard(verifiedAt:timestamp(now),items:[otherMajor,indie]),pulse:ProductPulse(),news:[],events:[releaseEvent],now:now)
        precondition(ranked.items.first?.id == indie.id, "Concentrated reporting is not buried below all major-vendor entries")
        var exactRelease = product; exactRelease.name = "AlphaAI Docs"; exactRelease.aliases = ["AlphaAI Docs"]; exactRelease.sourceURL = base["url"] as! String
        precondition(Products.board(catalog:ProductBoard(verifiedAt:timestamp(now),items:[exactRelease]),pulse:pulse,news:[],now:now).items[0].isHot, "A linked official announcement can cover a specifically named feature without generic brand aliases")
        var timezone = Calendar(identifier: .gregorian); timezone.timeZone = TimeZone(secondsFromGMT:8 * 3600)!
        boundary.releasedOn = "2026-09-11"
        precondition(Products.isRecentRelease(boundary,now:parseDate("2026-09-17T15:59:59Z")!,calendar:timezone))
        precondition(!Products.isRecentRelease(boundary,now:parseDate("2026-09-17T16:00:00Z")!,calendar:timezone), "Date-only publication follows the user's local day at midnight")
        var discovered = product
        discovered.id = "discovered"; discovered.name = "AlphaAI Next"; discovered.aliases = ["AlphaAI Next"]
        discovered.discoveredAutomatically = true; discovered.verifiedAt = timestamp(now); discovered.dateBasis = "官方结构化发布日期"
        let pending = PendingProduct(name:"Unconfirmed Model",maker:"Example",newsTitle:"A new model",newsURL:"https://example.com/pending",reason:"缺少官方日期")
        let discovery = ProductDiscovery(checkedAt:timestamp(now),items:[product,discovered],pending:[pending],errors:[])
        let merged = Products.mergedCatalog(catalog, discovery: discovery, now: now)
        precondition(merged.items.count == 2 && merged.items[0].summary == catalog.items[0].summary, "Merge new releases without duplicating or replacing curated descriptions")
        var releaseNews = item; releaseNews.title = "AlphaAI Next launches"; releaseNews.url = "https://example.com/next"
        let synced = Products.board(catalog:merged,pulse:pulse,news:[releaseNews],now:now)
        precondition(synced.items.first { $0.id == "discovered" }?.relatedNews?.count == 1, "A newly discovered product must link today's matching news")
        precondition(synced.discovery?.pending.count == 1 && !synced.items.contains { $0.name == pending.name }, "Unverified leads are visible separately, never counted as confirmed releases")
        let restored = try JSONDecoder().decode(ProductBoard.self, from: JSONEncoder().encode(synced))
        precondition(restored.discovery?.items.count == 2 && restored.items.first { $0.id == "discovered" }?.dateBasis == discovered.dateBasis, "Discovery status and provenance survive cache round trips")
        let noResurrection = Products.mergedCatalog(catalog, discovery:discovery, now:now.addingTimeInterval(7 * 86400))
        precondition(Products.board(catalog:noResurrection,pulse:pulse,news:[],now:now.addingTimeInterval(7 * 86400)).items.isEmpty)
        precondition(!Products.isRecentRelease(boundary,now:parseDate("2026-09-17T16:00:00Z")!), "The default release window follows Beijing midnight regardless of system timezone")
        print("PASS: product release windows, automatic catalog merging, pending leads, persistence, Beijing midnight expiry, exact announcements, heat thresholds and today's related news")
    }
}
