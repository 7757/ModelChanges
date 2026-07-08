import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Shared sheet chrome

struct SheetTitleBar: View {
    @EnvironmentObject var app: AppState
    let title: String
    let systemImage: String
    var doneIsDefault = true
    var dismiss: () -> Void
    var body: some View {
        HStack {
            Label(title, systemImage: systemImage).font(.headline)
            Spacer()
            if doneIsDefault {
                Button(app.t("button.done"), action: dismiss).keyboardShortcut(.defaultAction)
            } else {
                Button(app.t("button.done"), action: dismiss)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}

// MARK: - Endpoint sheet

struct EndpointSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedModel = ""
    @State private var selectedSnippet: EndpointSnippetKind = .environment
    @State private var showExamples = false

    private var availableModels: [String] {
        var names = app.running.map(\.name)
        for m in app.installed where !names.contains(m.name) { names.append(m.name) }
        return names
    }
    private var modelForSnippet: String {
        selectedModel.isEmpty ? (availableModels.first ?? "qwen2.5:7b") : selectedModel
    }
    private var snippetCode: String {
        switch selectedSnippet {
        case .environment:
            return """
            export OPENAI_BASE_URL="http://localhost:11434/v1"
            export OPENAI_API_KEY="ollama"
            export OPENAI_MODEL="\(modelForSnippet)"
            """
        case .python:
            return """
            from openai import OpenAI

            client = OpenAI(base_url="http://localhost:11434/v1", api_key="ollama")
            r = client.chat.completions.create(
                model="\(modelForSnippet)",
                messages=[{"role": "user", "content": "Hello!"}]
            )
            print(r.choices[0].message.content)
            """
        case .curl:
            return """
            curl http://localhost:11434/v1/chat/completions \\
              -H "Content-Type: application/json" \\
              -d '{"model":"\(modelForSnippet)","messages":[{"role":"user","content":"Hi"}]}'
            """
        case .vision:
            return """
            from openai import OpenAI

            client = OpenAI(base_url="http://localhost:11434/v1", api_key="ollama")
            r = client.chat.completions.create(
                model="\(modelForSnippet)",
                messages=[{
                    "role": "user",
                    "content": [
                        {"type": "text", "text": "Describe this image."},
                        {"type": "image_url", "image_url": {"url": "data:image/png;base64,<BASE64_IMAGE>"}}
                    ]
                }]
            )
            print(r.choices[0].message.content)
            """
        case .tools:
            return """
            from openai import OpenAI

            client = OpenAI(base_url="http://localhost:11434/v1", api_key="ollama")
            r = client.chat.completions.create(
                model="\(modelForSnippet)",
                messages=[{"role": "user", "content": "What is the weather in Singapore?"}],
                tools=[{
                    "type": "function",
                    "function": {
                        "name": "get_weather",
                        "description": "Get current weather for a city.",
                        "parameters": {
                            "type": "object",
                            "properties": {"city": {"type": "string"}},
                            "required": ["city"]
                        }
                    }
                }]
            )
            print(r.choices[0].message.tool_calls)
            """
        case .embedding:
            return """
            from openai import OpenAI

            client = OpenAI(base_url="http://localhost:11434/v1", api_key="ollama")
            r = client.embeddings.create(
                model="\(modelForSnippet)",
                input="Local models make private AI workflows possible."
            )
            print(len(r.data[0].embedding))
            """
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetTitleBar(title: app.t("endpoint.title"), systemImage: "link", doneIsDefault: false) { dismiss() }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    SettingsGroup(title: app.t("endpoint.connection")) {
                        SettingsRow(title: app.serverReachable ? app.t("endpoint.readyTitle") : app.t("endpoint.waitingTitle"),
                                    subtitle: app.serverReachable ? app.t("endpoint.live") : app.t("endpoint.offline"),
                                    systemImage: app.serverReachable ? "checkmark.circle" : "power.circle") {
                            Circle()
                                .fill(app.serverReachable ? Color.green : Color.orange)
                                .frame(width: 9, height: 9)
                        }
                        Divider().padding(.leading, 36)
                        SettingsRow(title: app.t("endpoint.currentModel"),
                                    subtitle: app.t("endpoint.modelHint"),
                                    systemImage: "memorychip") {
                            if availableModels.isEmpty {
                                Text(app.t("endpoint.noModel"))
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(.secondary)
                            } else {
                                Picker("", selection: $selectedModel) {
                                    ForEach(availableModels, id: \.self) { Text($0).tag($0) }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(maxWidth: 190)
                            }
                        }
                    }

                    SettingsGroup(title: app.t("endpoint.urls")) {
                        EndpointAddressRow(title: app.t("endpoint.openAIBase"),
                                        subtitle: app.t("endpoint.primaryHint"),
                                        value: "http://localhost:11434/v1")
                        Divider().padding(.leading, 36)
                        EndpointAddressRow(title: app.t("endpoint.nativeAPI"),
                                        subtitle: app.t("endpoint.nativeHint"),
                                        value: "http://localhost:11434")
                    }

                    SettingsGroup(title: app.t("endpoint.configuration")) {
                        DisclosureGroup(isExpanded: $showExamples) {
                            VStack(alignment: .leading, spacing: 10) {
                                Picker("", selection: $selectedSnippet) {
                                    ForEach(EndpointSnippetKind.allCases) { kind in
                                        Text(kind.label(app: app)).tag(kind)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(width: 180, alignment: .leading)

                                EndpointCodeBlock(code: snippetCode)
                            }
                            .padding(.top, 10)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "curlybraces")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.t("endpoint.snippetTitle")).font(.callout.weight(.medium))
                                    Text(app.t("endpoint.apiKeyHint")).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                        .padding(12)
                    }

                    TestChatView(model: modelForSnippet)
                }
                .padding(18)
            }
        }
        .frame(width: 580, height: 600)
        .onAppear { if selectedModel.isEmpty { selectedModel = availableModels.first ?? "" } }
    }
}

private enum EndpointSnippetKind: String, CaseIterable, Identifiable {
    case environment
    case python
    case curl
    case vision
    case tools
    case embedding

    var id: String { rawValue }

    @MainActor
    func label(app: AppState) -> String {
        switch self {
        case .environment: return app.t("endpoint.environment")
        case .python: return app.t("endpoint.pythonSDK")
        case .curl: return "curl"
        case .vision: return app.t("endpoint.visionExample")
        case .tools: return app.t("endpoint.toolsExample")
        case .embedding: return app.t("endpoint.embeddingExample")
        }
    }
}

private struct EndpointAddressRow: View {
    @EnvironmentObject var app: AppState
    let title: String
    let subtitle: String
    let value: String
    @State private var copied = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "link")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.callout.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(value)
                .font(.system(size: 12.5, weight: .regular, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(width: 205, alignment: .leading)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
                copied = true
                Task { try? await Task.sleep(nanoseconds: 1_300_000_000); copied = false }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .foregroundStyle(copied ? .green : .secondary)
            .help(copied ? app.t("endpoint.copied") : app.t("endpoint.copy"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

private struct EndpointCodeBlock: View {
    @EnvironmentObject var app: AppState
    let code: String
    @State private var copied = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 90, maxHeight: 132)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.45),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1))

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code, forType: .string)
                copied = true
                Task { try? await Task.sleep(nanoseconds: 1_300_000_000); copied = false }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 30, height: 30)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .foregroundStyle(copied ? .green : .secondary)
            .padding(6)
            .help(copied ? app.t("endpoint.copied") : app.t("endpoint.copy"))
        }
    }
}

