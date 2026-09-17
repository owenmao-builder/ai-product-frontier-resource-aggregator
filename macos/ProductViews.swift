import SwiftUI

struct ProductMenuContent: View {
    @ObservedObject var store: NewsStore
    var openDashboard: () -> Void
    @State private var filter = "major"
    @State private var query = ""
    @State private var expanded: String?
    @State private var showMethod = false

    private var visible: [AIProduct] {
        store.productBoard.items.filter { product in
            (!product.major || Products.isRecentRelease(product)) && (product.major || product.isHot) &&
            (filter != "major" || product.major) && (filter != "hot" || product.isHot) &&
            (query.isEmpty || [product.name, product.maker, product.category, product.summary].joined(separator: " ").localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索模型、版本或用途", text: $query).textFieldStyle(.plain).font(.system(size: 14))
                if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary) }
            }.padding(9).background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 9)).padding(.horizontal, 16)
            HStack(spacing: 8) {
                tab("全部", "all")
                tab("大厂上新 · 7 天", "major")
                tab("近期热门", "hot")
                Spacer()
                Text("\(visible.count) 款").font(.system(size: 12)).foregroundStyle(.secondary)
            }.padding(.horizontal, 16).padding(.vertical, 12)
            Divider()
            if let errors = store.productBoard.errors, !errors.isEmpty {
                Text(errors.keys.sorted().compactMap { errors[$0] }.joined(separator: " "))
                    .font(.system(size: 11)).foregroundStyle(.orange).padding(10)
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    if visible.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "square.grid.2x2").font(.system(size: 28)).foregroundStyle(.secondary)
                            Text(filter == "hot" ? "暂无符合条件的近期热度" : "暂无符合条件的近 7 天上新").font(.system(size: 14))
                            Button("查看全部产品") { filter = "all"; query = "" }.buttonStyle(.borderless)
                        }.frame(maxWidth: .infinity).padding(.vertical, 55)
                    }
                    ForEach(visible) { product in
                        row(product)
                        Divider().padding(.leading, 17)
                    }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("官方发布日期 · 近 7 天（含今天）").foregroundStyle(.secondary)
                    Spacer()
                    Button("入选依据") { showMethod.toggle() }.buttonStyle(.borderless)
                }.font(.system(size: 11))
                if showMethod { Text(Products.method).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                HStack {
                    Button(action: openDashboard) { Label("打开产品看板", systemImage: "square.grid.2x2") }.buttonStyle(.borderless).font(.system(size: 14, weight: .medium))
                    Spacer()
                    Text("检查 \(timeLabel(store.productBoard.checkedAt))").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 17).padding(.vertical, 12)
        }
    }

    private func tab(_ title: String, _ value: String) -> some View {
        Button { filter = value } label: {
            Text(title).font(.system(size: 12, weight: filter == value ? .semibold : .regular))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .foregroundStyle(filter == value ? Color.white : Color.secondary)
                .background(filter == value ? Color.indigo : Color.primary.opacity(0.04), in: Capsule())
        }.buttonStyle(.plain)
    }

    private func row(_ product: AIProduct) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(product.maker + " · " + product.category).font(.system(size: 11)).foregroundStyle(.secondary)
                    if let url = publicArticleURL(product.homepage) {
                        Link(destination: url) { Text(product.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary) }.help("打开产品官网")
                    }
                }
                Spacer()
                if product.major { Text(product.releaseKind ?? "大厂上新").font(.system(size: 10)).foregroundStyle(.indigo).padding(5).background(Color.indigo.opacity(0.07), in: Capsule()) }
                Button { expanded = expanded == product.id ? nil : product.id } label: {
                    Image(systemName: expanded == product.id ? "chevron.up" : "chevron.down").font(.system(size: 12)).frame(width: 25, height: 25)
                }.buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("\(product.name)的产品重点")
            }
            if let day = product.releasedOn {
                Text("官方发布 " + day).font(.system(size: 11, weight: .medium)).foregroundStyle(.indigo)
            }
            Text(product.summary).font(.system(size: 13)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            if let signal = product.signals?.first {
                Label(signal.label, systemImage: "flame").font(.system(size: 11, weight: .medium)).foregroundStyle(.orange)
            }
            if expanded == product.id {
                VStack(alignment: .leading, spacing: 8) {
                    Text("产品重点").font(.system(size: 12, weight: .semibold))
                    Text(product.difference).font(.system(size: 12)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                    Text("使用方式：" + product.access).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    ForEach(Array((product.signals ?? []).enumerated()), id: \.offset) { _, signal in
                        if let url = publicArticleURL(signal.url) {
                            Link("热度依据 · " + signal.label + " ↗", destination: url).font(.system(size: 11))
                        }
                    }
                    if let news = product.relatedNews?.first, let url = publicArticleURL(news.url) {
                        Link("今日相关 · " + news.title, destination: url).font(.system(size: 11)).lineLimit(3)
                    }
                    if let url = publicArticleURL(product.sourceURL) { Link(product.major ? "官方发布公告 ↗" : "官方产品说明 ↗", destination: url).font(.system(size: 11)) }
                }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Color.indigo.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            }
        }.padding(.horizontal, 17).padding(.vertical, 13)
    }
}
