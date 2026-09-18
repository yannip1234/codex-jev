import Foundation

/// Recovery records are evidence of prepared reductions, not a token-savings counter.
struct CompressionStatus: Equatable {
    var toolRecords = 0
    var historyRecords = 0
    var unavailable = false

    static func read(home: URL) -> CompressionStatus {
        let directory = home.appendingPathComponent("jev-originals")
        guard FileManager.default.fileExists(atPath: directory.path) else { return CompressionStatus() }
        do {
            let metadata = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard metadata.isDirectory == true, metadata.isSymbolicLink != true else {
                return CompressionStatus(unavailable: true)
            }
            let files = try FileManager.default.contentsOfDirectory(at: directory,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
            var status = CompressionStatus()
            for file in files {
                let name = file.deletingPathExtension().lastPathComponent
                guard file.pathExtension == "txt", let separator = name.firstIndex(of: "-"),
                      UUID(uuidString: String(name[name.index(after: separator)...])) != nil else { continue }
                let kind = name[..<separator]
                guard kind == "tool" || kind == "history" else { continue }
                let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
                if kind == "tool" { status.toolRecords += 1 } else { status.historyRecords += 1 }
            }
            return status
        } catch {
            return CompressionStatus(unavailable: true)
        }
    }
}
