import Foundation

// MARK: - Model type

enum ModelType: String, Codable, CaseIterable, Identifiable, Hashable {
    case chat
    case code
    case vision
    case reasoning
    case embedding
    case audio

    var id: String { rawValue }

    var label: String {
        label(language: .english)
    }

    func label(language: AppLanguage) -> String {
        switch self {
        case .chat: return L10n.t("modelType.chat", language: language)
        case .code: return L10n.t("modelType.code", language: language)
        case .vision: return L10n.t("modelType.vision", language: language)
        case .reasoning: return L10n.t("modelType.reasoning", language: language)
        case .embedding: return L10n.t("modelType.embedding", language: language)
        case .audio: return L10n.t("modelType.audio", language: language)
        }
    }

    var symbol: String {
        switch self {
        case .chat: return "bubble.left.and.bubble.right"
        case .code: return "chevron.left.forward.slash.chevron.right"
        case .vision: return "eye"
        case .reasoning: return "brain"
        case .embedding: return "point.3.connected.trianglepath.dotted"
        case .audio: return "waveform"
        }
    }
}

// MARK: - Live catalog (parsed from ollama.com/library)

/// A model family as listed on ollama.com — fetched live, not hardcoded.
struct LiveModel: Codable, Identifiable, Hashable {
    var name: String            // ollama base name, e.g. "llama3.1"
    var summary: String         // description
    var capabilities: [String]  // tools / thinking / vision / embedding / audio
    var sizes: [String]         // ["8b", "70b", "405b"]
    var pulls: String           // "116.9M"
    var tagCount: Int
    var updated: String         // "2 weeks ago"

    var id: String { name }

    var types: [ModelType] {
        let caps = Set(capabilities)
        if caps.contains("embedding") { return [.embedding] }
        var t: [ModelType] = []
        let hay = (name + " " + summary).lowercased()
        if hay.contains("cod") { t.append(.code) }
        if caps.contains("thinking") { t.append(.reasoning) }
        if caps.contains("vision") { t.append(.vision) }
        if caps.contains("audio") { t.append(.audio) }
        if t.isEmpty {
            t = [.chat]
        } else if caps.contains("tools"), !t.contains(.code) {
            t.insert(.chat, at: 0)
        }
        return t
    }

    var primaryType: ModelType { types.first ?? .chat }

    /// Best-effort developer, inferred from the family name.
    var developer: String { ModelMeta.developer(for: name) }

    var hasTools: Bool { capabilities.contains("tools") }

    var variants: [LiveVariant] {
        let labels = sizes.isEmpty ? ["latest"] : sizes
        return labels.map { label in
            let tag = label == "latest" ? name : "\(name):\(label)"
            let b = ModelMeta.paramsBillions(label)
            return LiveVariant(tag: tag,
                               sizeLabel: label,
                               estDiskGB: ModelMeta.estDiskGB(b),
                               estRAMGB: ModelMeta.estRAMGB(b))
        }
    }
}

struct LiveVariant: Identifiable, Hashable {
    var tag: String
    var sizeLabel: String
    var estDiskGB: Double
    var estRAMGB: Double
    var id: String { tag }
}

enum ModelMeta {
    /// Parse a size label like "8b", "3.8b", "135m", "8x7b" into billions of params.
    static func paramsBillions(_ label: String) -> Double? {
        let l = label.lowercased()
        if let x = l.range(of: "x") {   // MoE like "8x7b"
            let n = Double(l[l.startIndex..<x.lowerBound]) ?? 1
            let rest = String(l[x.upperBound...])
            if let per = paramsBillions(rest) { return n * per }
        }
        if l.hasSuffix("b"), let v = Double(l.dropLast()) { return v }
        if l.hasSuffix("m"), let v = Double(l.dropLast()) { return v / 1000 }
        return nil
    }

    static func estDiskGB(_ billions: Double?) -> Double {
        guard let b = billions else { return 0 }
        return (b * 0.6 * 10).rounded() / 10   // ~Q4 on disk
    }

    static func estRAMGB(_ billions: Double?) -> Double {
        guard let b = billions else { return 0 }
        return (b * 0.75 + 2).rounded()
    }

    private static let devMap: [(String, String)] = [
        ("codellama", "Meta"), ("tinyllama", "Community"), ("llama", "Meta"),
        ("qwen", "Alibaba"), ("qwq", "Alibaba"),
        ("deepseek", "DeepSeek"),
        ("gemma", "Google"), ("codegemma", "Google"),
        ("phi", "Microsoft"),
        ("codestral", "Mistral AI"), ("mixtral", "Mistral AI"), ("mistral", "Mistral AI"),
        ("command", "Cohere"),
        ("granite", "IBM"),
        ("smollm", "Hugging Face"),
        ("nomic", "Nomic AI"), ("mxbai", "Mixedbread"), ("bge", "BAAI"),
        ("snowflake", "Snowflake"), ("all-minilm", "Sentence-Transformers"),
        ("starcoder", "BigCode"), ("llava", "LLaVA"), ("minicpm", "OpenBMB"),
        ("moondream", "Moondream"), ("wizard", "WizardLM"), ("yi", "01.AI"),
        ("dolphin", "Cognitive Computations"), ("orca", "Microsoft"),
        ("falcon", "TII"), ("stablelm", "Stability AI"), ("solar", "Upstage"),
        ("aya", "Cohere"), ("nemotron", "NVIDIA")
    ]