private enum TestMode: String, CaseIterable, Identifiable {
    case text
    case image
    case tools
    case embedding

    var id: String { rawValue }

    @MainActor
    func label(app: AppState) -> String {
        switch self {
        case .text: return app.t("test.modeText")
        case .image: return app.t("test.modeImage")
        case .tools: return app.t("test.modeTools")
        case .embedding: return app.t("test.modeEmbedding")
        }
    }
}

struct TestChatView: View {
    @EnvironmentObject var app: AppState
    let model: String
    @State private var mode: TestMode = .text
    @State private var prompt = ""
    @State private var response = ""
    @State private var isLoading = false
    @State private var latency: Double?
    @State private var selectedImageName = ""
    @State private var selectedImageBase64: String?
    @State private var selectedImagePreview: NSImage?

    private var selectedInstalled: InstalledModel? {
        app.installed.first { sameTag($0.name, model) }
    }
    private var selectedRunning: RunningModel? {
        app.running.first { sameTag($0.name, model) }
    }
    private var modelCapabilities: [String] {
        let installed = selectedInstalled?.capabilities ?? []
        if !installed.isEmpty { return installed }
        return selectedRunning?.capabilities ?? []
    }
    private var supportsText: Bool {
        modelCapabilities.isEmpty ||
        modelCapabilities.contains("completion") ||
        modelCapabilities.contains("tools") ||
        modelCapabilities.contains("vision")
    }
    private var supportsVision: Bool {
        modelCapabilities.contains("vision")
    }
    private var supportsTools: Bool {
        modelCapabilities.contains("tools")
    }
    private var supportsEmbedding: Bool {
        modelCapabilities.contains("embedding")
    }
    private var availableModes: [TestMode] {
        var modes: [TestMode] = []
        if supportsText { modes.append(.text) }
        if supportsVision { modes.append(.image) }
        if supportsTools { modes.append(.tools) }
        if supportsEmbedding { modes.append(.embedding) }
        return modes.isEmpty ? [.text] : modes
    }
    private var canSend: Bool {
        let hasText = !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard !isLoading, hasText else { return false }
        guard !model.isEmpty, app.serverReachable else { return false }
        switch mode {
        case .text:
            return supportsText
        case .image:
            return supportsVision && selectedImageBase64 != nil
        case .tools:
            return supportsTools
        case .embedding:
            return supportsEmbedding
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsGroup(title: app.t("test.title")) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 10) {
                        Text(model.isEmpty ? app.t("test.deployFirst") : app.t("test.sendPrompt", model))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if availableModes.count > 1 {
                            Picker("", selection: $mode) {
                                ForEach(availableModes) { item in
                                    Text(item.label(app: app)).tag(item)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: CGFloat(availableModes.count) * 78)
                        }
                    }

                    capabilityRow

                    modeContent

                    sendRow

                    guidance

                    resultBlock
                }
                .padding(12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            prepareInitialState()
        }
        .onChange(of: model) { _, _ in
            prepareInitialState(clearResponse: true)
        }
        .onChange(of: modelCapabilities) { _, _ in
            normalizeMode()
        }
        .onChange(of: mode) { oldValue, newValue in
            let oldDefault = defaultPrompt(for: oldValue)
            if prompt.isEmpty || prompt == oldDefault {
                prompt = defaultPrompt(for: newValue)
            }
            response = ""
            latency = nil
        }
    }

