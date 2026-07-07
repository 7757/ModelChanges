import SwiftUI

struct ModelInspector: View {
    @EnvironmentObject var app: AppState
    let model: LiveModel
    var onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if !model.summary.isEmpty {
                    Text(model.summary)
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                statsRow
                if !model.capabilities.isEmpty { capabilities }
                Divider()
                deploySection
                footer
            }
            .padding(18)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.name).font(.title2.bold())
                    if !model.developer.isEmpty {
                        Text(model.developer).font(.callout).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .medium))
                        .frame(width: 24, height: 24)
                        .background(.quaternary, in: Circle())
                }.buttonStyle(.plain).foregroundStyle(.secondary)
            }
            HStack(spacing: 5) {
                ForEach(model.types, id: \.self) { TypeBadge(type: $0) }
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            stat("arrow.down.circle", model.pulls, app.t("inspector.pulls"))
            Divider().frame(height: 30)
            stat("number", "\(model.tagCount)", app.t("inspector.tags"))
            Divider().frame(height: 30)
            stat("clock", model.updated.isEmpty ? "—" : model.updated, app.t("inspector.updated"))
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
    }

    private func stat(_ symbol: String, _ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Label(value, systemImage: symbol)
                .font(.callout.weight(.semibold)).labelStyle(.titleAndIcon)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var capabilities: some View {
        FlowLayout(spacing: 6) {
            ForEach(model.capabilities, id: \.self) { Chip(text: $0, systemImage: "sparkle") }
        }
    }

    private var deploySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(app.t("inspector.deploy")).font(.headline)
                Spacer()
                Text(app.t("inspector.deployHint"))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            ForEach(model.variants) { variant in
                InspectorVariantRow(variant: variant)
            }
            Text(app.t("inspector.sizeHint"))
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private var footer: some View {
        HStack {
            if let url = URL(string: "https://ollama.com/library/\(model.name)") {
                Link(destination: url) {
                    Label(app.t("inspector.viewOnOllama"), systemImage: "arrow.up.right.square").font(.caption)
                }
            }
            Spacer()
        }
    }
}

struct InspectorVariantRow: View {
    @EnvironmentObject var app: AppState
    let variant: LiveVariant

    private var fit: FitStatus { Hardware.fit(estRAMGB: variant.estRAMGB, ramGB: app.ramGB) }
    private var unavailable: Bool { app.unavailableTags.contains(variant.tag) }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(variant.tag).font(.callout.weight(.semibold).monospaced()).lineLimit(1)
                        if app.isRunning(variant.tag) {
                            Chip(text: app.t("chip.running"), systemImage: "circle.fill", tint: .green)
                        } else if app.isInstalled(variant.tag) {
                            Chip(text: app.t("chip.installed"), systemImage: "internaldrive")
                        }
                    }
                    HStack(spacing: 8) {
                        if unavailable {
                            Label(app.t("badge.unavailable"), systemImage: "xmark.octagon.fill")
                                .foregroundStyle(.red)
                        } else {
                            if variant.estDiskGB > 0 {
                                Label("~\(Fmt.gb(variant.estDiskGB))", systemImage: "arrow.down.circle")
                                Label(app.t("inspector.ram", Fmt.gb(variant.estRAMGB)), systemImage: "memorychip")
                            }
                            Label(fit.label(language: app.language), systemImage: fit.symbol)
                                .foregroundStyle(fit.color)
                        }
                    }
                    .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                VariantActionButton(tag: variant.tag, fit: fit, unavailable: unavailable)
            }
            if let progress = app.deployments[variant.tag] {
                DeployProgressView(progress: progress)
            }
        }
        .padding(11)
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(app.isRunning(variant.tag) ? Color.green.opacity(0.4) : .clear, lineWidth: 1.5))
    }
}

struct VariantActionButton: View {
    @EnvironmentObject var app: AppState
    let tag: String
    var fit: FitStatus = .fits
    var unavailable: Bool = false

    var body: some View {
        let progress = app.deployments[tag]
        let deploying = progress != nil && progress?.phase != .done && progress?.phase != .failed

        if deploying {
            Button(role: .cancel) { app.cancelDeploy(tag) } label: {
                Label(app.t("button.cancel"), systemImage: "xmark")
            }.controlSize(.small)
        } else if app.isRunning(tag) {
            Button { app.stop(tag) } label: {
                Label(app.t("button.stop"), systemImage: "stop.fill")
            }.controlSize(.small).tint(.red)
        } else if app.isInstalled(tag) {
            Button { app.deploy(tag) } label: {
                Label(app.t("button.start"), systemImage: "play.fill")
            }.buttonStyle(.borderedProminent).controlSize(.small).disabled(!app.serverReachable)
        } else if unavailable {
            Button { } label: { Label(app.t("button.unavailable"), systemImage: "xmark.octagon") }
                .controlSize(.small).disabled(true)
                .help(app.t("error.modelNotPullable", tag))
        } else if fit == .tooBig {
            Button { } label: { Label(app.t("button.tooLarge"), systemImage: "xmark.octagon") }
                .controlSize(.small).disabled(true)
                .help(app.t("inspector.tooLargeHelp", Int(app.ramGB)))
        } else {
            Button { app.deploy(tag) } label: {
                Label(app.t("button.deploy"), systemImage: "arrow.down.circle.fill")
            }.buttonStyle(.borderedProminent).controlSize(.small).disabled(!app.serverReachable)
        }
    }
}

struct DeployProgressView: View {
    @EnvironmentObject var app: AppState
    let progress: DeployProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(statusText).font(.caption2)
                    .foregroundStyle(progress.phase == .failed ? Color.red : Color.secondary)
                    .lineLimit(2)
                Spacer()
                if progress.total > 0 && progress.phase != .failed {
                    Text("\(Fmt.bytes(progress.completed)) / \(Fmt.bytes(progress.total))")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            if progress.phase == .failed {
                EmptyView()
            } else if progress.phase == .loading || progress.total == 0 {
                ProgressView().progressViewStyle(.linear)
            } else {
                ProgressView(value: progress.fraction)
            }
        }
    }

    private var statusText: String {
        switch progress.phase {
        case .loading: return app.t("progress.loadingIntoMemory")
        case .done: return app.t("progress.ready")
        case .failed: return app.t("progress.failed", progress.status)
        case .pulling: return progress.status
        }
    }
}
