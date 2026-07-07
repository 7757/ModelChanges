import Foundation
import SwiftUI

/// Central app state + all Ollama interaction (HTTP API + local process control).
@MainActor
final class AppState: ObservableObject {

    // Live model catalog (fetched from ollama.com)
    @Published var models: [LiveModel] = []
    @Published var librarySyncedAt: Date?
    @Published var syncing = false
    @Published var syncError: String?
    @Published var sort: Library.Sort = .popular

    // Live server state
    @Published var serverReachable = false
    @Published var serverVersion: String?
    @Published var ollamaInstalled = false
    @Published var ollamaPath: String?

    // Live model state
    @Published var installed: [InstalledModel] = []
    @Published var running: [RunningModel] = []

    // In-flight deploys keyed by tag
    @Published var deployments: [String: DeployProgress] = [:]

    // UX
    @Published var lastError: String?
    @Published var actionLog: [String] = []
    @Published var history: [HistoryEntry] = []
    @Published var unavailableTags: Set<String> = []       // known-not-pullable
    @Published var importableModels: [String] = []         // found in a legacy ~/.ollama
    @Published var importDismissed = false
    @Published var importing = false
    @Published var keepAlive: String = "30m"   // how long models stay loaded
    @Published var wiping = false
    @Published var launchAtLogin: Bool = LoginItem.isEnabled
    @Published var language: AppLanguage = AppLanguage.load() {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: AppLanguage.storageKey)
        }
    }

    func setLaunchAtLogin(_ on: Bool) {
        LoginItem.set(on)
        launchAtLogin = LoginItem.isEnabled
    }

    func setLanguage(_ language: AppLanguage) {
        self.language = language
    }

    func t(_ key: String, _ args: CVarArg...) -> String {
        L10n.t(key, language: language, arguments: args)
    }

    /// Total RAM footprint of models currently loaded in memory.
    var loadedBytes: Int64 { running.reduce(0) { $0 + $1.size } }
    /// Physical RAM of this machine (GiB) — used for the dynamic fit analysis.
    let ramGB: Double = Hardware.ramGB

    let host = "http://127.0.0.1:11434"

    /// The Ollama runtime we ship *inside* the app (Contents/Resources/ollama-runtime).
    var bundledBinaryURL: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("ollama-runtime/ollama")
    }
    var hasBundledRuntime: Bool {
        guard let u = bundledBinaryURL else { return false }
        return FileManager.default.isExecutableFile(atPath: u.path)
    }
    /// Our own isolated model store, so nothing leaks onto the host.
    var modelsDirURL: URL {
        LibraryCache.directory.appendingPathComponent("models", isDirectory: true)
    }

    private var pullTasks: [String: Task<Void, Never>] = [:]
    private var pollTask: Task<Void, Never>?
    private var librarySyncTask: Task<Void, Never>?

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    init() {
        if let snap = LibraryCache.load() {
            models = snap.models
            librarySyncedAt = snap.fetchedAt
            sort = Library.Sort(rawValue: snap.sort) ?? .popular
        } else {
            models = LibrarySeed.models
        }
        history = HistoryStore.load()
        unavailableTags = UnavailableStore.load()
        importDismissed = UserDefaults.standard.bool(forKey: "ModelChanges.importDismissed")
        detectInstall()
        scanImportableModels()
    }

    // MARK: - Import existing models from a legacy ~/.ollama

    private var legacyModelsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ollama/models")
    }

    /// Look for models in a separate Ollama install so we can offer to import them.
    func scanImportableModels() {
        let manifests = legacyModelsDir.appendingPathComponent("manifests")
        guard FileManager.default.fileExists(atPath: manifests.path) else { importableModels = []; return }
        var found: [String] = []
        if let e = FileManager.default.enumerator(at: manifests, includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let url as URL in e where (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                let parts = url.pathComponents
                if parts.count >= 2 { found.append("\(parts[parts.count - 2]):\(parts.last!)") }
            }
        }
        importableModels = found.sorted()
    }

    /// Merge the legacy model store into our bundled one (blobs are content-addressed).
    func importLegacyModels() {
        guard !importing else { return }
        importing = true
        let src = legacyModelsDir.path
        let dst = modelsDirURL.path
        Task {
            log(t("log.importing"))
            try? FileManager.default.createDirectory(atPath: dst, withIntermediateDirectories: true)
            await Task.detached { _ = try? Self.runSyncStatic("/usr/bin/rsync", ["-a", src + "/", dst + "/"]) }.value
            BundledServer.shared.stop()          // restart so it rescans the merged store
            startServer()
            importableModels = []
            dismissImport()
            importing = false
            log(t("log.imported"))
        }
    }

    func dismissImport() {
        importDismissed = true
        UserDefaults.standard.set(true, forKey: "ModelChanges.importDismissed")
    }

    // MARK: - History

    func record(_ tag: String, _ action: HistoryAction) {
        history.insert(HistoryEntry(tag: tag, action: action, at: Date()), at: 0)
        if history.count > 300 { history.removeLast(history.count - 300) }
        HistoryStore.save(history)
    }

    func clearHistory() {
        history = []
        HistoryStore.save(history)
    }

    // MARK: - Live library sync

    func startLibrarySync() {
        guard librarySyncTask == nil else { return }
        librarySyncTask = Task { [weak self] in
            guard let self else { return }
            let stale = self.librarySyncedAt.map { Date().timeIntervalSince($0) > 3600 } ?? true
            if stale { await self.syncLibrary() }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 6 * 3600 * 1_000_000_000)  // every 6h
                if Task.isCancelled { break }
                await self.syncLibrary()
            }
        }
    }

    func syncLibrary() async {
        if syncing { return }
        syncing = true
        syncError = nil
        // ollama.com can be slow / flaky (transient TLS handshake failures).
        // Retry a few times before surfacing an error.
        var lastErr: Error?
        for attempt in 1...3 {
            do {
                let fetched = try await Library.fetch(sort: sort)
                models = fetched
                let now = Date()
                librarySyncedAt = now
                LibraryCache.save(LibrarySnapshot(models: fetched, fetchedAt: now, sort: sort.rawValue))
                log(t("log.synced", fetched.count))
                syncing = false
                return
            } catch {
                lastErr = error
                if attempt < 3 { try? await Task.sleep(nanoseconds: 1_200_000_000) }
            }
        }
        syncError = t("error.syncFailed", lastErr?.localizedDescription ?? "")
        syncing = false
    }

    func changeSort(_ newSort: Library.Sort) {
        guard newSort != sort else { return }
        sort = newSort
        Task { await syncLibrary() }
    }

    // MARK: - Derived lookups

    func isInstalled(_ tag: String) -> Bool {
        installed.contains { $0.name == tag || normalize($0.name) == normalize(tag) }
    }

    func isRunning(_ tag: String) -> Bool {
        running.contains { $0.name == tag || normalize($0.name) == normalize(tag) }
    }

    /// Ollama stores "llama3.2" as "llama3.2:latest"; treat those as equal.
    private func normalize(_ tag: String) -> String {
        tag.contains(":") ? tag : tag + ":latest"
    }

    var installedBytes: Int64 { installed.reduce(0) { $0 + $1.size } }
    var runningVramBytes: Int64 { running.reduce(0) { $0 + ($1.sizeVram ?? 0) } }

    // MARK: - Polling

    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() async {
        await fetchVersion()
        if serverReachable {
            await fetchTags()
            await fetchRunning()
        } else {
            installed = []
            running = []
        }
    }

    // MARK: - Read API

    private func fetchVersion() async {
        struct V: Decodable { var version: String }
        do {
            let data = try await get("/api/version", timeout: 2)
            let v = try Self.decoder.decode(V.self, from: data)
            serverVersion = v.version
            serverReachable = true
            // A reachable server means Ollama is installed; refresh path if we
            // missed it at launch (e.g. it was installed while the app ran).
            if !ollamaInstalled || ollamaPath == nil {
                detectInstall()
                ollamaInstalled = true
            }
        } catch {
            serverReachable = false
            serverVersion = nil
        }
    }

    private func fetchTags() async {
        struct R: Decodable { var models: [InstalledModel] }
        do {
            let data = try await get("/api/tags")
            installed = (try Self.decoder.decode(R.self, from: data)).models
                .sorted { $0.name < $1.name }
        } catch { /* keep previous */ }
    }

    private func fetchRunning() async {
        struct R: Decodable { var models: [RunningModel] }
        do {
            let data = try await get("/api/ps")
            running = (try Self.decoder.decode(R.self, from: data)).models
        } catch { /* keep previous */ }
    }

    // MARK: - Deploy (pull if needed, then load into memory)

    func deploy(_ tag: String) {
        guard pullTasks[tag] == nil else { return }
        log(t("log.deploying", tag))
        let task = Task { [weak self] in
            guard let self else { return }
            let alreadyInstalled = await MainActor.run { self.isInstalled(tag) }
            if !alreadyInstalled {
                let ok = await self.performPull(tag)
                if !ok {
                    await MainActor.run { self.pullTasks[tag] = nil }
                    return
                }
            }
            await MainActor.run {
                self.deployments[tag] = DeployProgress(tag: tag, status: self.t("progress.loadingIntoMemory"), phase: .loading)
            }
            await self.load(tag)
            await MainActor.run {
                self.deployments[tag]?.phase = .done
                self.deployments[tag]?.status = self.t("progress.ready")
                self.log(self.t("log.ready", tag))
                self.record(tag, alreadyInstalled ? .started : .deployed)
                self.pullTasks[tag] = nil
            }
            await self.refresh()
            // Clear the finished progress chip after a moment.
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run {
                if self.deployments[tag]?.phase == .done { self.deployments[tag] = nil }
            }
        }
        pullTasks[tag] = task
    }

    /// Pull only (download to disk), no load.
    func pull(_ tag: String) {
        guard pullTasks[tag] == nil else { return }
        let task = Task { [weak self] in
            guard let self else { return }
            _ = await self.performPull(tag)
            await MainActor.run { self.pullTasks[tag] = nil }
            await self.refresh()
        }
        pullTasks[tag] = task
    }

    private func performPull(_ tag: String) async -> Bool {
        await MainActor.run {
            self.deployments[tag] = DeployProgress(tag: tag, status: "starting…", phase: .pulling)
        }
        do {
            var req = URLRequest(url: URL(string: host + "/api/pull")!)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: ["model": tag, "stream": true])

            let (bytes, response) = try await URLSession.shared.bytes(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                throw NSError(domain: "ollama", code: http.statusCode,
                              userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
            }
            for try await line in bytes.lines {
                guard !line.isEmpty, let d = line.data(using: .utf8) else { continue }
                guard let p = try? Self.decoder.decode(PullLine.self, from: d) else { continue }
                if let err = p.error {
                    await MainActor.run { self.failPull(tag, err) }
                    return false
                }
                let status = p.status ?? ""
                await MainActor.run {
                    var dp = self.deployments[tag] ?? DeployProgress(tag: tag, status: status)
                    if !status.isEmpty { dp.status = status }
                    dp.total = p.total ?? dp.total
                    dp.completed = p.completed ?? (p.total != nil ? dp.completed : 0)
                    dp.phase = .pulling
                    self.deployments[tag] = dp
                }
            }
            return true
        } catch {
            await MainActor.run { self.fail(tag, error.localizedDescription) }
            return false
        }
    }

    func cancelDeploy(_ tag: String) {
        pullTasks[tag]?.cancel()
        pullTasks[tag] = nil
        deployments[tag] = nil
        log(t("log.cancelled", tag))
    }

    // MARK: - Load / Stop / Remove

    /// Load a model into memory without generating (warm start).
    func load(_ tag: String) async {
        do {
            // "-1" means keep loaded forever; send it as an integer, not a string.
            let ka: Any = keepAlive == "-1" ? -1 : keepAlive
            _ = try await postJSON("/api/generate", ["model": tag, "keep_alive": ka])
        } catch {
            await MainActor.run { self.lastError = error.localizedDescription }
        }
    }

    /// Unload a model from memory (keep_alive: 0 evicts immediately).
    func stop(_ name: String) {
        Task {
            log(t("log.stopping", name))
            do {
                _ = try await postJSON("/api/generate", ["model": name, "keep_alive": 0])
            } catch {
                await MainActor.run { self.lastError = error.localizedDescription }
            }
            await refresh()
            log(t("log.stopped", name))
            record(name, .stopped)
        }
    }

    /// Delete a model from disk.
    func remove(_ name: String) {
        Task {
            log(t("log.removing", name))
            await deleteModel(name)
            await refresh()
            log(t("log.removed", name))
            record(name, .removed)
        }
    }

    private func deleteModel(_ name: String) async {
        do {
            var req = URLRequest(url: URL(string: host + "/api/delete")!)
            req.httpMethod = "DELETE"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: ["model": name])
            _ = try await URLSession.shared.data(for: req)
        } catch {
            await MainActor.run { self.lastError = error.localizedDescription }
        }
    }

    // MARK: - Clean teardown

    /// Stop everything and delete every model (keeps Ollama installed).
    func removeAllModels() {
        guard !wiping else { return }
        wiping = true
        Task {
            log(t("log.removingAll"))
            for m in running { _ = try? await postJSON("/api/generate", ["model": m.name, "keep_alive": 0]) }
            let names = installed.map(\.name)
            for name in names { await deleteModel(name) }
            await refresh()
            record("all models", .cleared)
            log(t("log.removedAll", names.count))
            wiping = false
        }
    }

    /// Erase every model and all app data. The bundled engine can't be
    /// "uninstalled" — to remove the app itself, drag it to the Trash.
    func resetHost() {
        guard !wiping else { return }
        wiping = true
        Task {
            log(t("log.resettingHost"))
            for m in running { _ = try? await postJSON("/api/generate", ["model": m.name, "keep_alive": 0]) }
            for name in installed.map(\.name) { await deleteModel(name) }
            await refresh()
            // Stop our bundled server and wipe our isolated model store + app data.
            BundledServer.shared.stop()
            try? FileManager.default.removeItem(at: modelsDirURL)
            history = []; HistoryStore.save(history)
            unavailableTags = []; UnavailableStore.save(unavailableTags)
            installed = []
            running = []
            log(t("log.hostCleaned"))
            // Bring a clean server back up.
            startServer()
            wiping = false
        }
    }

    // MARK: - Test chat

    func testChat(model: String, prompt: String, imageBase64: String? = nil) async -> String {
        await testChat(model: model, prompt: prompt, imageBase64List: imageBase64.map { [$0] } ?? [])
    }

    func testChat(model: String, prompt: String, imageBase64List: [String]) async -> String {
        struct ChatMessage: Encodable {
            let role: String
            let content: String
            let images: [String]?
        }
        struct ChatReq: Encodable {
            let model: String
            let messages: [ChatMessage]
            let stream: Bool
        }
        struct ChatResp: Decodable { struct M: Decodable { let content: String }; let message: M }
        struct ErrorResp: Decodable { let error: String }
        do {
            var req = URLRequest(url: URL(string: host + "/api/chat")!)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let images = imageBase64List.isEmpty ? nil : imageBase64List
            let body = ChatReq(model: model,
                               messages: [ChatMessage(role: "user", content: prompt, images: images)],
                               stream: false)
            req.httpBody = try JSONEncoder().encode(body)
            req.timeoutInterval = 120
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                if let error = try? Self.decoder.decode(ErrorResp.self, from: data) {
                    return Self.readableError(error.error)
                }
                return "⚠️ HTTP \(http.statusCode)"
            }
            let resp = try Self.decoder.decode(ChatResp.self, from: data)
            return resp.message.content
        } catch {
            return "⚠️ \(error.localizedDescription)"
        }
    }

    func testToolCall(model: String, prompt: String) async -> String {
        let body: [String: Any] = [
            "model": model,
            "stream": false,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "tools": [[
                "type": "function",
                "function": [
                    "name": "get_weather",
                    "description": "Get current weather for a city.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "city": [
                                "type": "string",
                                "description": "City name"
                            ]
                        ],
                        "required": ["city"]
                    ]
                ]
            ]]
        ]
        do {
            let (data, response) = try await postJSONObject("/api/chat", body, timeout: 120)
            if response.statusCode >= 400 {
                return readableHTTPError(data, statusCode: response.statusCode)
            }
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let message = object["message"] as? [String: Any] else {
                return "⚠️ Could not read tool response."
            }
            if let calls = message["tool_calls"] as? [[String: Any]], !calls.isEmpty {
                let rendered = calls.enumerated().map { index, call in
                    guard let function = call["function"] as? [String: Any] else {
                        return "\(index + 1). \(call)"
                    }
                    let name = function["name"] as? String ?? "tool"
                    let args = function["arguments"] ?? [:]
                    let argsText = Self.prettyJSONString(args)
                    return "\(index + 1). \(name)\n\(argsText)"
                }
                return rendered.joined(separator: "\n\n")
            }
            if let content = message["content"] as? String, !content.isEmpty {
                return content
            }
            return "⚠️ The model returned no tool call."
        } catch {
            return "⚠️ \(error.localizedDescription)"
        }
    }

    func testEmbedding(model: String, input: String) async -> String {
        do {
            let (data, response) = try await postJSONObject("/api/embed", ["model": model, "input": input], timeout: 120)
            if response.statusCode >= 400 {
                return readableHTTPError(data, statusCode: response.statusCode)
            }
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return "⚠️ Could not read embedding response."
            }
            let vector: [Double]
            if let embeddings = object["embeddings"] as? [[Double]], let first = embeddings.first {
                vector = first
            } else if let embedding = object["embedding"] as? [Double] {
                vector = embedding
            } else {
                return "⚠️ No embedding vector returned."
            }
            let norm = sqrt(vector.reduce(0) { $0 + $1 * $1 })
            let preview = vector.prefix(8).map { String(format: "%.4f", $0) }.joined(separator: ", ")
            return """
            Dimensions: \(vector.count)
            L2 norm: \(String(format: "%.4f", norm))
            Preview: [\(preview)\(vector.count > 8 ? ", ..." : "")]
            """
        } catch {
            return "⚠️ \(error.localizedDescription)"
        }
    }

    nonisolated private static func readableError(_ raw: String) -> String {
        if let data = raw.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let nested = object["error"] as? [String: Any],
           let message = nested["message"] as? String {
            return "⚠️ \(message)"
        }
        return "⚠️ \(raw)"
    }

    nonisolated private static func prettyJSONString(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return "\(value)"
        }
        return string
    }

    private func readableHTTPError(_ data: Data, statusCode: Int) -> String {
        if let error = try? Self.decoder.decode(ErrorResp.self, from: data) {
            return Self.readableError(error.error)
        }
        return "⚠️ HTTP \(statusCode)"
    }

    private struct ErrorResp: Decodable { let error: String }

    // MARK: - HTTP helpers

    private func get(_ path: String, timeout: TimeInterval = 10) async throws -> Data {
        var req = URLRequest(url: URL(string: host + path)!)
        req.timeoutInterval = timeout
        let (data, _) = try await URLSession.shared.data(for: req)
        return data
    }

    @discardableResult
    private func postJSON(_ path: String, _ body: [String: Any]) async throws -> Data {
        let (data, _) = try await postJSONObject(path, body)
        return data
    }

    private func postJSONObject(_ path: String, _ body: [String: Any], timeout: TimeInterval = 600) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: URL(string: host + path)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = timeout
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }

    // MARK: - Local process control

    func detectInstall() {
        // The bundled runtime means Ollama is always "installed" from the user's view.
        if hasBundledRuntime {
            ollamaPath = bundledBinaryURL?.path
            ollamaInstalled = true
            return
        }
        let candidates = ["/opt/homebrew/bin/ollama", "/usr/local/bin/ollama"]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            ollamaPath = path
            ollamaInstalled = true
            return
        }
        if let which = try? runSync("/usr/bin/which", ["ollama"]).out
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !which.isEmpty, FileManager.default.isExecutableFile(atPath: which) {
            ollamaPath = which
            ollamaInstalled = true
            return
        }
        if let appPath = Self.ollamaAppPath() {
            let bundledCLI = appPath + "/Contents/Resources/ollama"
            ollamaPath = FileManager.default.isExecutableFile(atPath: bundledCLI) ? bundledCLI : nil
            ollamaInstalled = true   // app present even if CLI symlink missing
        } else {
            ollamaPath = nil
            ollamaInstalled = false
        }
    }

    /// Ensure a local Ollama server is running — prefer our bundled runtime.
    func startServer() {
        log(t("log.startingServer"))
        Task { [weak self] in
            guard let self else { return }
            await self.fetchVersion()
            if self.serverReachable { self.detectInstall(); return }  // already up

            if self.hasBundledRuntime, let bin = self.bundledBinaryURL {
                BundledServer.shared.start(binary: bin, modelsDir: self.modelsDirURL, host: "127.0.0.1:11434")
            } else if let appPath = Self.ollamaAppPath() {
                _ = try? await Task.detached { try Self.runDetached("/usr/bin/open", [appPath]) }.value
            } else if let path = self.ollamaPath {
                _ = try? await Task.detached { try Self.runDetached(path, ["serve"]) }.value
            }

            for _ in 0..<20 {
                try? await Task.sleep(nanoseconds: 600_000_000)
                await self.refresh()
                if self.serverReachable { self.detectInstall(); self.log(self.t("log.serverUp")); break }
            }
        }
    }

    /// Install Ollama directly from the official macOS DMG.
    func installOllama() {
        guard !wiping else { return }
        log(t("log.installingOllama"))
        Task {
            do {
                let dmg = try await Self.downloadOllamaDMG()
                let result = await Task.detached { Self.installOllamaDMGSync(dmg) }.value
                try? FileManager.default.removeItem(at: dmg)
                finishOllamaInstall(result)
            } catch {
                lastError = t("error.ollamaInstallFailed", error.localizedDescription)
                log(t("log.installFailed"))
            }
        }
    }

    private func finishOllamaInstall(_ result: (Int32, String, String)) {
        if result.0 == 0 {
            log(t("log.ollamaInstalled"))
            detectInstall()
            startServer()
        } else {
            lastError = t("error.ollamaInstallFailed", result.2.isEmpty ? result.1 : result.2)
            log(t("log.installFailed"))
        }
    }

    private static func downloadOllamaDMG() async throws -> URL {
        let source = URL(string: "https://ollama.com/download/Ollama.dmg")!
        let (temporaryURL, response) = try await URLSession.shared.download(from: source)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw URLError(.badServerResponse)
        }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("Ollama-\(UUID().uuidString).dmg")
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    nonisolated private static func installOllamaDMGSync(_ dmg: URL) -> (Int32, String, String) {
        do {
            let attach = try runSyncStatic("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-plist"])
            guard attach.0 == 0 else { return attach }
            guard let mount = mountPoint(from: attach.1) else {
                return (1, attach.1, "Could not mount Ollama installer")
            }
            defer { _ = try? runSyncStatic("/usr/bin/hdiutil", ["detach", mount, "-quiet"]) }

            let source = URL(fileURLWithPath: mount).appendingPathComponent("Ollama.app").path
            guard FileManager.default.fileExists(atPath: source) else {
                return (1, mount, "Ollama.app was not found in the installer")
            }

            var lastError = ""
            for destination in ollamaAppCandidates() {
                let parent = URL(fileURLWithPath: destination).deletingLastPathComponent().path
                try? FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)
                _ = try? FileManager.default.removeItem(atPath: destination)
                let copy = try runSyncStatic("/usr/bin/ditto", [source, destination])
                if copy.0 == 0 { return (0, destination, "") }
                lastError = copy.2.isEmpty ? copy.1 : copy.2
            }
            return (1, "", lastError.isEmpty ? "Could not copy Ollama.app" : lastError)
        } catch {
            return (1, "", error.localizedDescription)
        }
    }

    nonisolated private static func mountPoint(from plist: String) -> String? {
        guard let data = plist.data(using: .utf8),
              let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = object as? [String: Any],
              let entities = dict["system-entities"] as? [[String: Any]] else {
            return nil
        }
        return entities.compactMap { $0["mount-point"] as? String }
            .first { FileManager.default.fileExists(atPath: URL(fileURLWithPath: $0).appendingPathComponent("Ollama.app").path) }
    }

    nonisolated private static func ollamaAppCandidates() -> [String] {
        let userApps = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
            .appendingPathComponent("Ollama.app")
            .path
        return ["/Applications/Ollama.app", userApps]
    }

    nonisolated private static func ollamaAppPath() -> String? {
        ollamaAppCandidates().first { FileManager.default.fileExists(atPath: $0) }
    }

    // MARK: - Process utilities

    private func runSync(_ launch: String, _ args: [String]) throws -> (status: Int32, out: String, err: String) {
        try Self.runSyncStatic(launch, args)
    }

    nonisolated private static func runSyncStatic(_ launch: String, _ args: [String]) throws -> (Int32, String, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launch)
        p.arguments = args
        let outPipe = Pipe(); let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        try p.run()
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus,
                String(data: outData, encoding: .utf8) ?? "",
                String(data: errData, encoding: .utf8) ?? "")
    }

    @discardableResult
    nonisolated private static func runDetached(_ launch: String, _ args: [String]) throws -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launch)
        p.arguments = args
        try p.run()
        return p
    }

    // MARK: - Logging

    func log(_ message: String) {
        actionLog.insert(message, at: 0)
        if actionLog.count > 100 { actionLog.removeLast(actionLog.count - 100) }
    }

    private func fail(_ tag: String, _ message: String) {
        deployments[tag]?.phase = .failed
        deployments[tag]?.status = message
        lastError = t("error.failedTag", tag, message)
        log(t("log.failedTag", tag, message))
    }

    /// Turn a raw Ollama pull error into a clear, user-facing message.
    private func failPull(_ tag: String, _ raw: String) {
        let lower = raw.lowercased()
        let notPullable = lower.contains("manifest")
            || lower.contains("does not exist")
            || lower.contains("not found")
            || lower.contains("no such")
        if notPullable {
            unavailableTags.insert(tag)
            UnavailableStore.save(unavailableTags)
            deployments[tag] = nil                 // remove the stuck progress bar
            lastError = t("error.modelNotPullable", tag)
            log(t("log.failedTag", tag, raw))
        } else {
            fail(tag, raw)
        }
    }
}
