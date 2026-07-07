import SwiftUI

struct RunningDock: View {
    @EnvironmentObject var app: AppState
    @Binding var showEndpoint: Bool
    @State private var showInstalled = false
    @State private var installedButtonHover = false
    @State private var installedPopoverHover = false
    @State private var installedCloseTask: Task<Void, Never>?

    private var deploying: [DeployProgress] {
        app.deployments.values
            .filter { $0.phase == .pulling || $0.phase == .loading }
            .sorted { $0.tag < $1.tag }
    }

    private var isEmpty: Bool {
        app.running.isEmpty && deploying.isEmpty && app.installed.isEmpty
    }

    var body: some View {
        if isEmpty {
            EmptyView()
        } else {
            VStack(spacing: 0) {
                Divider().opacity(0.5)
                HStack(spacing: 10) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(deploying) { DeployPill(progress: $0) }
                            ForEach(app.running) { RunningPill(model: $0) }
                            if app.running.isEmpty && deploying.isEmpty {
                                Text(app.t("dock.nothingLoaded"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    Spacer(minLength: 6)

                    if app.serverReachable { MemoryMeter(); Divider().frame(height: 22) }

                    Button {
                        installedCloseTask?.cancel()
                        showInstalled.toggle()
                    } label: {
                        Label("\(app.installed.count)", systemImage: "internaldrive")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .onHover { setInstalledButtonHover($0) }
                    .help(app.t("dock.installedHelp", Fmt.bytes(app.installedBytes)))
                    .popover(isPresented: $showInstalled, arrowEdge: .bottom) {
                        InstalledPopover()
                            .onHover { setInstalledPopoverHover($0) }
                    }

                    Button { showEndpoint = true } label: {
                        Label(app.t("dock.connect"), systemImage: "bolt.horizontal.fill").font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .disabled(!app.serverReachable)
                    .help(app.t("dock.connectHelp"))
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
            }
            .background(.bar)
        }
    }

    private func setInstalledButtonHover(_ hovering: Bool) {
        installedButtonHover = hovering
        if hovering {
            installedCloseTask?.cancel()
            showInstalled = true
        } else {
            scheduleInstalledClose()
        }
    }

    private func setInstalledPopoverHover(_ hovering: Bool) {
        installedPopoverHover = hovering
        if hovering {
            installedCloseTask?.cancel()
        } else {
            scheduleInstalledClose()
        }
    }

    private func scheduleInstalledClose() {
        installedCloseTask?.cancel()
        installedCloseTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            await MainActor.run {
                if !installedButtonHover && !installedPopoverHover {
                    showInstalled = false
                }
            }
        }
    }
}

/// Live memory-headroom meter — dynamic to this machine's RAM and current load.
struct MemoryMeter: View {
    @EnvironmentObject var app: AppState

    private var usedGB: Double { Double(app.loadedBytes) / 1_073_741_824 }
    private var frac: Double { min(1, usedGB / max(1, app.ramGB)) }
    private var color: Color { frac < 0.72 ? .green : (frac < 0.92 ? .orange : .red) }

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text("\(String(format: usedGB < 10 ? "%.1f" : "%.0f", usedGB)) / \(Int(app.ramGB)) GB")
                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary).frame(width: 96, height: 4)
                Capsule().fill(color).frame(width: max(2, 96 * frac), height: 4)
            }
        }
        .help(app.t("dock.memoryHelp", Fmt.bytes(app.loadedBytes), Int(app.ramGB)))
    }
}

struct RunningPill: View {
    @EnvironmentObject var app: AppState
    let model: RunningModel
    @State private var hover = false

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(.green).frame(width: 7, height: 7)
                .shadow(color: .green.opacity(0.7), radius: 2)
            Text(model.name).font(.caption.weight(.medium).monospaced()).lineLimit(1)
            Text(Fmt.bytes(model.size)).font(.caption2).foregroundStyle(.secondary)
            Button { app.stop(model.name) } label: {
                Image(systemName: "stop.circle.fill").font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .foregroundStyle(hover ? .red : .secondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(.green.opacity(0.10), in: Capsule())
        .overlay(Capsule().stroke(.green.opacity(0.3), lineWidth: 1))
        .onHover { hover = $0 }
        .help("\(model.name) · \(Int(model.gpuFraction * 100))% on GPU")
    }
}

struct DeployPill: View {
    @EnvironmentObject var app: AppState
    let progress: DeployProgress

    var body: some View {
        HStack(spacing: 7) {
            ProgressView().controlSize(.small).scaleEffect(0.6).frame(width: 12, height: 12)
            Text(progress.tag).font(.caption.weight(.medium).monospaced()).lineLimit(1)
            Text(progress.phase == .loading ? app.t("dock.loading")
                 : (progress.total > 0 ? "\(Int(progress.fraction * 100))%" : "…"))
                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            Button { app.cancelDeploy(progress.tag) } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 12))
            }.buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Brand.accent.opacity(0.12), in: Capsule())
        .overlay(Capsule().stroke(Brand.accent.opacity(0.3), lineWidth: 1))
    }
}

struct InstalledPopover: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(app.t("dock.installedModels")).font(.headline)
                Spacer()
                Text(Fmt.bytes(app.installedBytes)).font(.caption).foregroundStyle(.secondary)
            }
            if app.installed.isEmpty {
                Text(app.t("dock.noModelsDownloaded")).font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(app.installed) { InstalledRow(model: $0) }
                    }
                }
                .frame(maxHeight: 320)
            }
        }
        .padding(14)
        .frame(width: 360)
    }
}

struct InstalledRow: View {
    @EnvironmentObject var app: AppState
    let model: InstalledModel
    @State private var confirmRemove = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "shippingbox.fill").foregroundStyle(Brand.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.name).font(.callout.weight(.medium).monospaced()).lineLimit(1)
                HStack(spacing: 8) {
                    Text(Fmt.bytes(model.size))
                    if let p = model.details?.parameterSize { Text(p) }
                    if let q = model.details?.quantizationLevel { Text(q) }
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if app.isRunning(model.name) {
                Button { app.stop(model.name) } label: { Image(systemName: "stop.fill") }
                    .controlSize(.small).tint(.red).help(app.t("dock.stopHelp"))
            } else {
                Button { app.deploy(model.name) } label: { Image(systemName: "play.fill") }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .disabled(!app.serverReachable).help(app.t("dock.loadHelp"))
            }
            Button(role: .destructive) { confirmRemove = true } label: { Image(systemName: "trash") }
                .controlSize(.small).help(app.t("dock.deleteHelp"))
                .confirmationDialog(app.t("dock.removeTitle", model.name), isPresented: $confirmRemove) {
                    Button(app.t("dock.removeButton", Fmt.bytes(model.size)), role: .destructive) { app.remove(model.name) }
                }
        }
        .padding(8)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
    }
}
