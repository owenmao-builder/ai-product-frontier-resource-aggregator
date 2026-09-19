import SwiftUI

struct CoverageOverview: View {
    var coverage: CoverageSignal
    var body: some View {
        VStack(alignment:.leading,spacing:5) {
            Label(coverage.label,systemImage:"flame.fill").font(.system(size:13,weight:.semibold)).foregroundStyle(.orange)
            Text(coverage.explanation).font(.system(size:12)).fixedSize(horizontal:false,vertical:true)
            Text("计入来源：" + coverage.sourceNames.joined(separator:"、"))
                .font(.system(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }.padding(9).frame(maxWidth:.infinity,alignment:.leading)
            .background(Color.orange.opacity(0.06),in:RoundedRectangle(cornerRadius:6))
    }
}

struct EventBrief: View {
    var event: NewsEvent
    var open: (EventArticle) -> Void
    private let kinds = ["media":"媒体","official":"官方","community":"作者/社区","aggregator":"聚合平台"]
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            Text("核心分析").font(.system(size:13,weight:.semibold))
            ForEach(Array(event.insights.enumerated()),id:\.offset) { _,insight in
                VStack(alignment:.leading,spacing:3) {
                    Text(insight.title).font(.system(size:12,weight:.semibold)).foregroundStyle(.indigo)
                    Text(insight.text).font(.system(size:12)).lineSpacing(3).fixedSize(horizontal:false,vertical:true)
                }
            }
            Text("各家关注点").font(.system(size:13,weight:.semibold)).padding(.top,4)
            ForEach(Array(event.reports.prefix(4))) { report in reportView(report) }
            if event.reports.count > 4 {
                DisclosureGroup("其余 \(event.reports.count - 4) 家来源") {
                    ForEach(Array(event.reports.dropFirst(4))) { report in reportView(report).padding(.top,8) }
                }.font(.system(size:12))
            }
            Text("根据各家标题、摘录或已有分析归纳；报道数量表示关注热度。")
                .font(.system(size:10)).foregroundStyle(.secondary)
        }
    }
    private func reportView(_ report:EventReport) -> some View {
        VStack(alignment:.leading,spacing:5) {
            HStack(alignment:.firstTextBaseline) {
                Text(report.name).font(.system(size:12,weight:.semibold))
                Text(kinds[report.kind] ?? "来源").font(.system(size:10)).foregroundStyle(.secondary)
                if event.coverage?.sourceIDs.contains(report.id) == true {
                    Text("计入热度").font(.system(size:10)).foregroundStyle(.orange)
                }
                Spacer()
                Text(report.basis).font(.system(size:10)).foregroundStyle(.secondary)
            }
            if !report.focus.isEmpty {
                Text(report.focus.joined(separator:" · ")).font(.system(size:11,weight:.medium)).foregroundStyle(.orange)
            }
            ForEach(Array(report.points.enumerated()),id:\.offset) { _,point in
                Text("• " + point).font(.system(size:12)).lineSpacing(2).fixedSize(horizontal:false,vertical:true)
            }
            ForEach(report.articles,id:\.id) { article in
                Button { open(article) } label: {
                    Text("原文 ↗ " + article.title).font(.system(size:11)).lineLimit(2).multilineTextAlignment(.leading)
                }.buttonStyle(.borderless)
            }
        }.padding(9).frame(maxWidth:.infinity,alignment:.leading)
            .background(Color.primary.opacity(0.025),in:RoundedRectangle(cornerRadius:6))
    }
}