    static func developer(for name: String) -> String {
        let l = name.lowercased()
        for (key, dev) in devMap where l.contains(key) { return dev }
        return ""
    }
}

// MARK: - Hardware fit

enum FitStatus: String {
    case fits, tight, tooBig

    var label: String {
        label(language: .english)
    }

    func label(language: AppLanguage) -> String {
        switch self {
        case .fits: return L10n.t("fit.fits", language: language)
        case .tight: return L10n.t("fit.tight", language: language)
        case .tooBig: return L10n.t("fit.tooBig", language: language)
        }
    }
    var symbol: String {
        switch self {
        case .fits: return "checkmark.circle.fill"
        case .tight: return "exclamationmark.triangle.fill"
        case .tooBig: return "xmark.octagon.fill"
        }
    }
    var deployable: Bool { self != .tooBig }
}

enum Hardware {
    /// Physical RAM in GiB.
    static let ramGB: Double = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0

    static func fit(estRAMGB: Double, ramGB: Double = ramGB) -> FitStatus {
        if estRAMGB <= 0 { return .fits }               // unknown (e.g. embeddings) → assume ok
        if estRAMGB <= ramGB * 0.72 { return .fits }
        if estRAMGB <= ramGB * 0.92 { return .tight }
        return .tooBig
    }
}

// MARK: - Launch history

enum HistoryAction: String, Codable {
    case deployed, started, stopped, removed, cleared, wiped

    var verb: String {
        verb(language: .english)
    }

    func verb(language: AppLanguage) -> String {
        switch self {
        case .deployed: return L10n.t("history.deployed", language: language)
        case .started: return L10n.t("history.started", language: language)
        case .stopped: return L10n.t("history.stopped", language: language)
        case .removed: return L10n.t("history.removed", language: language)
        case .cleared: return L10n.t("history.cleared", language: language)
        case .wiped: return L10n.t("history.wiped", language: language)
        }
    }
    var symbol: String {
        switch self {
        case .deployed: return "arrow.down.circle.fill"
        case .started: return "play.circle.fill"
        case .stopped: return "stop.circle.fill"
        case .removed: return "trash.circle.fill"
        case .cleared: return "trash.circle.fill"
        case .wiped: return "sparkles"
        }
    }
}

struct HistoryEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var tag: String
    var action: HistoryAction
    var at: Date
}

// MARK: - Live Ollama state

struct InstalledModel: Codable, Identifiable, Hashable {
    var name: String
    var model: String?
    var modifiedAt: String?
    var size: Int64
    var digest: String?
    var details: OllamaDetails?
    var capabilities: [String]?
    var id: String { name }
}

struct RunningModel: Codable, Identifiable, Hashable {
    var name: String
    var model: String?
    var size: Int64
    var sizeVram: Int64?
    var digest: String?
    var details: OllamaDetails?
    var capabilities: [String]?
    var expiresAt: String?
    var id: String { name }

    var gpuFraction: Double {
        guard size > 0, let vram = sizeVram else { return 0 }
        return min(1.0, Double(vram) / Double(size))
    }
}

struct OllamaDetails: Codable, Hashable {
    var format: String?
    var family: String?
    var families: [String]?
    var parameterSize: String?
    var quantizationLevel: String?
    var contextLength: Int?
    var embeddingLength: Int?
}

struct PullLine: Codable {
    var status: String
    var digest: String?
    var total: Int64?
    var completed: Int64?
    var error: String?
}

struct DeployProgress: Identifiable, Hashable {
    var id: String { tag }
    var tag: String
    var status: String
    var completed: Int64 = 0
    var total: Int64 = 0
    var phase: Phase = .pulling

    enum Phase: Hashable { case pulling, loading, done, failed }

    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1.0, Double(completed) / Double(total))
    }
}

// MARK: - Formatting

enum Fmt {
    static func bytes(_ n: Int64) -> String {
        let f = ByteCountFormatter(); f.countStyle = .file
        return f.string(fromByteCount: n)
    }
    static func gb(_ v: Double) -> String {
        if v <= 0 { return "—" }
        return v >= 100 ? String(format: "%.0f GB", v) : String(format: "%.1f GB", v)
    }
    static func relative(_ date: Date, language: AppLanguage = .english) -> String {
        let s = Date().timeIntervalSince(date)
        if s < 60 { return L10n.t("relative.justNow", language: language) }
        if s < 3600 { return L10n.t("relative.minutesAgo", language: language, Int(s / 60)) }
        if s < 86400 { return L10n.t("relative.hoursAgo", language: language, Int(s / 3600)) }
        return L10n.t("relative.daysAgo", language: language, Int(s / 86400))
    }
}
