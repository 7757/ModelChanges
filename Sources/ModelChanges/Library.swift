import Foundation

struct LibrarySnapshot: Codable {
    var models: [LiveModel]
    var fetchedAt: Date
    var sort: String
}

/// Fetches and parses the live model list from ollama.com/library.
enum Library {
    enum Sort: String, CaseIterable, Identifiable {
        case popular, newest
        var id: String { rawValue }
        var label: String { label(language: .english) }
        func label(language: AppLanguage) -> String {
            switch self {
            case .popular: return L10n.t("sort.popular", language: language)
            case .newest: return L10n.t("sort.newest", language: language)
            }
        }
    }

    static func fetch(sort: Sort) async throws -> [LiveModel] {
        var req = URLRequest(url: URL(string: "https://ollama.com/library?sort=\(sort.rawValue)")!)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 20
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw URLError(.badServerResponse)
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        let models = parse(html)
        if models.isEmpty { throw URLError(.zeroByteResource) }
        return models
    }

    // MARK: HTML parsing

    static func parse(_ html: String) -> [LiveModel] {
        let ns = html as NSString
        guard let anchor = try? NSRegularExpression(pattern: #"<a href="/library/([^"]+)" class="group"#) else {
            return []
        }
        let anchors = anchor.matches(in: html, range: NSRange(location: 0, length: ns.length))
        var models: [LiveModel] = []
        models.reserveCapacity(anchors.count)

        for (i, m) in anchors.enumerated() {
            let start = m.range.location
            let end = (i + 1 < anchors.count) ? anchors[i + 1].range.location : ns.length
            let block = ns.substring(with: NSRange(location: start, length: end - start))
            let name = ns.substring(with: m.range(at: 1))

            let rawSummary = firstGroup(#"<p class="max-w-lg[^"]*">(.*?)</p>"#, block, dotAll: true) ?? ""
            let summary = decodeEntities(rawSummary)
                .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let caps = allGroups(#"x-test-capability[^>]*>([^<]+)<"#, block)
            let sizes = allGroups(#"x-test-size[^>]*>([^<]+)<"#, block)
            let pulls = firstGroup(#"x-test-pull-count>([^<]+)<"#, block) ?? "—"
            let updated = firstGroup(#"x-test-updated>([^<]+)<"#, block) ?? ""
            let tagCountStr = firstGroup(#"x-test-tag-count>([^<]+)<"#, block) ?? "0"
            let tagCount = Int(tagCountStr.replacingOccurrences(of: ",", with: "")) ?? 0

            models.append(LiveModel(name: name, summary: summary, capabilities: caps,
                                    sizes: sizes, pulls: pulls, tagCount: tagCount, updated: updated))
        }
        return models
    }

    private static func firstGroup(_ pattern: String, _ s: String, dotAll: Bool = false) -> String? {
        let opts: NSRegularExpression.Options = dotAll ? [.dotMatchesLineSeparators] : []
        guard let re = try? NSRegularExpression(pattern: pattern, options: opts) else { return nil }
        let ns = s as NSString
        guard let r = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)),
              r.numberOfRanges > 1 else { return nil }
        return ns.substring(with: r.range(at: 1))
    }

    private static func allGroups(_ pattern: String, _ s: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).compactMap {
            $0.numberOfRanges > 1 ? ns.substring(with: $0.range(at: 1)) : nil
        }
    }

    private static func decodeEntities(_ s: String) -> String {
        var t = s
        let map = [("&amp;", "&"), ("&#39;", "'"), ("&#x27;", "'"), ("&quot;", "\""),
                   ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " ")]
        for (a, b) in map { t = t.replacingOccurrences(of: a, with: b) }
        return t
    }
}

// MARK: - On-disk cache

enum LibraryCache {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ModelChanges", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    static var file: URL { directory.appendingPathComponent("library.json") }

    static func load() -> LibrarySnapshot? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(LibrarySnapshot.self, from: data)
    }

    static func save(_ snapshot: LibrarySnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: file)
        }
    }
}

enum UnavailableStore {
    static var file: URL { LibraryCache.directory.appendingPathComponent("unavailable.json") }
    static func load() -> Set<String> {
        guard let data = try? Data(contentsOf: file) else { return [] }
        return (try? JSONDecoder().decode(Set<String>.self, from: data)) ?? []
    }
    static func save(_ set: Set<String>) {
        if let data = try? JSONEncoder().encode(set) { try? data.write(to: file) }
    }
}

enum HistoryStore {
    static var file: URL { LibraryCache.directory.appendingPathComponent("history.json") }

    static func load() -> [HistoryEntry] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        return (try? JSONDecoder().decode([HistoryEntry].self, from: data)) ?? []
    }
    static func save(_ entries: [HistoryEntry]) {
        if let data = try? JSONEncoder().encode(entries) { try? data.write(to: file) }
    }
}

// MARK: - Offline seed (first run with no network)

enum LibrarySeed {
    static let models: [LiveModel] = [
        LiveModel(name: "llama3.1", summary: "State-of-the-art model from Meta available in 8B, 70B and 405B sizes.",
                  capabilities: ["tools"], sizes: ["8b", "70b", "405b"], pulls: "—", tagCount: 0, updated: ""),
        LiveModel(name: "qwen2.5-coder", summary: "Code-specialist models with strong fill-in-the-middle.",
                  capabilities: ["tools"], sizes: ["0.5b", "1.5b", "3b", "7b", "14b", "32b"], pulls: "—", tagCount: 0, updated: ""),
        LiveModel(name: "deepseek-r1", summary: "Open reasoning models with explicit chain-of-thought.",
                  capabilities: ["thinking"], sizes: ["1.5b", "7b", "8b", "14b", "32b", "70b", "671b"], pulls: "—", tagCount: 0, updated: ""),
        LiveModel(name: "gemma3", summary: "Google's efficient multimodal models with 128K context.",
                  capabilities: ["vision"], sizes: ["1b", "4b", "12b", "27b"], pulls: "—", tagCount: 0, updated: ""),
        LiveModel(name: "llama3.2", summary: "Small, efficient Llama models for on-device use.",
                  capabilities: ["tools"], sizes: ["1b", "3b"], pulls: "—", tagCount: 0, updated: ""),
        LiveModel(name: "nomic-embed-text", summary: "High-performing open embedding model for RAG.",
                  capabilities: ["embedding"], sizes: [], pulls: "—", tagCount: 0, updated: "")
    ]
}
