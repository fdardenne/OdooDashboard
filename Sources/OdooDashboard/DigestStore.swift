import Foundation

/// The digest "mailbox" -- every DigestEntry ever generated, newest first,
/// persisted to disk so past issues stay browsable across app restarts.
enum DigestStore {
    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    static func load() -> [DigestEntry] {
        guard let data = try? Data(contentsOf: Config.digestsPath),
              let entries = try? makeDecoder().decode([DigestEntry].self, from: data) else { return [] }
        return entries.sorted { $0.generatedAt > $1.generatedAt }
    }

    /// Prepends a freshly-generated entry and persists the whole mailbox.
    static func append(_ entry: DigestEntry) {
        var entries = load()
        entries.insert(entry, at: 0)
        guard let data = try? makeEncoder().encode(entries) else { return }
        try? FileManager.default.createDirectory(at: Config.dataDir, withIntermediateDirectories: true)
        let tmp = Config.digestsPath.appendingPathExtension("tmp")
        try? data.write(to: tmp)
        _ = try? FileManager.default.replaceItemAt(Config.digestsPath, withItemAt: tmp)
    }

    /// Wipes the whole mailbox -- the next consult() starts over as if it
    /// were the very first time (a 7-day window).
    static func clear() {
        try? FileManager.default.removeItem(at: Config.digestsPath)
    }
}
