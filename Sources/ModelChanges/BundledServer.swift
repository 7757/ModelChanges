import Foundation

/// Owns the Ollama server process that we bundle *inside* the app, so the user
/// never installs Ollama separately. Runs it headless on our own port with our
/// own model directory, and can be stopped cleanly on quit.
final class BundledServer {
    static let shared = BundledServer()

    private var process: Process?

    var isRunning: Bool { process?.isRunning ?? false }

    /// Launch the bundled `ollama serve` if it isn't already running.
    func start(binary: URL, modelsDir: URL, host: String) {
        if isRunning { return }
        try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)

        let p = Process()
        p.executableURL = binary
        p.arguments = ["serve"]
        var env = ProcessInfo.processInfo.environment
        env["OLLAMA_HOST"] = host
        env["OLLAMA_MODELS"] = modelsDir.path
        p.environment = env
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            process = p
        } catch {
            process = nil
        }
    }

    func stop() {
        if let p = process, p.isRunning { p.terminate() }
        process = nil
    }
}
