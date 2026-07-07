import SwiftUI
import ServiceManagement
import AppKit

// MARK: - Launch at login (ServiceManagement)

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    @discardableResult
    static func set(_ on: Bool) -> Bool {
        do {
            if on {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
            return true
        } catch {
            return false
        }
    }
}

// MARK: - Menu bar panel

struct StatusBarInstaller: View {
    @EnvironmentObject var app: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                StatusBarController.shared.install(app: app) {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
            .onChange(of: app.running.isEmpty) { _, isEmpty in
                StatusBarController.shared.update(running: !isEmpty)
            }
            .onChange(of: app.serverReachable) { _, _ in
                StatusBarController.shared.refreshPanel(app: app)
            }
            .onChange(of: app.language) { _, _ in
                StatusBarController.shared.refreshPanel(app: app)
            }
    }
}

@MainActor
final class StatusBarController: NSObject {
    static let shared = StatusBarController()

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var openMainWindow: (() -> Void)?
    private weak var appState: AppState?
    private let panelWidth: CGFloat = 236
    private let collapsedHeight: CGFloat = 284

    func install(app: AppState, openMainWindow: @escaping () -> Void) {
        appState = app
        self.openMainWindow = openMainWindow
        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            statusItem = item
            item.button?.target = self
            item.button?.action = #selector(togglePopover)
            item.button?.imagePosition = .imageLeading
            item.button?.font = .systemFont(ofSize: 12, weight: .semibold)
        }
        popover.behavior = .transient
        resizePanel(expanded: false, rows: 0)
        refreshPanel(app: app)
        update(running: !app.running.isEmpty)
    }

    func refreshPanel(app: AppState) {
        let root = MenuBarPanel(openMainWindow: openMainWindow)
            .environmentObject(app)
            .environment(\.locale, app.language.locale)
            .tint(Brand.accent)
        popover.contentViewController = NSHostingController(rootView: root)
    }

    func update(running: Bool) {
        guard let button = statusItem?.button else { return }
        button.image = Self.statusIcon(active: running)
        button.title = "MC"
        button.toolTip = "ModelChanges"
    }

    func resizePanel(expanded: Bool, rows: Int) {
        let listHeight = expanded ? min(CGFloat(max(rows, 1)) * 28, 116) + 8 : 0
        popover.contentSize = NSSize(width: panelWidth, height: collapsedHeight + listHeight)
    }

    private static func statusIcon(active: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 3.0, y: 7.0))
        path.curve(to: NSPoint(x: 7.3, y: 11.0),
                   controlPoint1: NSPoint(x: 4.6, y: 7.0),
                   controlPoint2: NSPoint(x: 5.2, y: 11.0))
        path.curve(to: NSPoint(x: 11.0, y: 7.2),
                   controlPoint1: NSPoint(x: 9.0, y: 11.0),
                   controlPoint2: NSPoint(x: 9.2, y: 7.2))
        path.curve(to: NSPoint(x: 15.0, y: 11.3),
                   controlPoint1: NSPoint(x: 12.8, y: 7.2),
                   controlPoint2: NSPoint(x: 13.2, y: 11.3))
        path.lineWidth = 2.4
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        (active ? Brand.accentNS : NSColor.labelColor).withAlphaComponent(active ? 1 : 0.78).setStroke()
        path.stroke()

        func dot(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ color: NSColor) {
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: x - r, y: y - r, width: r * 2, height: r * 2)).fill()
        }
        dot(3, 7, 2.0, active ? Brand.highlightNS : NSColor.labelColor.withAlphaComponent(0.78))
        dot(15, 11.3, 2.3, active ? Brand.accentNS : NSColor.labelColor.withAlphaComponent(0.88))
        image.unlockFocus()
        image.isTemplate = !active
        return image
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            if let appState {
                refreshPanel(app: appState)
                resizePanel(expanded: false, rows: appState.installed.count)
                Task { await appState.refresh() }
            }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

struct MenuBarPanel: View {
    @EnvironmentObject var app: AppState
    @Environment(\.openWindow) private var openWindow
    var openMainWindow: (() -> Void)? = nil
    @State private var showStartable = false

    private var deploying: [DeployProgress] {
        app.deployments.values
            .filter { $0.phase == .pulling || $0.phase == .loading }
            .sorted { $0.tag < $1.tag }
    }
    private var startable: [InstalledModel] {
        app.installed.filter { !app.isRunning($0.name) }
    }
    private var usedGB: Double { Double(app.loadedBytes) / 1_073_741_824 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
                .contentShape(Rectangle())
                .onTapGesture { showStartable = false }

            if app.serverReachable {
                memoryLine
                    .contentShape(Rectangle())
                    .onTapGesture { showStartable = false }
            } else {
                offlineRow
            }

            Divider()

            if app.running.isEmpty && deploying.isEmpty {
                Label(app.t("menu.noModelsLoaded"), systemImage: "moon.zzz")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 1)
                    .contentShape(Rectangle())
                    .onTapGesture { showStartable = false }
            } else {
                VStack(spacing: 5) {
                    ForEach(deploying) { p in deployRow(p) }
                    ForEach(app.running) { m in runningRow(m) }
                }
            }

