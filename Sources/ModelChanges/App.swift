import SwiftUI
import AppKit

@main
struct ModelChangesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var app = AppState()

    var body: some Scene {
        // A single Window (not WindowGroup) so "Open" focuses the existing
        // window instead of spawning duplicates.
        Window("ModelChanges", id: "main") {
            RootView()
                .environmentObject(app)
                .environment(\.locale, app.language.locale)
                .tint(Brand.accent)
                .frame(minWidth: 800, minHeight: 540)
                .background(StatusBarInstaller().environmentObject(app))
                .task {
                    app.startServer()        // launch the bundled Ollama runtime
                    app.startPolling()
                    app.startLibrarySync()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1000, height: 680)

    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    // Keep running in the menu bar after the window is closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // Stop the bundled Ollama server when the app quits — nothing left running.
    func applicationWillTerminate(_ notification: Notification) {
        BundledServer.shared.stop()
    }

    // Clicking the Dock icon restores the existing window instead of nothing.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows where window.canBecomeMain {
                window.makeKeyAndOrderFront(nil)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
        return true
    }
}

// MARK: - Import banner

struct ImportBanner: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.and.arrow.down.on.square")
                .foregroundStyle(Brand.accent)
            Text(app.t("import.title", app.importableModels.count))
                .font(.callout)
            Spacer(minLength: 8)
            if app.importing {
                ProgressView().controlSize(.small)
            } else {
                Button(app.t("import.button")) { app.importLegacyModels() }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                Button(app.t("import.dismiss")) { app.dismissImport() }
                    .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Brand.accent.opacity(0.08))
    }
}

// MARK: - Brand

