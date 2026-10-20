import Foundation

/// Local log policy approved on 2026-10-19: keep 7 days, cap each file at 5 MB,
/// and let the user clear logs explicitly. Nothing is uploaded.
public enum LogRetention {
    public struct Policy: Sendable {
        public let maximumAge: TimeInterval
        public let maximumBytes: UInt64
        public init(maximumAge: TimeInterval = 7 * 24 * 60 * 60,
                    maximumBytes: UInt64 = 5 * 1024 * 1024) {
            self.maximumAge = maximumAge
            self.maximumBytes = maximumBytes
        }
    }

    public static let standard = Policy()

    public static func defaultLogFiles(configurationDirectory: URL,
                                       homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        [
            configurationDirectory.appendingPathComponent("automnt.log"),
            homeDirectory.appendingPathComponent("Library/Logs/automnt/stdout.log"),
            homeDirectory.appendingPathComponent("Library/Logs/automnt/stderr.log")
        ]
    }

    public static func enforce(files: [URL], policy: Policy = standard, now: Date = Date()) throws {
        for url in files {
            try trim(fileAt: url, policy: policy, now: now)
        }
    }

    public static func trim(fileAt url: URL, policy: Policy = standard, now: Date = Date()) throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: url.path) else { return }
        let attributes = try manager.attributesOfItem(atPath: url.path)
        if let modified = attributes[.modificationDate] as? Date,
           now.timeIntervalSince(modified) > policy.maximumAge {
            try manager.removeItem(at: url)
            return
        }
        guard let size = (attributes[.size] as? NSNumber)?.uint64Value,
              size > policy.maximumBytes else { return }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: size - policy.maximumBytes)
        var tail = try handle.readToEnd() ?? Data()
        // Start at a line boundary when one exists, so the trimmed file stays readable.
        if let newline = tail.firstIndex(of: 0x0A) {
            tail = tail.dropFirst(newline + 1)
        }
        try tail.write(to: url, options: .atomic)
    }

    public static func clear(files: [URL]) throws {
        for url in files where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
