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
        precondition(filtered.items.count == 3 && filtered.items.filter { Products.isRecentMajorRelease($0,now:now) }.map(\.id) == [product.id], "Older or undated major products can trend without becoming new releases")
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
        let oldHot = Products.board(catalog:ProductBoard(verifiedAt:timestamp(now),items:[oldMajor]),pulse:ProductPulse(),news:[],events:[releaseEvent],now:now)
        precondition(oldHot.items.count == 1 && !Products.isRecentMajorRelease(oldHot.items[0],now:now), "Older major products can be hot but do not count as new releases")
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
        var community=indie
        community.id = "community-kev"; community.name = "Kev"; community.aliases = ["Kev"]; community.repository = nil
        community.discoveryBasis = "community"; community.lastSeenAt = timestamp(now.addingTimeInterval(-3 * 86400))
        let xSignal=ProductSignal(kind:"x",label:"X · 3 位作者讨论",title:"甲、乙、丙",url:"https://x.com/author/status/123",observedAt:community.lastSeenAt!,sourceCount:3)
        community.signals = [xSignal]
        community.relatedNews = [ProductNews(title:"Kev 决策模型开源",url:xSignal.url,date:xSignal.observedAt)]
        let communityDiscovery=ProductDiscovery(checkedAt:timestamp(now),items:[community],pending:[],errors:[])
        let communityCatalog=Products.mergedCatalog(ProductBoard(verifiedAt:"",items:[]),discovery:communityDiscovery,now:now)
        let communityBoard=Products.board(catalog:communityCatalog,pulse:ProductPulse(),news:[],now:now)
        precondition(communityBoard.items.count == 1 && communityBoard.items[0].signals?.first?.kind == "x" && communityBoard.items[0].relatedNews?.count == 1, "Unknown community products survive discovery and retain their original discussion evidence")
        precondition(!Products.isRecentMajorRelease(community,now:now) && community.releasedOn == nil)
        var candidate=community; candidate.signals = []
        let candidates=Products.mergedCatalog(ProductBoard(verifiedAt:"",items:[]),discovery:ProductDiscovery(checkedAt:timestamp(now),items:[candidate],pending:[],errors:[]),now:now)
        precondition(candidates.items.count == 1 && Products.board(catalog:candidates,pulse:ProductPulse(),news:[],now:now).items.isEmpty,"Keep recent candidates for pulse matching, but do not declare a single discussion hot")
        var curated=community; curated.id = "editorial-kev"; curated.summary = "编辑说明"; curated.discoveryBasis = "official"; curated.releasedOn = "2026-09-15"; curated.signals = []; curated.relatedNews = []
        let enriched=Products.mergedCatalog(ProductBoard(verifiedAt:"",items:[curated]),discovery:communityDiscovery,now:now)
        precondition(enriched.items.count == 1 && enriched.items[0].id == curated.id && enriched.items[0].summary == curated.summary && enriched.items[0].releasedOn == curated.releasedOn && enriched.items[0].signals?.count == 1,"Merge community heat without overwriting curated identity, descriptions or official dates")
        var muse=community; muse.id = "meta-muse"; muse.name = "Muse"; muse.aliases = ["Meta Muse"]; muse.major = true; muse.releasedOn = "2026-09-08"; muse.discoveryBasis = "official"
        let museBoard=Products.board(catalog:ProductBoard(verifiedAt:"",items:[muse]),pulse:ProductPulse(),news:[],now:now)
        precondition(museBoard.items.count == 1 && !Products.isRecentMajorRelease(museBoard.items[0],now:now),"Older Meta Muse can be hot while staying out of major-vendor new releases")
        let expiredCommunity=Products.board(catalog:communityCatalog,pulse:ProductPulse(),news:[],now:now.addingTimeInterval(4 * 86400 + 1))
        precondition(expiredCommunity.items.isEmpty,"Seven-day discussion evidence expires from its original date, not fetch time")
        var variants:[AIProduct] = []
        for name in ["Muse","Muse Realtime Avatar","Model3.8","Model38","OpenJev","Jev"] { var variant=community; variant.name = name; variant.id = name; variant.aliases = [name]; variants.append(variant) }
        let distinct=Products.mergedCatalog(ProductBoard(verifiedAt:"",items:[]),discovery:ProductDiscovery(checkedAt:timestamp(now),items:variants,pending:[],errors:[]),now:now)
        precondition(distinct.items.count == variants.count,"Do not merge different products, derivatives or numeric versions")
        var confirmed=community; confirmed.discoveryBasis = "official"; confirmed.major = true; confirmed.releasedOn = "2026-09-17"; confirmed.releaseKind = "新模型"; confirmed.sourceURL = "https://example.com/kev"; confirmed.signals = []
        let promoted=Products.mergedCatalog(communityCatalog,discovery:ProductDiscovery(checkedAt:timestamp(now),items:[confirmed],pending:[],errors:[]),now:now)
        precondition(promoted.items[0].id == community.id && promoted.items[0].sourceURL == confirmed.sourceURL && Products.isRecentMajorRelease(promoted.items[0],now:now) && promoted.items[0].signals?.count == 1,"Official confirmation promotes the entry while preserving identity and discussion")
        let hfSignal=ProductSignal(kind:"huggingface",label:"Hugging Face 趋势 #2",title:"实时模型趋势",url:"https://huggingface.co/team/model",observedAt:timestamp(now))
        var hfProduct=community; hfProduct.signals = [hfSignal]
        precondition(Products.board(catalog:ProductBoard(verifiedAt:"",items:[hfProduct]),pulse:ProductPulse(),news:[],now:now).items.count == 1 && !Products.isRecentMajorRelease(hfProduct,now:now),"Hugging Face trends enter hot products without inventing a release date")
        precondition(Products.freshSignal(hfSignal,now:now.addingTimeInterval(86400)) && !Products.freshSignal(hfSignal,now:now.addingTimeInterval(86401)),"Hugging Face observations expire after 24 hours")
        var versionA=community; versionA.name = "Model2.5"; versionA.aliases = [versionA.name]; versionA.sourceURL = "https://example.com/model-family"
        var versionB=versionA; versionB.name = "Model25"; versionB.aliases = [versionB.name]
        var sharedEvent=releaseEvent; sharedEvent.event?.subject = versionB.name; sharedEvent.event?.urls = [versionA.sourceURL]
        precondition(Products.reportingSignal(versionA,events:[sharedEvent],now:now,catalog:[versionA,versionB]) == nil && Products.reportingSignal(versionB,events:[sharedEvent],now:now,catalog:[versionA,versionB]) != nil,"Different model versions cannot borrow heat through a shared announcement URL")
        sharedEvent.event?.subject = nil
        precondition(Products.reportingSignal(versionA,events:[sharedEvent],now:now,catalog:[versionA,versionB]) == nil,"An ambiguous family announcement must not heat every model")
        precondition(Products.nameKey("Model2.5") != Products.nameKey("Model25"),"Keep decimal version boundaries")
        var fullRepo=product; fullRepo.repository = "https://github.com/example/alpha-ai/tree/main"
        precondition(Products.board(catalog:ProductBoard(verifiedAt:"",items:[fullRepo]),pulse:pulse,news:[],now:now).items[0].signals?.contains(where:{ $0.kind == "github" }) == true,"Discovered repository URLs can match GitHub owner/repository trend IDs")
        var nova=community; nova.name = "Nova"; nova.aliases = ["Nova"]; nova.maker = "Shared vendor"
        for kind in ["github","huggingface","maker"] {
            var first=nova,second=nova; first.id = kind + "-alice"; second.id = kind + "-bob"
            if kind == "github" { first.repository = "alice/Nova"; second.repository = "https://github.com/bob/Nova/tree/main" }
            else if kind == "huggingface" { first.homepage = "https://huggingface.co/alice/Nova"; second.homepage = "https://huggingface.co/bob/Nova/tree/main" }
            else { first.maker = "Alice Labs"; second.maker = "Bob Labs" }
            let distinctOwners=Products.mergedCatalog(ProductBoard(verifiedAt:"",items:[first]),discovery:ProductDiscovery(checkedAt:timestamp(now),items:[second],pending:[],errors:[]),now:now)
            precondition(distinctOwners.items.map(\.id) == [first.id,second.id],"Homonymous repositories, HF model identities and named makers must not merge")
        }
        var repoA=nova,repoB=nova; repoA.repository = "alice/Nova"; repoB.repository = "https://github.com/alice/Nova/tree/main"
        precondition(Products.compatibleIdentity(repoA,repoB),"Canonical GitHub repository forms have the same identity")
        var unknownMaker=community; unknownMaker.maker = "开发者 / 社区"
        var officialMaker=confirmed; officialMaker.maker = "Cognition"; officialMaker.repository = "jaredpalmer/kev"
        let resolvedMaker=Products.mergedCatalog(ProductBoard(verifiedAt:"",items:[unknownMaker]),discovery:ProductDiscovery(checkedAt:timestamp(now),items:[officialMaker],pending:[],errors:[]),now:now)
        precondition(resolvedMaker.items.count == 1 && resolvedMaker.items[0].id == community.id && resolvedMaker.items[0].maker == "Cognition" && resolvedMaker.items[0].repository == officialMaker.repository,"Official identification can enrich an unknown maker without replacing its card or heat")
        print("PASS: product release windows, automatic catalog merging, pending leads, persistence, Beijing midnight expiry, exact announcements, heat thresholds and today's related news")
    }
}
