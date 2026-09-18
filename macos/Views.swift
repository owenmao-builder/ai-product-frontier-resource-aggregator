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
                    Text(store.section == "products" ? "\(store.productBoard.items.count) 款产品 · \(store.productBoard.items.filter(\.isHot).count) 款近期热门" : store.filter == "today" ? "今天 \(store.todayItems.count) 条 · \(store.todayItems.filter { store.rating(for: $0).sortScore >= 7 }.count) 条重点" : "\(store.items.count) 条资讯 · \(store.assessedCount) 条已评估").font(.system(size: 12)).foregroundStyle(.secondary)
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
                filter("待评估", "pending")
                filter("未读", "unread")
                Spacer()
                Text("重要度 ↓").font(.system(size: 12)).foregroundStyle(.secondary)
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
                    ForEach(Array(store.visible.prefix(40))) { item in
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
                    Text(Scoring.rubric + " A：关键判断有充分直接材料；B：有原文但仍存在未核实部分；C：材料不足。")
                        .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Text(store.directRefreshLabel)
                    Spacer()
                    Text("每 \(store.preferences.refreshMinutes) 分钟直采")
                }.font(.system(size: 12)).foregroundStyle(.secondary)
                Text("\(store.snapshotLabel) · 北京时间")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .help("原站订阅直接抓取最新消息；其余聚合平台随上游快照更新。检查成功不代表上游发布了新快照。")
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
        let read = store.seen.contains(item.url)
        let newsTime = item.newsTime()
        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        if !read { Circle().fill(Color.indigo).frame(width: 5, height: 5) }
                        Text(item.source).lineLimit(1)
                        Text("· \(newsTime.label)").lineLimit(1).help(newsTime.explanation)
                    }.font(.system(size: 11)).foregroundStyle(.secondary)
                    Button {
                        guard let url = item.safeURL else { return }
                        store.markRead(item); NSWorkspace.shared.open(url)
                    } label: {
                        Text(store.title(for: item)).font(.system(size: 14, weight: .medium)).lineSpacing(3).lineLimit(3)
                            .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(read ? Color.secondary : Color.primary)
                    }.buttonStyle(.plain).help("在默认浏览器阅读原文")
                    Group {
                        HStack(spacing: 6) { ForEach(Array(([rating.categoryLabel] + rating.tags).prefix(3)), id: \.self) { tag in
                            Text(tag).font(.system(size: 10)).foregroundStyle(.indigo).padding(.horizontal, 5).padding(.vertical, 3).background(Color.indigo.opacity(0.07), in: RoundedRectangle(cornerRadius: 4))
                        } }
                    }
                }
                Button { expanded = expanded == item.id ? nil : item.id } label: {
                    VStack(spacing: 2) {
                        Text(rating.displayScore).font(.system(size: 21, weight: .bold, design: .rounded)).monospacedDigit()
                        Text(rating.statusLabel).font(.system(size: 10))
                    }.foregroundStyle(rating.sortScore >= 7 ? Color.indigo : Color.secondary).frame(width: 56, height: 53)
                        .background((rating.sortScore >= 7 ? Color.indigo : Color.secondary).opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain).help("证据 \(rating.statusLabel)：\(rating.evidenceExplanation)\n点击\(rating.sortScore >= 7 ? "展开中文重点" : "查看评分理由")").accessibilityLabel("\(rating.displayScore)，证据 \(rating.statusLabel)，\(rating.sortScore >= 7 ? "展开重点" : "查看评估依据")")
            }
            if rating.sortScore >= 7 {
                Button { expanded = expanded == item.id ? nil : item.id } label: {
                    Label(expanded == item.id ? "收起重点" : "展开重点", systemImage: expanded == item.id ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.indigo)
                }.buttonStyle(.plain)
            }
            if expanded == item.id {
                VStack(alignment: .leading, spacing: 6) {
                    if rating.sortScore >= 7 {
                        Text("新闻重点").font(.system(size: 13, weight: .semibold))
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
                            Button(showEvidence.contains(item.id) ? "收起评分依据" : "评分依据") {
                                if showEvidence.contains(item.id) { showEvidence.remove(item.id) } else { showEvidence.insert(item.id) }
                            }.buttonStyle(.borderless).font(.system(size: 12))
                        }.padding(.top, 4)
                    }
                    if rating.sortScore < 7 || showEvidence.contains(item.id) {
                    Text("证据 \(rating.statusLabel) · \(rating.evidenceExplanation)").font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text(rating.reason).font(.system(size: 12)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                    if let dimensions = rating.dimensions, !dimensions.isEmpty {
                        ForEach(Scoring.keys.indices, id: \.self) { index in
                            if let dimension = dimensions.first(where: { $0.key == Scoring.keys[index] }) {
                                Text("\(Scoring.names[index]) \(String(format: "%.0f", dimension.value))/5 · \(dimension.reason)").font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                            }
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
}

struct SettingsContent: View {
    @ObservedObject var store: NewsStore
    var close: () -> Void
    @State private var draft: Preferences
    @State private var key = ""
    @State private var keyChanged = false
    @State private var error: String?
    init(store: NewsStore, close: @escaping () -> Void) {
        self.store = store; self.close = close; _draft = State(initialValue: store.preferences)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("更新与评分").font(.system(size: 21, weight: .bold)); Spacer(); Button("关闭", action: close).keyboardShortcut(.cancelAction) }
            GroupBox {
                VStack(alignment: .leading, spacing: 13) {
                    Picker("检查更新", selection: $draft.refreshMinutes) { Text("每 5 分钟").tag(5); Text("每 15 分钟").tag(15); Text("每 30 分钟").tag(30); Text("每小时").tag(60) }
                    Toggle("菜单栏仅显示闪光符号", isOn: $draft.compactTitle)
                    Text("点开符号即可预览消息和评分。关闭此项后，菜单栏会显示新闻标题及分数。应用运行时持续检查；退出应用后停止。")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    TextField("资讯数据目录（HTTPS）", text: $draft.dataBaseURL).textFieldStyle(.roundedBorder)
                    Text("上方频率控制官方博客、新智元和苔藓之火等原站订阅的直接抓取。此地址提供补充聚合内容，更新时间由上游决定；各来源的检查时间、发布情况与失败原因可在「信息源」查看。")
                        .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(8)
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("自动读取正文并使用 AI 评估", isOn: $draft.aiEnabled)
                    Text("按类型评估；官方大厂新模型或新架构发布加 1 分。7 分及以上生成中文标题和重点。默认仅处理今天的消息，保留历史结果。")
                        .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    TextField("API Base URL（兼容 Chat Completions，含 /v1 如需）", text: $draft.apiBaseURL).textFieldStyle(.roundedBorder)
                    TextField("模型名称", text: $draft.model).textFieldStyle(.roundedBorder)
                    SecureField("API Key（留空保留已保存的密钥）", text: $key).textFieldStyle(.roundedBorder).onChange(of: key) { _ in keyChanged = true }
                    Text("密钥保存在 macOS 钥匙串。启用后每轮最多评估今天的 5 条，向所配模型发送新闻、公开原文和可用历史对照片段，可能产生费用。读不到正文或依据不完整时保留待评估。")
                        .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(8)
            }
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(.red) }
            HStack {
                Link("原项目 · MIT", destination: URL(string: "https://github.com/SuYxh/ai-news-aggregator")!).font(.system(size: 12))
                Spacer()
                Button("保存设置") {
                    do { try store.save(draft, key: keyChanged ? key : nil); close() } catch { self.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent).tint(.indigo).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 560).background(Color(nsColor: .windowBackgroundColor))
    }
}