enum Brand {
    static let accent = Color(red: 0.02, green: 0.64, blue: 0.55)
    static let highlight = Color(red: 0.56, green: 1.0, blue: 0.70)
    static let deepTeal = Color(red: 0.04, green: 0.30, blue: 0.27)
    static let accentNS = NSColor(calibratedRed: 0.02, green: 0.64, blue: 0.55, alpha: 1)
    static let highlightNS = NSColor(calibratedRed: 0.56, green: 1.0, blue: 0.70, alpha: 1)
    static let gradient = LinearGradient(
        colors: [Brand.deepTeal, Brand.accent, Brand.highlight],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

// MARK: - Root

struct RootView: View {
    @EnvironmentObject var app: AppState
    @State private var search = ""
    @State private var typeFilter: ModelType?
    @State private var selected: LiveModel?
    @State private var showEndpoint = false
    @State private var showSettings = false

    private var filtered: [LiveModel] {
        app.models.filter { m in
            if let typeFilter, !m.types.contains(typeFilter) { return false }
            if !search.isEmpty {
                let hay = (m.name + " " + m.developer + " " + m.summary).lowercased()
                if !hay.contains(search.lowercased()) { return false }
            }
            return true
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                header
                Divider().opacity(0.5)
                filterBar
                Divider().opacity(0.5)
                if !app.importableModels.isEmpty && !app.importDismissed {
                    ImportBanner()
                    Divider().opacity(0.5)
                }
                ModelGrid(models: filtered, selected: $selected)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                RunningDock(showEndpoint: $showEndpoint)
            }
            ErrorBanner()
        }
        .background(WindowBackground())
        .inspector(isPresented: Binding(
            get: { selected != nil },
            set: { if !$0 { selected = nil } })) {
                Group {
                    if let selected {
                        ModelInspector(model: selected) { self.selected = nil }
                    }
                }
                .inspectorColumnWidth(min: 340, ideal: 390, max: 480)
            }
        .sheet(isPresented: $showEndpoint) { EndpointSheet() }
        .sheet(isPresented: $showSettings) { SettingsSheet() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            BrandMark()
            Spacer(minLength: 12)
            SyncButton()
            StatusPill(openSettings: { showSettings = true })
            ToolbarIconButton(system: "bolt.horizontal.fill", help: app.t("toolbar.endpointHelp")) { showEndpoint = true }
            ToolbarIconButton(system: "gearshape", help: app.t("toolbar.settings")) { showSettings = true }
        }
        .padding(.leading, 82)
        .padding(.trailing, 14)
        .padding(.top, 11)
        .padding(.bottom, 9)
    }

    // MARK: Filter bar

    private var filterBar: some View {
        HStack(spacing: 12) {
            SearchField(text: $search)
            TypeFilterBar(selected: $typeFilter)
            Spacer(minLength: 8)
            Text("\(filtered.count)")
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(.secondary)
            SortMenu()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }
}

/// Subtle vibrant window background.
struct WindowBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .underWindowBackground
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Brand mark

struct BrandMark: View {
    var body: some View {
        HStack(spacing: 8) {
            ModelChangesLogo(size: 22)
            Text("ModelChanges").font(.headline).fontWeight(.semibold)
        }
    }
}

struct ModelChangesLogo: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(LinearGradient(
                    colors: [
                        Color(red: 0.07, green: 0.11, blue: 0.13),
                        Brand.deepTeal
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                Path { p in
                    p.move(to: CGPoint(x: w * 0.20, y: h * 0.58))
                    p.addCurve(to: CGPoint(x: w * 0.40, y: h * 0.40),
                               control1: CGPoint(x: w * 0.28, y: h * 0.57),
                               control2: CGPoint(x: w * 0.31, y: h * 0.39))
                    p.addCurve(to: CGPoint(x: w * 0.58, y: h * 0.57),
                               control1: CGPoint(x: w * 0.48, y: h * 0.40),
                               control2: CGPoint(x: w * 0.49, y: h * 0.58))
                    p.addCurve(to: CGPoint(x: w * 0.80, y: h * 0.38),
                               control1: CGPoint(x: w * 0.67, y: h * 0.56),
                               control2: CGPoint(x: w * 0.70, y: h * 0.38))
                }
                .stroke(.white.opacity(0.94), style: StrokeStyle(lineWidth: max(2, size * 0.13), lineCap: .round, lineJoin: .round))

                Circle()
                    .fill(Brand.highlight)
                    .frame(width: w * 0.22, height: h * 0.22)
                    .position(x: w * 0.20, y: h * 0.58)
                Circle()
                    .fill(.white)
                    .frame(width: w * 0.24, height: h * 0.24)
                    .overlay(Circle().stroke(Brand.highlight, lineWidth: max(1, size * 0.045)))
                    .position(x: w * 0.80, y: h * 0.38)
            }
            .padding(size * 0.16)
        }
        .frame(width: size, height: size)
        .shadow(color: Color(red: 0.02, green: 0.25, blue: 0.22).opacity(0.35), radius: 3, y: 1)
    }
}

// MARK: - Status pill

struct StatusPill: View {
    @EnvironmentObject var app: AppState
    var openSettings: () -> Void

    private var info: (Color, String) {
        if app.serverReachable { return (.green, "Ollama \(app.serverVersion ?? "")") }
        if app.ollamaInstalled { return (.orange, app.t("status.startServer")) }
        return (.red, app.t("status.installOllama"))
    }

    var body: some View {
        Button {
            if app.serverReachable { openSettings() }
            else if app.ollamaInstalled { app.startServer() }
            else { app.installOllama() }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(info.0).frame(width: 7, height: 7)
                Text(info.1).font(.caption.weight(.medium))
                if !app.serverReachable {
                    Image(systemName: "arrow.right.circle.fill").font(.caption2)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(info.0.opacity(0.14), in: Capsule())
            .foregroundStyle(app.serverReachable ? Color.primary : info.0)
        }
        .buttonStyle(.plain)
        .help(app.serverReachable
              ? app.t("status.localRuntimeLive")
              : app.t(app.ollamaInstalled ? "status.clickToStart" : "status.clickToInstall"))
    }
}

// MARK: - Sync button

struct SyncButton: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        Button { Task { await app.syncLibrary() } } label: {
            HStack(spacing: 5) {
                if app.syncing {
                    ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 12, height: 12)
                } else {
                    Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .medium))
                }
                Text(app.syncing ? app.t("sync.syncing")
                     : (app.librarySyncedAt.map { app.t("sync.updated", Fmt.relative($0, language: app.language)) } ?? app.t("sync.action")))
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .disabled(app.syncing)
        .help(app.t("sync.refreshHelp"))
    }
}

