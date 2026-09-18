import Foundation

struct CollectionSource: Codable {
    var id: String
    var name: String
    var kind: String
    var url: String?
    var ok: Bool
    var checked_at: String
    var fetched_at: String?
    var latest_published_at: String?
    var item_count: Int
    var error: String?
    var skipped: Bool?
}

struct CollectionStatus: Codable {
    var mode: String
    var started_at: String
    var finished_at: String
    var sources: [CollectionSource]
    var label: String {
        let succeeded = sources.filter(\.ok).count
        return "本机采集 \(succeeded)/\(sources.count) 源成功 · \(beijingTimeLabel(date: parseDate(finished_at)))"
    }
    var failures: Int { sources.filter { !$0.ok }.count }
}

// Runs the bundled collector without depending on Homebrew, a terminal PATH or a remote snapshot host.
@MainActor
final class LocalCollector {
    private var process: Process?
    func cancel() { if let process, process.isRunning { process.terminate() }; process = nil }

    func collect(directory: URL, seed: [NewsItem]) async throws -> [NewsData] {
        guard process == nil else { throw NewsError.message("资讯采集正在运行") }
        guard let resources = Bundle.main.resourceURL else { throw NewsError.message("采集器资源缺失") }
        let executable = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/node")
        let script = resources.appendingPathComponent("collector/desktop.mjs")
        guard FileManager.default.isExecutableFile(atPath: executable.path), FileManager.default.fileExists(atPath: script.path) else {
            throw NewsError.message("内置采集器缺失，请重新安装完整应用")
        }
        let output = directory.appendingPathComponent("collector", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        struct Seed: Encodable { var items: [NewsItem] }
        let seedURL = output.appendingPathComponent("seed.json")
        try JSONEncoder().encode(Seed(items: seed)).write(to: seedURL, options: .atomic)
        let logURL = output.appendingPathComponent("latest-run.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let log = try FileHandle(forWritingTo: logURL)
        let task = Process()
        task.executableURL = executable
        task.arguments = ["--max-old-space-size=384", script.path, "--output-dir", output.path,
            "--catalog", resources.appendingPathComponent("web/data/opml-feeds.json").path, "--seed", seedURL.path]
        task.currentDirectoryURL = resources
        task.environment = ["HOME": FileManager.default.homeDirectoryForCurrentUser.path, "PATH": "/usr/bin:/bin", "TZ": "Asia/Shanghai", "LANG": "en_US.UTF-8"]
        task.standardOutput = log; task.standardError = log
        process = task
        let timeout = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 240_000_000_000)
            if !Task.isCancelled && task.isRunning { task.terminate() }
        }
        defer { timeout.cancel(); try? log.close(); process = nil }
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            task.terminationHandler = { process in continuation.resume(returning: process.terminationStatus) }
            do { try task.run() } catch { task.terminationHandler = nil; continuation.resume(throwing: error) }
        }
        guard status == 0 else { throw NewsError.message("本机采集未完成，保留上次内容；请稍后刷新") }
        struct Result: Decodable { var snapshots: [NewsData] }
        let bytes = try Data(contentsOf: output.appendingPathComponent("result.json"))
        guard bytes.count <= 40_000_000 else { throw NewsError.message("采集结果过大") }
        let snapshots = try JSONDecoder().decode(Result.self, from: bytes).snapshots
        guard snapshots.count == 2, snapshots.allSatisfy({ $0.collection?.mode == "local" && parseDate($0.generated_at) != nil }) else {
            throw NewsError.message("采集结果无效，保留上次内容")
        }
        return snapshots
    }
}
