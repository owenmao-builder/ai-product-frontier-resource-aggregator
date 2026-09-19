import SwiftUI
import AppKit

struct MenuContent: View {
    @ObservedObject var store: NewsStore
    var openDashboard: () -> Void
    var openSettings: () -> Void
    @State private var expanded: String?
    @State private var showEvidence = Set<String>()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "sparkle.magnifyingglass").font(.system(size: 23, weight: .semibold)).foregroundStyle(.indigo)
                VStack(alignment: .leading, spacing: 3) {
                    Text("AI 资讯聚合").font(.system(size: 17, weight: .bold))
                    Text(store.section == "products" ? "\(store.productBoard.items.count) 款产品 · \(store.productBoard.items.filter(\.isHot).count) 款近期热门" : store.filter == "today" ? "今天 \(store.todayEvents.count) 个事件 · \(store.todayEvents.filter { store.rating(for:$0).sortScore >= 7 }.count) 个重点" : "\(store.newsItems.count) 个事件 · \(store.items.count) 篇报道").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { Task { await store.refresh() } } label: {
                    if store.loading { ProgressView().controlSize(.small).frame(width: 20, height: 20) }
                    else { Image(systemName: "arrow.clockwise").font(.system(size: 15, weight: .medium)) }
                }.disabled(store.loading).buttonStyle(.borderless).help("立即拉取最新资讯")
                Button(action: openSettings) { Image(systemName: "slider.horizontal.3").font(.system(size: 16)) }.buttonStyle(.borderless).help("更新与评分设置")
            }.padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 14)

            Picker("栏目", selection: $store.section) {
                Text("新闻").tag("news")
                Text("AI 产品").tag("products")
            }.pickerStyle(.segmented).padding(.horizontal, 16).padding(.bottom, 12)

            if store.section == "products" {
                ProductMenuContent(store: store, openDashboard: openDashboard)
            } else {

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索标题或来源", text: $store.query).textFieldStyle(.plain).font(.system(size: 14))
                if !store.query.isEmpty { Button { store.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain) }
            }.padding(9).background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 9)).padding(.horizontal, 16)

            HStack(spacing: 6) {
                filter("今天", "today")
                filter("全部", "all")
                filter("7 分以上", "high")
                filter("未评分", "pending")
                filter("未读", "unread")
                Spacer()
                Text("关注优先 ↓").font(.system(size: 12)).foregroundStyle(.secondary).help(Priority.method)
            }.padding(.horizontal, 16).padding(.vertical, 12)

            Divider()
            if let error = store.error { banner(error, color: .orange) }
            if let error = store.aiError { banner(error, color: .orange) }
            ScrollView {
                LazyVStack(spacing: 0) {
                    if store.visible.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "tray").font(.system(size: 28)).foregroundStyle(.secondary)
                            Text(store.loading ? "正在拉取资讯…" : "没有符合条件的资讯").font(.system(size: 15, weight: .medium))
                            Button("显示全部") { store.filter = "all"; store.query = "" }.buttonStyle(.borderless)
                        }.frame(maxWidth: .infinity).padding(.vertical, 70)
                    }
                    ForEach(Array(store.visible.prefix(40)),id:\.presentationID) { item in
                        newsRow(item)
                        Divider().padding(.leading, 17)
                    }
                    if store.visible.count > 40 {
                        Button("在完整看板查看其余 \(store.visible.count - 40) 条", action: openDashboard)
                            .font(.system(size: 13)).buttonStyle(.borderless).padding(18)
                    }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(store.scoring ? "正在读取原文并评估…" : store.filter == "today" ? "今天优先阅读 · 高分中文重点" : "按类型评估 · \(store.items.count - store.assessedCount) 条待评估")
                    Spacer()
                    Button("评分说明") { expanded = expanded == "rubric" ? nil : "rubric" }.buttonStyle(.borderless)
                }.font(.system(size: 12)).foregroundStyle(.secondary)
                if expanded == "rubric" {
                    Text(InterestScore.method + "\n" + NewsEvents.method + "\nA：材料充分；B：部分待验；C：材料不足。证据状态不限制关注分。")
                        .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Text(store.directRefreshLabel)
                    Spacer()
                    Text("每 \(store.preferences.refreshMinutes) 分钟全源采集")
                }.font(.system(size: 12)).foregroundStyle(.secondary)
                Text("\(store.snapshotLabel) · 北京时间")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .help("本机直接检查全部已配置的平台与订阅入口。失败来源保留缓存；完整看板的「信息源」显示逐源状态。")
                HStack {
                    Button(action: openDashboard) { Label("打开完整看板", systemImage: "macwindow") }.buttonStyle(.borderless).font(.system(size: 14, weight: .medium))
                    Spacer()
                    Button("全部已读") { store.markAllRead() }.buttonStyle(.borderless).font(.system(size: 12)).foregroundStyle(.secondary)
                    Menu { Button("退出 AI 资讯") { NSApplication.shared.terminate(nil) } } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 24)
                }.padding(.top, 3)
            }.padding(.horizontal, 17).padding(.vertical, 12)
            }
        }.frame(width: 460, height: 680).background(Color(nsColor: .windowBackgroundColor))
    }

    private func filter(_ title: String, _ value: String) -> some View {
        Button { store.filter = value } label: {
            Text(title).font(.system(size: 12, weight: store.filter == value ? .semibold : .regular))
                .padding(.horizontal, 11).padding(.vertical, 6)
                .foregroundStyle(store.filter == value ? Color.white : Color.primary.opacity(0.65))
                .background(store.filter == value ? Color.indigo : Color.primary.opacity(0.04), in: Capsule())
        }.buttonStyle(.plain)
    }
    private func banner(_ value: String, color: Color) -> some View {
        Text(value).font(.system(size: 12)).foregroundStyle(color).frame(maxWidth: .infinity, alignment: .leading).padding(10).background(color.opacity(0.07))
    }
    private func newsRow(_ item: NewsItem) -> some View {
        let rating = store.rating(for: item)
        let read = store.isRead(item)
        let key = item.presentationID
        let event = item.event.flatMap { $0.articleCount > 1 ? $0 : nil }
        let newsTime = item.newsTime()
        let priority = store.priority(for: item)
        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        if !read { Circle().fill(Color.indigo).frame(width: 5, height: 5) }
                        Text(event == nil ? item.source : "事件追踪").lineLimit(1)
                        Text("· \(event.flatMap { parseDate($0.latestAt) }.map { "最新报道 " + beijingTimeLabel(date:$0) } ?? newsTime.label)").lineLimit(1).help(event == nil ? newsTime.explanation : "事件内最新报道时间，北京时间。各家原文均保留在展开内容中。")
                    }.font(.system(size: 11)).foregroundStyle(.secondary)
                    Button {
                        if event != nil { toggle(item); return }
                        guard let url = item.safeURL else { return }
                        store.markRead(item); NSWorkspace.shared.open(url)
                    } label: {
                        Text(store.title(for: item)).font(.system(size: 14, weight: .medium)).lineSpacing(3).lineLimit(3)
                            .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(read ? Color.secondary : Color.primary)
                    }.buttonStyle(.plain).help(event == nil ? "在默认浏览器阅读原文" : "展开事件重点与各家媒体关注点")
                    if let event {
                        Label(event.label + (event.coverage == nil && event.bonus > 0 ? " · +\(String(format:"%.1f",event.bonus))" : ""),systemImage:event.isWidelyCovered ? "flame.fill" : "square.stack")
                            .font(.system(size:11,weight:.semibold)).foregroundStyle(event.isWidelyCovered ? Color.orange : Color.secondary)
                            .padding(.horizontal,7).padding(.vertical,4)
                            .background((event.isWidelyCovered ? Color.orange : Color.secondary).opacity(0.09),in:RoundedRectangle(cornerRadius:5))
                            .help(NewsEvents.method)
                    }
                    if !priority.reasons.isEmpty {
                        Text(priority.reasons.prefix(2).joined(separator: " · "))
                            .font(.system(size: 10, weight: .medium)).foregroundStyle(.orange).lineLimit(1)
                            .help(Priority.method + "\n本条：" + priority.reasons.joined(separator: "；") + (priority.provisional ? "。升级幅度尚待原文核验。" : ""))
                    }
                    Group {
                        HStack(spacing: 6) { ForEach(Array(([rating.categoryLabel] + rating.tags).prefix(4)), id: \.self) { tag in
                            Text(tag).font(.system(size: 10)).foregroundStyle(.indigo).padding(.horizontal, 5).padding(.vertical, 3).background(Color.indigo.opacity(0.07), in: RoundedRectangle(cornerRadius: 4))
                        } }
                    }
                }
                Button { toggle(item) } label: {
                    VStack(spacing: 2) {
                        Text(rating.displayScore).font(.system(size: 21, weight: .bold, design: .rounded)).monospacedDigit()
                        Text(rating.scoreLabel).font(.system(size: 10))
                    }.foregroundStyle(rating.sortScore >= 7 ? Color.indigo : Color.secondary).frame(width: 56, height: 53)
                        .background((rating.sortScore >= 7 ? Color.indigo : Color.secondary).opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain).help("\(rating.isInterest ? "关注分按你的标准直接计算。" : "")证据 \(rating.statusLabel)：\(rating.evidenceExplanation)\n点击\(rating.sortScore >= 7 ? "展开中文重点" : "查看评分理由")").accessibilityLabel("\(rating.displayScore)，\(rating.scoreLabel)，\(rating.sortScore >= 7 ? "展开重点" : "查看评分依据")")
            }
            if rating.sortScore >= 7 || event != nil {
                Button { toggle(item) } label: {
                    Label(expanded == key ? "收起重点" : event == nil ? "展开重点" : "展开重点分析", systemImage: expanded == key ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.indigo)
                }.buttonStyle(.plain)
            }
            if expanded == key {
                VStack(alignment: .leading, spacing: 6) {
                    if let event {
                        if let coverage = event.coverage, coverage.minimumScore > 0 { CoverageOverview(coverage:coverage) }
                        if rating.briefBasis == "official-context", let points = rating.highlights {
                            Text("官方发布重点 · 按官网宣称").font(.system(size:13,weight:.semibold))
                            ForEach(Array(points.enumerated()),id:\.offset) { _,point in
                                Text("• " + point).font(.system(size:12)).lineSpacing(3).fixedSize(horizontal:false,vertical:true)
                            }
                            if let source = rating.sources?.first(where: { $0.title.contains("官方发布说明") }), let url = publicArticleURL(source.url) {
                                Link("官方发布说明 ↗",destination:url).font(.system(size:12))
                            }
                        }
                        EventBrief(event:event) { article in
                            guard let url = publicArticleURL(article.url) else { return }
                            store.markRead(item); NSWorkspace.shared.open(url)
                        }
                        Button(showEvidence.contains(key) ? "收起评分依据" : "评分依据") {
                            if showEvidence.contains(key) { showEvidence.remove(key) } else { showEvidence.insert(key) }
                        }.buttonStyle(.borderless).font(.system(size:12))
                    } else if rating.sortScore >= 7 {
                        Text(rating.briefBasis == "headline" ? "标题要点" : rating.briefBasis == "official-context" ? "官方发布重点 · 按官网宣称" : "新闻重点").font(.system(size: 13, weight: .semibold))
                        if let points = rating.highlights, !points.isEmpty {
                            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                                Text("• " + point).font(.system(size: 12)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                            }
                        } else {
                            Text("中文重点尚未补充，可先查看已有依据或阅读原文。").font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        if rating.releaseBonus > 0, let release = rating.release, let base = rating.baseScore {
                            Text("发布优先 +1.0 · 基础分 \(String(format: "%.1f", base))\n" + release.reason)
                                .font(.system(size: 11)).foregroundStyle(.indigo).fixedSize(horizontal: false, vertical: true)
                        }
                        HStack {
                            if let source = rating.sources?.first, let url = publicArticleURL(source.url) { Link("阅读依据原文 ↗", destination: url).font(.system(size: 12)) }
                            Spacer()
                            Button(showEvidence.contains(key) ? "收起评分依据" : "评分依据") {
                                if showEvidence.contains(key) { showEvidence.remove(key) } else { showEvidence.insert(key) }
                            }.buttonStyle(.borderless).font(.system(size: 12))
                        }.padding(.top, 4)
                    }
                    if (rating.sortScore < 7 && event == nil) || showEvidence.contains(key) {
                    if let event, let coverage = event.coverage, coverage.minimumScore > 0 {
                        Text("集中报道至少 \(String(format:"%.1f",coverage.minimumScore)) 分；内容关注分 \(event.baseScore.map { String(format:"%.1f",$0) } ?? "尚未计算")；取较高值 = \(rating.displayScore)")
                            .font(.system(size:12,weight:.medium)).foregroundStyle(.orange)
                    } else if let event, let base = event.baseScore, event.bonus > 0 {
                        Text("基础关注分 \(String(format:"%.1f",base)) + 媒体关注 \(String(format:"%.1f",event.bonus)) = \(rating.displayScore)（10 分封顶）")
                            .font(.system(size:12,weight:.medium)).foregroundStyle(.orange)
                    }
                    Text("证据 \(rating.statusLabel) · \(rating.evidenceExplanation)").font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text(rating.reason).font(.system(size: 12)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                    if let dimensions = rating.dimensions, !dimensions.isEmpty {
                        ForEach(dimensions, id: \.key) { dimension in
                            let name = InterestScore.names[dimension.key] ?? Scoring.keys.firstIndex(of:dimension.key).map { Scoring.names[$0] } ?? dimension.key
                            Text("\(name) \(String(format: "%.1f", dimension.value))/5\(dimension.weight.map { " · 权重 \(Int($0))" } ?? "") · \(dimension.reason)").font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if let comparison = rating.comparison, !comparison.isEmpty { Text("相对变化：" + comparison).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true) }
                    if let sources = rating.sources {
                        ForEach(Array(sources.enumerated()), id: \.offset) { _, source in
                            if let url = publicArticleURL(source.url) { Link("依据 · " + source.title, destination: url).font(.system(size: 11)).lineLimit(2) }
                        }
                    }
                    if let gaps = rating.gaps, !gaps.isEmpty { Text("待确认：" + gaps.joined(separator: "；")).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                    if let model = rating.model { Text("评估方式：\(model)").font(.system(size: 11)).foregroundStyle(.secondary) }
                    }
                }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Color.indigo.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            }
        }.padding(.horizontal, 17).padding(.vertical, 13)
    }
    private func toggle(_ item:NewsItem) {
        if expanded == item.presentationID { expanded = nil }
        else { expanded = item.presentationID; store.markRead(item) }
    }
}

struct SettingsContent: View {
    @ObservedObject var store: NewsStore
    var close: () -> Void
    @State private var draft: Preferences
    @State private var watchlistText: String
    @State private var key = ""
    @State private var keyChanged = false
    @State private var error: String?
    init(store: NewsStore, close: @escaping () -> Void) {
        self.store = store; self.close = close; _draft = State(initialValue: store.preferences)
        _watchlistText = State(initialValue: (store.preferences.watchedProducts ?? Priority.defaultWatchlist).joined(separator: ", "))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("更新与评分").font(.system(size: 21, weight: .bold)); Spacer(); Button("关闭", action: close).keyboardShortcut(.cancelAction) }
            ScrollView {
            VStack(alignment: .leading, spacing: 18) {
            GroupBox {
                VStack(alignment: .leading, spacing: 13) {
                    Picker("检查更新", selection: $draft.refreshMinutes) { Text("每 5 分钟").tag(5); Text("每 15 分钟").tag(15); Text("每 30 分钟").tag(30); Text("每小时").tag(60) }
                    Toggle("菜单栏仅显示闪光符号", isOn: $draft.compactTitle)
                    Text("点开符号即可预览消息和评分。关闭此项后，菜单栏会显示新闻标题及分数。应用运行时持续检查；退出应用后停止。")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Text("每轮由本机直接采集资讯平台、RSS 和官方博客，不再等待第三方 JSON 快照。各来源的成功、失败、最近发布时间可在「信息源」查看；来源自身停更时会保留其原有发布时间。")
                        .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    TextField("关注产品，用逗号分隔", text: $watchlistText).textFieldStyle(.roundedBorder)
                    Text(Priority.method).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(8)
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("可选：用 AI 补充正文分析", isOn: $draft.aiEnabled)
                    Text("关注分始终按你的标准立即计算，无需 API。高分消息先显示标题要点；此选项用于补充更完整的中文重点和原文分析，不会挡住评分。")
                        .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    TextField("API Base URL（兼容 Chat Completions，含 /v1 如需）", text: $draft.apiBaseURL).textFieldStyle(.roundedBorder)
                    TextField("模型名称", text: $draft.model).textFieldStyle(.roundedBorder)
                    SecureField("API Key（留空保留已保存的密钥）", text: $key).textFieldStyle(.roundedBorder).onChange(of: key) { _ in keyChanged = true }
                    Text("密钥保存在 macOS 钥匙串。启用后每轮最多分析今天的 5 条，向所配模型发送公开新闻、正文与对照片段，可能产生费用。分析失败仍保留关注分。未翻译的高分公开标题会通过原项目使用的 Google 翻译服务分批翻译，每轮最多 5 条。")
                        .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(8)
            }
            }
            }
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(.red) }
            HStack {
                Link("原项目 · MIT", destination: URL(string: "https://github.com/SuYxh/ai-news-aggregator")!).font(.system(size: 12))
                Spacer()
                Button("保存设置") {
                    draft.watchedProducts = watchlistText.components(separatedBy: CharacterSet(charactersIn: ",，\n")).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                    do { try store.save(draft, key: keyChanged ? key : nil); close() } catch { self.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent).tint(.indigo).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 560).background(Color(nsColor: .windowBackgroundColor))
    }
}