    private var capabilityRow: some View {
        FlowLayout(spacing: 6) {
            if supportsText {
                Chip(text: app.t("test.capText"), systemImage: "text.bubble", tint: Brand.accent)
            }
            if supportsVision {
                Chip(text: app.t("test.capVision"), systemImage: "eye", tint: Color(red: 0.12, green: 0.72, blue: 0.68))
            }
            if supportsTools {
                Chip(text: app.t("test.capTools"), systemImage: "wrench.and.screwdriver", tint: Color(red: 0.92, green: 0.58, blue: 0.20))
            }
            if supportsEmbedding {
                Chip(text: app.t("test.capEmbedding"), systemImage: "point.3.connected.trianglepath.dotted", tint: Color(red: 0.38, green: 0.82, blue: 0.47))
            }
        }
    }

    @ViewBuilder
    private var modeContent: some View {
        switch mode {
        case .image:
            imageInput
        default:
            EmptyView()
        }
    }

    private var sendRow: some View {
        HStack(alignment: .top, spacing: 8) {
            TextField(placeholder, text: $prompt)
                .textFieldStyle(.plain)
                .submitLabel(.send)
                .onSubmit { send() }
                .padding(9)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            Button { send() } label: {
                if isLoading { ProgressView().controlSize(.small).frame(width: 58) }
                else { Label(sendButtonTitle, systemImage: sendButtonIcon).frame(minWidth: 58) }
            }
            .buttonStyle(.bordered)
            .disabled(!canSend)
        }
    }

