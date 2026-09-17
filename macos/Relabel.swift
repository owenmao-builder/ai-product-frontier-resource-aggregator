import Foundation

@main
struct RelabelNews {
    @MainActor static func main() async throws {
        let args = CommandLine.arguments
        if args.count == 4 && args[1] == "fetch" {
            struct Request: Codable { var url: String; var title: String }
            let requests = try JSONDecoder().decode([Request].self, from: Data(contentsOf: URL(fileURLWithPath: args[2])))
            let docs = await withTaskGroup(of: ArticleDocument.self) { group -> [ArticleDocument] in
                var iterator = requests.makeIterator()
                for _ in 0..<4 { if let r = iterator.next() { group.addTask { await ArticleDocument.fetch(url: r.url, title: r.title) } } }
                var values: [ArticleDocument] = []
                for await doc in group {
                    values.append(doc)
                    print("\(doc.readable ? "READ" : "PENDING") \(doc.text.count) \(doc.url)")
                    if let r = iterator.next() { group.addTask { await ArticleDocument.fetch(url: r.url, title: r.title) } }
                }
                return values
            }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(docs).write(to: URL(fileURLWithPath: args[3]), options: .atomic)
            return
        }
        guard args.count == 5 && args[1] == "export" else { print("relabel fetch requests.json documents.json | relabel export source-directory archive.json output-directory"); return }
        let source = URL(fileURLWithPath: args[2]); let out = URL(fileURLWithPath: args[4])
        let archive = try JSONDecoder().decode(ReviewedArchive.self, from: Data(contentsOf: URL(fileURLWithPath: args[3])))
        let reviewed = Dictionary(archive.entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        for range in ["24h", "7d"] {
            var snapshot = try NewsStore.decode(Data(contentsOf: source.appendingPathComponent("latest-\(range).json")))
            snapshot.items = snapshot.items.map { item in
                var value = item
                if let saved = reviewed[item.id], saved.fingerprint == Scoring.fingerprint(item), let valid = Scoring.validated(saved.rating) { value.rating = valid }
                else { value.rating = Scoring.rule(item) }
                return value
            }
            try encoder.encode(snapshot).write(to: out.appendingPathComponent("latest-\(range).json"), options: .atomic)
            let assessed = snapshot.items.filter { $0.rating?.isScored == true }.count
            print("\(range): total=\(snapshot.items.count), assessed=\(assessed), pending=\(snapshot.items.count - assessed)")
            print(Dictionary(grouping: snapshot.items, by: { $0.rating?.categoryLabel ?? "?" }).mapValues(\.count))
        }
    }
}
