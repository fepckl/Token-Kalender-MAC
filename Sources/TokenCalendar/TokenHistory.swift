import Foundation

struct DayUsage {
    var input = 0
    var output = 0
    var cacheWrite = 0
    var cacheRead = 0
    var messages = 0
    var byModel: [String: Int] = [:]

    func total(includeCacheReads: Bool) -> Int {
        input + output + cacheWrite + (includeCacheReads ? cacheRead : 0)
    }
}

struct TokenHistoryResult {
    var days: [Date: DayUsage] = [:]
    var files = 0
    var messages = 0
    var directories: [URL] = []
}

/// Builds a per-day token history from Claude Code's local transcripts
/// (~/.claude/projects/**/*.jsonl). The usage API only knows the current
/// windows, so this is the only source for historical numbers.
enum TokenHistory {
    /// Claude Code honours CLAUDE_CONFIG_DIR (comma-separated); newer versions
    /// default to ~/.config/claude, older ones to ~/.claude.
    static var projectDirectories: [URL] {
        let fm = FileManager.default
        var candidates: [URL] = []
        if let env = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !env.isEmpty {
            for part in env.split(separator: ",") {
                let path = part.trimmingCharacters(in: .whitespaces)
                candidates.append(URL(fileURLWithPath: path).appendingPathComponent("projects"))
            }
        }
        let home = fm.homeDirectoryForCurrentUser
        candidates.append(home.appendingPathComponent(".config/claude/projects"))
        candidates.append(home.appendingPathComponent(".claude/projects"))

        var seen = Set<String>()
        return candidates.filter { url in
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return false }
            return seen.insert(url.resolvingSymlinksInPath().path).inserted
        }
    }

    // Only the fields we need — JSONDecoder skips everything else.
    private struct Line: Decodable {
        let timestamp: String?
        let requestId: String?
        let message: Message?

        struct Message: Decodable {
            let id: String?
            let model: String?
            let usage: Usage?
        }

        struct Usage: Decodable {
            let input_tokens: Int?
            let output_tokens: Int?
            let cache_creation_input_tokens: Int?
            let cache_read_input_tokens: Int?
        }
    }

    private struct Entry {
        var day: Date
        var model: String
        var input: Int
        var output: Int
        var cacheWrite: Int
        var cacheRead: Int
    }

    /// Blocking — call from a background task.
    static func load() -> TokenHistoryResult {
        var result = TokenHistoryResult()
        result.directories = projectDirectories

        // Claude Code writes one line per content block, each repeating the same
        // usage object; resumed sessions also copy earlier messages into new files.
        // Dedupe on message id + request id, as ccusage does.
        var unique: [String: Entry] = [:]
        var anonymous: [Entry] = []

        let decoder = JSONDecoder()
        let isoFractional = ISO8601DateFormatter()
        isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        let calendar = Calendar.current

        // Cheap byte-level prefilter: lines can be megabytes long (tool output),
        // so only assistant lines carrying usage are handed to the decoder.
        let assistantMarker = Data("\"type\":\"assistant\"".utf8)
        let usageMarker = Data("\"usage\":{".utf8)
        let newline = UInt8(ascii: "\n")

        for dir in result.directories {
            guard let walker = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker where url.pathExtension == "jsonl" {
                result.files += 1
                guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { continue }

                for slice in data.split(separator: newline, omittingEmptySubsequences: true) {
                    guard slice.range(of: assistantMarker) != nil, slice.range(of: usageMarker) != nil else { continue }
                    guard let line = try? decoder.decode(Line.self, from: Data(slice)),
                          let message = line.message,
                          let usage = message.usage,
                          let ts = line.timestamp,
                          let date = isoFractional.date(from: ts) ?? isoPlain.date(from: ts) else { continue }

                    let model = message.model ?? "unknown"
                    if model == "<synthetic>" { continue }   // locally generated, not billed

                    let entry = Entry(
                        day: calendar.startOfDay(for: date),
                        model: model,
                        input: usage.input_tokens ?? 0,
                        output: usage.output_tokens ?? 0,
                        cacheWrite: usage.cache_creation_input_tokens ?? 0,
                        cacheRead: usage.cache_read_input_tokens ?? 0
                    )
                    if entry.input + entry.output + entry.cacheWrite + entry.cacheRead == 0 { continue }

                    if let id = message.id {
                        let key = id + ":" + (line.requestId ?? "")
                        if let existing = unique[key], existing.output >= entry.output { continue }
                        unique[key] = entry
                    } else {
                        anonymous.append(entry)
                    }
                }
            }
        }

        for entry in unique.values { add(entry, to: &result) }
        for entry in anonymous { add(entry, to: &result) }
        return result
    }

    private static func add(_ e: Entry, to result: inout TokenHistoryResult) {
        var day = result.days[e.day] ?? DayUsage()
        day.input += e.input
        day.output += e.output
        day.cacheWrite += e.cacheWrite
        day.cacheRead += e.cacheRead
        day.messages += 1
        day.byModel[e.model, default: 0] += e.input + e.output + e.cacheWrite + e.cacheRead
        result.days[e.day] = day
        result.messages += 1
    }
}