            if app.serverReachable && !startable.isEmpty {
                startModelSection
            }

            Divider()

            Toggle(isOn: Binding(get: { app.launchAtLogin },
                                 set: {
                                     showStartable = false
                                     app.setLaunchAtLogin($0)
                                 })) {
                Label(app.t("menu.launchAtLogin"), systemImage: "power")
            }
            .toggleStyle(.switch).controlSize(.mini)
            .font(.caption)

            HStack(spacing: 8) {
                Button {
                    showStartable = false
                    if let openMainWindow {
                        openMainWindow()
                    } else {
                        openWindow(id: "main")
                    }
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Label(app.t("menu.openApp"), systemImage: "macwindow")
                }
                .controlSize(.small)
                Spacer()
                Button(app.t("button.quit")) {
                    showStartable = false
                    NSApp.terminate(nil)
                }
                    .controlSize(.small)
                    .keyboardShortcut("q")
            }
            .font(.caption)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: 236)
        .onAppear {
            showStartable = false
            StatusBarController.shared.resizePanel(expanded: false, rows: startable.count)
            Task {
                await app.refresh()
                StatusBarController.shared.resizePanel(expanded: showStartable, rows: startable.count)
            }
        }
        .onDisappear {
            showStartable = false
            StatusBarController.shared.resizePanel(expanded: false, rows: 0)
        }
        .onChange(of: showStartable) { _, expanded in
            StatusBarController.shared.resizePanel(expanded: expanded, rows: startable.count)
        }
        .onChange(of: startable.count) { _, count in
            if count == 0 { showStartable = false }
            StatusBarController.shared.resizePanel(expanded: showStartable, rows: count)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            ModelChangesLogo(size: 16)
            Text("ModelChanges").font(.subheadline.weight(.semibold))
            Spacer()
            Circle().fill(app.serverReachable ? .green : (app.ollamaInstalled ? .orange : .red))
                .frame(width: 7, height: 7)
            Text(app.serverReachable ? app.t("menu.on") : app.t("menu.off")).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var memoryLine: some View {
        let frac = min(1, usedGB / max(1, app.ramGB))
        let color: Color = frac < 0.72 ? .green : (frac < 0.92 ? .orange : .red)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(app.t("menu.loadedCount", app.running.count)).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(String(format: usedGB < 10 ? "%.1f" : "%.0f", usedGB)) / \(Int(app.ramGB)) GB")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary).frame(height: 4)
                GeometryReader { geo in
                    Capsule().fill(color).frame(width: max(2, geo.size.width * frac), height: 4)
                }.frame(height: 4)
            }
        }
    }

    private var offlineRow: some View {
        HStack {
            Text(app.ollamaInstalled ? app.t("menu.serverNotRunning") : app.t("menu.ollamaNotInstalled"))
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button(app.ollamaInstalled ? app.t("button.start") : app.t("button.install")) {
                showStartable = false
                app.ollamaInstalled ? app.startServer() : app.installOllama()
            }.controlSize(.small)
        }
    }

    private var startModelSection: some View {
        let listHeight = min(CGFloat(startable.count) * 28, 116)
        return VStack(alignment: .leading, spacing: 5) {
            if showStartable {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(startable) { model in
                            startModelRow(model)
                        }
                    }
                }
                .scrollIndicators(.never)
                .frame(height: listHeight)
                .layoutPriority(1)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Button {
                withAnimation(.easeInOut(duration: 0.12)) {
                    showStartable.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.circle")
                        .font(.callout)
                    Text(app.t("menu.startInstalled"))
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(showStartable ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func startModelRow(_ model: InstalledModel) -> some View {
        Button {
            showStartable = false
            app.deploy(model.name)
        } label: {
            HStack(spacing: 6) {
                Text(model.name)
                    .font(.caption2.monospaced())
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(Fmt.bytes(model.size))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func runningRow(_ m: RunningModel) -> some View {
        HStack(spacing: 6) {
            Circle().fill(.green).frame(width: 6, height: 6)
            Text(m.name).font(.caption2.monospaced()).lineLimit(1)
            Spacer()
            Text(Fmt.bytes(m.size)).font(.caption2).foregroundStyle(.secondary)
            Button {
                showStartable = false
                app.stop(m.name)
            } label: {
                Image(systemName: "stop.circle.fill").font(.caption)
            }.buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture { showStartable = false }
    }

    private func deployRow(_ p: DeployProgress) -> some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small).scaleEffect(0.6).frame(width: 10, height: 10)
            Text(p.tag).font(.caption2.monospaced()).lineLimit(1)
            Spacer()
            Text(p.phase == .loading ? app.t("dock.loading") : (p.total > 0 ? "\(Int(p.fraction * 100))%" : "…"))
                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            Button {
                showStartable = false
                app.cancelDeploy(p.tag)
            } label: {
                Image(systemName: "xmark.circle.fill")
            }.buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture { showStartable = false }
    }
}
