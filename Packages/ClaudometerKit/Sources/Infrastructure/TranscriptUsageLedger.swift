import Foundation
import Domain

/// `UsageLedger` adapter that computes exact token usage by parsing Claude Code's
/// local session transcripts at `<CLAUDE_CONFIG_DIR>/projects/**/*.jsonl`.
///
/// This is the only source of exact per-account token counts for a Pro/Max
/// subscription: the OAuth usage endpoint exposes only percentages, and the
/// token-count Admin/Analytics APIs reject subscription tokens (HTTP 403). It is
/// also fully local — no network, no rate limit.
///
/// Accuracy notes mirroring how `ccusage` reads the same files:
///  • **Dedup** by `(message.id, requestId)` — Claude Code replays history into
///    resumed sessions, so the same assistant message recurs across files.
///  • Cache-creation tokens are split into 1-hour / 5-minute buckets (they price
///    2× vs 1.25× of input); any unsplit remainder is attributed to 5-minute.
///  • `usage.speed == "fast"` is carried through so Fast-mode pricing applies.
///
/// Performance: files are read and JSON-decoded concurrently (the hot path), then
/// deduped and window-bucketed in a cheap serial merge. Files untouched since
/// before the widest window are skipped entirely.
public struct TranscriptUsageLedger: UsageLedger {
    private let resolver = ConfigAccountResolver()

    public init() {}

    public func entries(for profile: Profile, now: Date) async throws -> [LedgerEntry] {
        let configDirs = resolver.configDirsByShortHash()
        guard let dir = resolver.configDir(forService: profile.id.rawValue, configDirs: configDirs) else {
            return []
        }
        let projects = dir.appendingPathComponent("projects")
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: projects.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return []
        }

        // Window cutoffs as yyyymmdd ints (date-only, inclusive of the cutoff day).
        let cutoffs: [(window: CostWindow, dayInt: Int)] = CostWindow.allCases.map {
            ($0, Self.dayInt(of: now.addingTimeInterval(-Double($0.days) * 86_400)))
        }
        let widest = CostWindow.allCases.map(\.days).max() ?? 30
        let oldestDay = Self.dayInt(of: now.addingTimeInterval(-Double(widest) * 86_400))
        // Skip files untouched since before the widest window — they can hold no
        // in-window entries (a file's mtime is its newest line).
        let fileCutoff = now.addingTimeInterval(-Double(widest) * 86_400)

        // Gather candidate files (cheap, synchronous).
        let resourceKeys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let walker = fm.enumerator(at: projects, includingPropertiesForKeys: resourceKeys) else {
            return []
        }
        var urls: [URL] = []
        while let object = walker.nextObject() {
            guard let url = object as? URL, url.pathExtension == "jsonl" else { continue }
            if let mtime = try? url.resourceValues(forKeys: Set(resourceKeys)).contentModificationDate,
               mtime < fileCutoff {
                continue
            }
            urls.append(url)
        }

        // Read + decode each file concurrently (the expensive part).
        let perFile = await withTaskGroup(of: [Record].self) { group in
            for url in urls {
                group.addTask { Self.parse(url, onOrAfterDay: oldestDay) }
            }
            var collected: [[Record]] = []
            for await records in group { collected.append(records) }
            return collected
        }

        // Merge: global dedup (resumed sessions duplicate records across files),
        // then bucket each record into every window whose span contains its day.
        var seen = Set<String>()
        var accumulator: [Slice: TokenUsage] = [:]
        for records in perFile {
            for record in records {
                if let key = record.dedupKey, !seen.insert(key).inserted { continue }
                for cutoff in cutoffs where record.day >= cutoff.dayInt {
                    let slice = Slice(window: cutoff.window, modelID: record.model, fast: record.fast)
                    accumulator[slice] = (accumulator[slice] ?? .zero) + record.usage
                }
            }
        }

        return accumulator.map {
            LedgerEntry(window: $0.key.window, modelID: $0.key.modelID, fast: $0.key.fast, usage: $0.value)
        }
    }

    // MARK: - Parsing

    /// One decoded assistant record, before dedup/windowing (those need state
    /// shared across files, so they happen in the serial merge).
    private struct Record: Sendable {
        let dedupKey: String?
        let day: Int
        let model: String
        let fast: Bool
        let usage: TokenUsage
    }

    /// Bytes of `"usage"` — a cheap prefilter so we JSON-parse only assistant lines.
    private static let usageNeedle = Data("\"usage\"".utf8)

    private static func parse(_ url: URL, onOrAfterDay oldestDay: Int) -> [Record] {
        guard let fileData = try? Data(contentsOf: url) else { return [] }
        var records: [Record] = []

        // Byte-level split + substring scan; JSON-decode only lines that carry
        // usage — avoids per-line String allocation and Unicode-aware search.
        for lineData in fileData.split(separator: 0x0A, omittingEmptySubsequences: true) {
            guard lineData.range(of: usageNeedle) != nil,
                  let obj = (try? JSONSerialization.jsonObject(with: lineData)) as? [String: Any],
                  let message = obj["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any]
            else { continue }

            guard let timestamp = obj["timestamp"] as? String,
                  let day = dayInt(ofTimestamp: timestamp), day >= oldestDay else { continue }

            let dedupKey: String?
            if let id = message["id"] as? String, let request = obj["requestId"] as? String {
                dedupKey = id + "|" + request
            } else {
                dedupKey = nil
            }

            let model = (message["model"] as? String) ?? "<none>"
            let fast = (usage["speed"] as? String) == "fast"

            let creation = usage["cache_creation"] as? [String: Any]
            let cacheWrite1h = int(creation?["ephemeral_1h_input_tokens"])
            let nested5m = int(creation?["ephemeral_5m_input_tokens"])
            let creationFlat = int(usage["cache_creation_input_tokens"])
            let cacheWrite5m = nested5m + max(0, creationFlat - cacheWrite1h - nested5m)

            records.append(Record(
                dedupKey: dedupKey,
                day: day,
                model: model,
                fast: fast,
                usage: TokenUsage(
                    input: int(usage["input_tokens"]),
                    output: int(usage["output_tokens"]),
                    cacheRead: int(usage["cache_read_input_tokens"]),
                    cacheWrite5m: cacheWrite5m,
                    cacheWrite1h: cacheWrite1h
                )
            ))
        }
        return records
    }

    // MARK: - Helpers

    private struct Slice: Hashable {
        let window: CostWindow
        let modelID: String
        let fast: Bool
    }

    /// Robustly extract an integer from a JSON value (JSONSerialization yields
    /// `NSNumber` for numbers).
    private static func int(_ value: Any?) -> Int {
        switch value {
        case let number as NSNumber: return number.intValue
        case let integer as Int: return integer
        case let double as Double: return Int(double)
        default: return 0
        }
    }

    private static func dayInt(of date: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return (c.year ?? 0) * 10_000 + (c.month ?? 0) * 100 + (c.day ?? 0)
    }

    /// Parse the `YYYY-MM-DD` prefix of an ISO-8601 timestamp into a `yyyymmdd` int.
    private static func dayInt(ofTimestamp timestamp: String) -> Int? {
        let parts = timestamp.prefix(10).split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        return year * 10_000 + month * 100 + day
    }
}
