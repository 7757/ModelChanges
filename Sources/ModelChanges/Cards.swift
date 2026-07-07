import SwiftUI

struct ModelGrid: View {
    @EnvironmentObject var app: AppState
    let models: [LiveModel]
    @Binding var selected: LiveModel?

    private let columns = [GridItem(.adaptive(minimum: 236, maximum: 360), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(models) { model in
                    ModelCard(model: model, isSelected: selected?.id == model.id) {
                        withAnimation(.snappy(duration: 0.2)) { selected = model }
                    }
                }
            }
            .padding(16)
        }
        .overlay {
            if models.isEmpty {
                ContentUnavailableView(app.t("empty.noModelsTitle"),
                                       systemImage: "magnifyingglass",
                                       description: Text(app.t("empty.noModelsDescription")))
            }
        }
    }
}

struct ModelCard: View {
    @EnvironmentObject var app: AppState
    let model: LiveModel
    let isSelected: Bool
    let onTap: () -> Void
    @State private var hover = false

    private var running: Bool { model.variants.contains { app.isRunning($0.tag) } }
    private var installedCount: Int { model.variants.filter { app.isInstalled($0.tag) }.count }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text(model.name).font(.headline).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 4)
                    statusDot
                }
                if !model.developer.isEmpty {
                    Text(model.developer).font(.caption2).foregroundStyle(.secondary)
                }
                Text(model.summary.isEmpty ? " " : model.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 2)

                HStack(spacing: 5) {
                    ForEach(model.types.prefix(2), id: \.self) { TypeBadge(type: $0) }
                    if model.types.count > 2 { Chip(text: "+\(model.types.count - 2)") }
                }
                if !model.sizes.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(model.sizes.prefix(4), id: \.self) { Chip(text: $0) }
                        if model.sizes.count > 4 { Chip(text: "+\(model.sizes.count - 4)") }
                    }
                }

                HStack(spacing: 6) {
                    Label(model.pulls, systemImage: "arrow.down.circle").labelStyle(.titleAndIcon)
                    if !model.updated.isEmpty {
                        Text("· \(model.updated)")
                    }
                    Spacer()
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            .padding(12)
            .frame(height: 176, alignment: .top)
            .background(cardBackground)
            .overlay(border)
            .shadow(color: .black.opacity(hover ? 0.14 : 0), radius: hover ? 9 : 0, y: hover ? 4 : 0)
            .scaleEffect(hover ? 1.015 : 1)
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.14)) { hover = h } }
    }

    @ViewBuilder private var statusDot: some View {
        if running {
            Circle().fill(.green).frame(width: 8, height: 8)
                .shadow(color: .green.opacity(0.7), radius: 3)
        } else if installedCount > 0 {
            Image(systemName: "internaldrive.fill").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.85))
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
            .stroke(borderColor, lineWidth: (running || isSelected) ? 1.5 : 1)
    }

    private var borderColor: Color {
        if running { return .green.opacity(0.55) }
        if isSelected { return Brand.accent.opacity(0.8) }
        return hover ? Color.secondary.opacity(0.35) : Color.secondary.opacity(0.15)
    }
}