    @ViewBuilder
    private var guidance: some View {
        switch mode {
        case .image where selectedImageBase64 == nil:
            Label(app.t("test.imagePickHint"), systemImage: "photo")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .embedding:
            Label(app.t("test.embeddingHint"), systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }

    private var imageInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let preview = selectedImagePreview {
                HStack(alignment: .center, spacing: 10) {
                    Image(nsImage: preview)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 78, height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Color.secondary.opacity(0.18), lineWidth: 1))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(selectedImageName.isEmpty ? app.t("test.pastedImage") : selectedImageName)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(app.t("test.imageReady"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button(app.t("button.clear")) { clearImage() }
                        .controlSize(.small)
                    Button(app.t("test.pasteImage")) { pasteImage() }
                        .controlSize(.small)
                    Button(app.t("test.changeImage")) { chooseImage() }
                        .controlSize(.small)
                }
                .padding(8)
                .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                HStack(spacing: 8) {
                    Button {
                        chooseImage()
                    } label: {
                        Label(app.t("test.chooseImage"), systemImage: "photo")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    Button {
                        pasteImage()
                    } label: {
                        Label(app.t("test.pasteImage"), systemImage: "doc.on.clipboard")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var placeholder: String {
        switch mode {
        case .text: return app.t("test.placeholder")
        case .image: return app.t("test.placeholderImage")
        case .tools: return app.t("test.placeholderTools")
        case .embedding: return app.t("test.placeholderEmbedding")
        }
    }

    private var resultTitle: String {
        switch mode {
        case .tools: return app.t("test.toolResult")
        case .embedding: return app.t("test.embeddingResult")
        default: return app.t("test.response")
        }
    }

    private var sendButtonTitle: String {
        switch mode {
        case .embedding: return app.t("button.test")
        default: return app.t("button.send")
        }
    }

    private var sendButtonIcon: String {
        switch mode {
        case .embedding: return "point.3.connected.trianglepath.dotted"
        case .tools: return "wrench.and.screwdriver"
        default: return "paperplane.fill"
        }
    }

    @ViewBuilder
    private var resultBlock: some View {
        if !response.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(resultTitle).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if let latency {
                        Text(String(format: "%.2fs", latency))
                            .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                Text(response).font(.callout).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func send() {
        let message = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }
        isLoading = true; response = ""; latency = nil
        let start = Date()
        let images = mode == .image ? selectedImageBase64.map { [$0] } ?? [] : []
        Task {
            let result: String
            switch mode {
            case .text, .image:
                result = await app.testChat(model: model, prompt: message, imageBase64List: images)
            case .tools:
                result = await app.testToolCall(model: model, prompt: message)
            case .embedding:
                result = await app.testEmbedding(model: model, input: message)
            }
            await MainActor.run {
                response = result
                latency = Date().timeIntervalSince(start)
                isLoading = false
            }
        }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK else { return }
        if let url = panel.url {
            setImage(url: url)
        }
    }

    private func pasteImage() {
        guard let image = NSPasteboard.general.readObjects(forClasses: [NSImage.self])?.first as? NSImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else {
            response = app.t("test.noImageOnClipboard")
            return
        }
        selectedImageName = app.t("test.pastedImage")
        selectedImageBase64 = data.base64EncodedString()
        selectedImagePreview = image
        applyImageDefaults()
    }

    private func setImage(url: URL) {
        do {
            let data = try Data(contentsOf: url)
            if let preview = NSImage(contentsOf: url) {
                selectedImageName = url.lastPathComponent
                selectedImageBase64 = data.base64EncodedString()
                selectedImagePreview = preview
                applyImageDefaults()
            }
        } catch {
            response = "⚠️ \(error.localizedDescription)"
        }
    }

    private func clearImage() {
        selectedImageName = ""
        selectedImageBase64 = nil
        selectedImagePreview = nil
    }

    private func applyImageDefaults() {
        if prompt.isEmpty || prompt == app.t("test.defaultPrompt") {
            prompt = app.t("test.defaultImagePrompt")
        }
        response = ""
    }

    private func defaultPrompt(for mode: TestMode) -> String {
        switch mode {
        case .text: return app.t("test.defaultPrompt")
        case .image: return app.t("test.defaultImagePrompt")
        case .tools: return app.t("test.defaultToolsPrompt")
        case .embedding: return app.t("test.defaultEmbeddingPrompt")
        }
    }

    private func prepareInitialState(clearResponse: Bool = false) {
        normalizeMode()
        if prompt.isEmpty {
            prompt = defaultPrompt(for: mode)
        }
        if clearResponse {
            response = ""
            latency = nil
        }
    }

    private func normalizeMode() {
        let modes = availableModes
        guard let first = modes.first else { return }
        guard !modes.contains(mode) else { return }
        let oldDefault = defaultPrompt(for: mode)
        mode = first
        if prompt.isEmpty || prompt == oldDefault {
            prompt = defaultPrompt(for: first)
        }
    }

    private func sameTag(_ lhs: String, _ rhs: String) -> Bool {
        lhs == rhs || normalized(lhs) == normalized(rhs)
    }

    private func normalized(_ tag: String) -> String {
        tag.contains(":") ? tag : tag + ":latest"
    }
}

// MARK: - Settings sheet

struct SettingsSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var confirmRemoveAll = false
    @State private var confirmReset = false
    @State private var showAdvanced = false

    private var keepAliveOptions: [(String, String)] {
        [
            ("5m", app.t("settings.fiveMin")),
            ("30m", app.t("settings.thirtyMin")),
            ("2h", app.t("settings.twoHours")),
            ("-1", app.t("settings.forever"))
        ]
    }

    private var contextOptions: [(Int, String)] {
        [(0, app.t("settings.contextAuto")), (8192, "8K"), (16384, "16K"), (32768, "32K"), (65536, "64K")]
    }

    private var languageSelection: Binding<AppLanguage> {
        Binding(get: { app.language }, set: { app.setLanguage($0) })
    }

    private var sortSelection: Binding<Library.Sort> {
        Binding(get: { app.sort }, set: { app.changeSort($0) })
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetTitleBar(title: app.t("settings.title"), systemImage: "gearshape") { dismiss() }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    SettingsGroup(title: app.t("settings.basic")) {
                        SettingsRow(title: app.t("settings.language"),
                                    subtitle: app.t("settings.languageSubtitle"),
                                    systemImage: "globe") {
                            Picker("", selection: languageSelection) {
                                ForEach(AppLanguage.allCases) { language in
                                    Text(language.label(language: app.language)).tag(language)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 250)
                        }

                        Divider().padding(.leading, 36)

                        SettingsRow(title: app.t("settings.launchAtLogin"),
                                    subtitle: app.t("settings.launchAtLoginSubtitle"),
                                    systemImage: "power") {
                            Toggle("", isOn: Binding(get: { app.launchAtLogin },
                                                     set: { app.setLaunchAtLogin($0) }))
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                    }

                    SettingsGroup(title: app.t("settings.agentPerf")) {
                        SettingsRow(title: app.t("settings.keepAlive"),
                                    subtitle: app.t("settings.keepAliveSubtitle"),
                                    systemImage: "bolt.fill") {
                            Picker("", selection: $app.keepAlive) {
                                ForEach(keepAliveOptions, id: \.0) { Text($0.1).tag($0.0) }
                            }
                            .labelsHidden().pickerStyle(.segmented).frame(width: 250)
                        }

                        Divider().padding(.leading, 36)

                        SettingsRow(title: app.t("settings.context"),
                                    subtitle: app.t("settings.contextSubtitle"),
                                    systemImage: "text.alignleft") {
                            Picker("", selection: $app.contextOverride) {
                                ForEach(contextOptions, id: \.0) { Text($0.1).tag($0.0) }
                            }
                            .labelsHidden().pickerStyle(.segmented).frame(width: 300)
                        }

                        Divider().padding(.leading, 36)

                        VStack(alignment: .leading, spacing: 8) {
                            Label(app.t("settings.warmup"), systemImage: "flame")
                                .font(.callout.weight(.semibold))
                            Text(app.t("settings.warmupSubtitle"))
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            TextEditor(text: $app.warmupPrompt)
                                .font(.callout.monospaced())
                                .frame(height: 88)
                                .scrollContentBackground(.hidden)
                                .padding(6)
                                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                                .overlay(alignment: .topLeading) {
                                    if app.warmupPrompt.isEmpty {
                                        Text(app.t("settings.warmupPlaceholder"))
                                            .font(.callout).foregroundStyle(.tertiary)
                                            .padding(.horizontal, 11).padding(.vertical, 10)
                                            .allowsHitTesting(false)
                                    }
                                }
                            HStack {
                                Button {
                                    if let name = app.running.first?.name { app.warmUp(name) }
                                } label: {
                                    Label(app.warming ? app.t("button.warming") : app.t("button.warmNow"),
                                          systemImage: "flame.fill")
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(app.warming || app.warmupPrompt.isEmpty || app.running.isEmpty)
                                Spacer()
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6)

                        if app.serverNeedsRestart {
                            Divider().padding(.leading, 36)
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.t("settings.restartNeeded")).font(.callout)
                                    Text(app.t("settings.restartWarning")).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(app.t("button.restartApply")) { app.restartServer() }
                                    .buttonStyle(.borderedProminent)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 6)
                        }
                    }

                    SettingsGroup(title: app.t("settings.ollama")) {
                        SettingsRow(title: runtimeTitle,
                                    subtitle: runtimeSubtitle,
                                    systemImage: app.serverReachable ? "checkmark.circle" : "power.circle") {
                            if !app.ollamaInstalled {
                                Button(app.t("button.install")) { app.installOllama() }
                                    .buttonStyle(.borderedProminent)
                            } else if !app.serverReachable {
                                Button(app.t("button.start")) { app.startServer() }
                                    .buttonStyle(.borderedProminent)
                            }
                        }
                        if app.serverReachable {
                            Divider().padding(.leading, 36)
                            SettingsRow(title: app.t("settings.modelLibrary"),
                                        subtitle: app.librarySyncedAt.map { app.t("sync.updated", Fmt.relative($0, language: app.language)) } ?? app.t("settings.notSynced"),
                                        systemImage: "square.grid.2x2") {
                                Text(app.t("settings.modelCount", app.models.count))
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    SettingsGroup(title: app.t("settings.storage")) {
                        SettingsRow(title: app.t("settings.downloadedModels"),
                                    subtitle: app.t("settings.downloadedModelsSubtitle"),
                                    systemImage: "externaldrive") {
                            Text(Fmt.bytes(app.installedBytes))
                                .font(.callout.weight(.medium).monospacedDigit())
                        }
                        if app.installedBytes > 0 {
                            Divider().padding(.leading, 36)
                            Button(role: .destructive) { confirmRemoveAll = true } label: {
                                Label(app.t("settings.removeAllModels"), systemImage: "trash")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .disabled(app.wiping)
                        }
                        if app.wiping {
                            Divider().padding(.leading, 36)
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text(app.t("settings.cleaning")).font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                        }
                    }
                    .confirmationDialog(app.t("settings.removeAllTitle", app.installed.count),
                                        isPresented: $confirmRemoveAll) {
                        Button(app.t("dock.removeButton", Fmt.bytes(app.installedBytes)), role: .destructive) {
                            app.removeAllModels()
                        }
                    } message: {
                        Text(app.t("settings.removeAllMessage"))
                    }

                    advancedSection
                    .confirmationDialog(app.t("settings.resetTitle"), isPresented: $confirmReset) {
                        Button(app.t("settings.resetButton"), role: .destructive) {
                            app.resetHost()
                        }
                    } message: {
                        Text(app.t("settings.resetMessage"))
                    }
                }
                .padding(18)
            }
        }
        .frame(width: 560, height: 560)
    }

    private var recentHistory: [HistoryEntry] {
        Array(app.history.prefix(12))
    }

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    showAdvanced.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .rotationEffect(.degrees(showAdvanced ? 90 : 0))
                    Text(app.t("settings.advanced"))
                        .font(.callout.weight(.medium))
                    Spacer()
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            if showAdvanced {
                SettingsGroup(title: app.t("settings.advanced")) {
                    SettingsRow(title: app.t("settings.modelList"),
                                subtitle: app.t("settings.modelListSubtitle"),
                                systemImage: "arrow.clockwise") {
                        HStack(spacing: 8) {
                            Picker("", selection: sortSelection) {
                                ForEach(Library.Sort.allCases) { Text($0.label(language: app.language)).tag($0) }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .fixedSize()
                            Button { Task { await app.syncLibrary() } } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .disabled(app.syncing)
                        }
                    }
                    if let e = app.syncError {
                        Text(e).font(.caption).foregroundStyle(.red).padding(.leading, 48)
                    }

                    if let path = app.ollamaPath {
                        Divider().padding(.leading, 36)
                        CopyField(label: app.t("settings.binary"), value: path)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }

                    Divider().padding(.leading, 36)

                    SettingsRow(title: app.t("settings.history"),
                                subtitle: app.history.isEmpty ? app.t("settings.nothingYet") : app.t("settings.historyCount", app.history.count),
                                systemImage: "clock.arrow.circlepath") {
                        if !app.history.isEmpty {
                            Button(app.t("button.clearHistory")) { app.clearHistory() }
                                .buttonStyle(.bordered)
                        }
                    }

                    if !app.history.isEmpty {
                        historyPreview
                    }

                    Divider().padding(.leading, 36)

                    Button(role: .destructive) { confirmReset = true } label: {
                        Label(app.t("settings.resetHost"), systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(!app.ollamaInstalled || app.wiping)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var historyPreview: some View {
        VStack(spacing: 0) {
            ForEach(recentHistory) { entry in
                HistoryRow(entry: entry)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                if entry.id != recentHistory.last?.id {
                    Divider().padding(.leading, 40)
                }
            }
        }
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private var runtimeTitle: String {
        if app.serverReachable { return app.t("runtime.ready") }
        if app.ollamaInstalled { return app.t("runtime.installedNotRunning") }
        return app.t("runtime.notInstalled")
    }

    private var runtimeSubtitle: String {
        if app.serverReachable { return app.t("runtime.running", app.serverVersion ?? "") }
        if app.ollamaInstalled { return app.t("runtime.startHint") }
        return app.t("runtime.installHint")
    }
}

private struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            VStack(spacing: 0) {
                content
            }
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.58),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1))
        }
    }
}

private struct SettingsRow<Trailing: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium))
                if !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

struct HistoryRow: View {
    @EnvironmentObject var app: AppState
    let entry: HistoryEntry
    private var showsTag: Bool { entry.action != .wiped && entry.action != .cleared }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: entry.action.symbol)
                .foregroundStyle(entry.action.color).font(.callout)
            Text(entry.action.verb(language: app.language)).font(.caption.weight(.medium))
            if showsTag {
                Text(entry.tag)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(Fmt.relative(entry.at, language: app.language)).font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