// MARK: - Icon button

struct ToolbarIconButton: View {
    let system: String
    let help: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 28)
                .background(hover ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                            in: RoundedRectangle(cornerRadius: 7))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}

// MARK: - Search field

struct SearchField: View {
    @EnvironmentObject var app: AppState
    @Binding var text: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.caption).foregroundStyle(.secondary)
            TextField(app.t("search.placeholder"), text: $text).textFieldStyle(.plain).font(.callout)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(width: 230)
        .background(.quaternary.opacity(0.5), in: Capsule())
    }
}

// MARK: - Type filter

struct TypeFilterBar: View {
    @EnvironmentObject var app: AppState
    @Binding var selected: ModelType?
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                pill(nil, app.t("filter.all"), "square.grid.2x2")
                ForEach(ModelType.allCases) { pill($0, $0.label(language: app.language), $0.symbol) }
            }
        }
    }

    private func pill(_ type: ModelType?, _ label: String, _ symbol: String) -> some View {
        let active = selected == type
        let tint = type?.tint ?? Brand.accent
        return Button {
            withAnimation(.snappy(duration: 0.15)) { selected = active ? nil : type }
        } label: {
            Label(label, systemImage: symbol)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(active ? AnyShapeStyle(tint.opacity(0.18)) : AnyShapeStyle(.clear), in: Capsule())
                .overlay(Capsule().stroke(Color.secondary.opacity(active ? 0 : 0.25), lineWidth: 1))
                .foregroundStyle(active ? tint : .secondary)
        }
        .buttonStyle(.plain)
        .fixedSize()
    }
}

// MARK: - Sort menu

struct SortMenu: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        Menu {
            ForEach(Library.Sort.allCases) { s in
                Button {
                    app.changeSort(s)
                } label: {
                    if app.sort == s { Label(s.label(language: app.language), systemImage: "checkmark") }
                    else { Text(s.label(language: app.language)) }
                }
            }
        } label: {
            Label(app.sort.label(language: app.language), systemImage: "arrow.up.arrow.down").font(.caption.weight(.medium))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

// MARK: - Error banner

struct ErrorBanner: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        if let error = app.lastError {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.white)
                Text(error).font(.callout).foregroundStyle(.white).lineLimit(2)
                Spacer(minLength: 8)
                Button { app.lastError = nil } label: {
                    Image(systemName: "xmark").foregroundStyle(.white)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Color.red.opacity(0.92), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16).padding(.top, 56)
            .shadow(radius: 10, y: 3)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

// MARK: - Shared style

extension ModelType {
    var tint: Color {
        switch self {
        case .chat: return Brand.accent
        case .code: return Color(red: 0.03, green: 0.48, blue: 0.43)
        case .vision: return Color(red: 0.12, green: 0.72, blue: 0.68)
        case .reasoning: return Color(red: 0.92, green: 0.58, blue: 0.20)
        case .embedding: return Color(red: 0.38, green: 0.82, blue: 0.47)
        case .audio: return Color(red: 0.20, green: 0.66, blue: 0.82)
        }
    }
}

extension FitStatus {
    var color: Color {
        switch self {
        case .fits: return .green
        case .tight: return .orange
        case .tooBig: return .red
        }
    }
}

extension HistoryAction {
    var color: Color {
        switch self {
        case .deployed: return Brand.accent
        case .started: return .green
        case .stopped: return .orange
        case .removed, .cleared: return .red
        case .wiped: return .pink
        }
    }
}

struct TypeBadge: View {
    @EnvironmentObject var app: AppState
    let type: ModelType
    var body: some View {
        Label(type.label(language: app.language), systemImage: type.symbol)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(type.tint.opacity(0.16), in: Capsule())
            .foregroundStyle(type.tint)
    }
}

struct Chip: View {
    let text: String
    var systemImage: String? = nil
    var tint: Color = .secondary
    var body: some View {
        HStack(spacing: 3) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 7)) }
            Text(text)
        }
        .font(.caption2)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(tint == .secondary ? AnyShapeStyle(.quaternary.opacity(0.5)) : AnyShapeStyle(tint.opacity(0.16)),
                    in: Capsule())
        .foregroundStyle(tint)
    }
}
