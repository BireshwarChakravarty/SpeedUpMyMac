import SwiftUI
import BurnishCore

struct CleanupView: View {
    @Environment(AppModel.self) private var model

    private var selectedBytes: Int64 { model.selectedCleanupResults.reduce(0) { $0 + $1.bytes } }

    var body: some View {
        ModuleScroll {
            HeroHeader(title: "Cleanup", value: model.scan == nil ? "—" : Format.bytes(selectedBytes),
                       caption: model.scan == nil ? "Caches, logs, browser junk, installers, Trash and more"
                           : "selected of \(Format.bytes(model.scan!.totalBytes)) found", symbol: "trash.slash") {
                HStack {
                    Button("Scan") { Task { await model.runCleanupScan() } }.disabled(model.busy != nil)
                    Button("Review & clean") { model.confirmCleanup() }
                        .buttonStyle(.polish)
                        .disabled(model.busy != nil || selectedBytes == 0)
                }
            }
            if let scan = model.scan {
                if scan.results.isEmpty {
                    EmptyState(symbol: "checkmark.seal", title: "Spotless", message: "Nothing worth cleaning was found.").card()
                }
                ForEach(TargetCategory.allCases, id: \.self) { category in
                    let results = scan.results.filter { $0.target.category == category }
                    if !results.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(category.rawValue, systemImage: category.symbol).font(.headline).padding(.bottom, 4)
                            ForEach(results) { result in TargetRow(result: result) }
                        }
                        .card()
                    }
                }
            } else {
                EmptyState(symbol: "magnifyingglass", title: "Scan to see what's reclaimable",
                           message: "Safe items are pre-selected. Items marked Review or Risky are listed but never selected for you.").card()
            }
        }
        .navigationTitle("Cleanup")
        .task { if model.scan == nil { await model.runCleanupScan() } }
    }
}

struct TargetRow: View {
    @Environment(AppModel.self) private var model
    var result: TargetResult
    @State private var expanded = false

    private var isOn: Binding<Bool> {
        Binding(get: { model.selectedTargets.contains(result.target.id) },
                set: { on in
                    if on { model.selectedTargets.insert(result.target.id) } else { model.selectedTargets.remove(result.target.id) }
                })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Toggle("", isOn: isOn).labelsHidden().disabled(result.skippedReason != nil)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(result.target.title).fontWeight(.medium)
                        RiskBadge(risk: result.target.risk)
                        if result.target.scope == .system { SudoBadge() }
                    }
                    Text(result.skippedReason ?? result.target.detail)
                        .font(.caption)
                        .foregroundStyle(result.skippedReason == nil ? Color.secondary : Theme.review)
                }
                Spacer()
                SizeText(bytes: result.bytes)
                if !result.items.isEmpty {
                    Button { withAnimation { expanded.toggle() } } label: {
                        Image(systemName: "chevron.right").rotationEffect(.degrees(expanded ? 90 : 0))
                    }
                    .buttonStyle(.borderless)
                }
            }
            if expanded {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(result.items.prefix(200)) { item in
                        HStack {
                            Toggle("", isOn: Binding(get: { !model.excludedItems.contains(item.path) },
                                                     set: { on in
                                                         if on { model.excludedItems.remove(item.path) } else { model.excludedItems.insert(item.path) }
                                                     }))
                                .labelsHidden().controlSize(.small)
                            PathText(path: item.path)
                            Spacer()
                            Button { model.reveal(item.path) } label: { Image(systemName: "magnifyingglass") }
                                .buttonStyle(.borderless).help("Show in Finder")
                            Text(Format.bytes(item.bytes)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                    if result.items.count > 200 { Text("… and \(result.items.count - 200) more").font(.caption).foregroundStyle(.secondary) }
                }
                .padding(.leading, 34)
            }
        }
        .padding(.vertical, 4)
    }
}
