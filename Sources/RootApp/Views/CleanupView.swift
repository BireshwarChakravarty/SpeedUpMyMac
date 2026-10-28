import SwiftUI
import RootCore

struct CleanupView: View {
    @Environment(AppModel.self) private var model

    private var selectedBytes: Int64 { model.selectedCleanupResults.reduce(0) { $0 + $1.bytes } }

    var body: some View {
        ModuleScroll {
            HeroHeader(title: "Cleanup", value: model.scan == nil ? "—" : Format.bytes(selectedBytes),
                       caption: model.scan == nil ? "Caches, logs, browser junk, installers, Trash and more"
                           : "selected of \(Format.bytes(model.scan!.totalBytes)) found", symbol: "trash") {
                Button("Rescan") { Task { await model.runCleanupScan() } }.disabled(model.busy != nil)
                Button("Review & Clean") { model.confirmCleanup() }
                    .buttonStyle(.brand)
                    .disabled(model.busy != nil || selectedBytes == 0)
            }
            if let scan = model.scan {
                let available = scan.results.filter { $0.skippedReason != "Needs Sudo mode" }
                let sudoOnly = scan.results.filter { $0.skippedReason == "Needs Sudo mode" }
                if scan.results.isEmpty {
                    EmptyState(symbol: "checkmark.circle", title: "Spotless", message: "Nothing worth cleaning was found.")
                }
                ForEach(TargetCategory.allCases, id: \.self) { category in
                    let results = available.filter { $0.target.category == category }
                    if !results.isEmpty {
                        GroupedSection(title: category.rawValue, trailing: Format.bytes(results.reduce(0) { $0 + $1.bytes })) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                                if index > 0 { RowDivider() }
                                TargetRow(result: result)
                            }
                        }
                    }
                }
                if !sudoOnly.isEmpty {
                    GroupedSection(title: "System", trailing: nil) {
                        ForEach(Array(sudoOnly.enumerated()), id: \.element.id) { index, result in
                            if index > 0 { RowDivider() }
                            TargetRow(result: result)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        Label(model.machine.isAdmin
                              ? "Turn on Sudo to include · \(Format.bytes(sudoOnly.reduce(0) { $0 + $1.bytes }))"
                              : "Needs an admin account · \(Format.bytes(sudoOnly.reduce(0) { $0 + $1.bytes }))",
                              systemImage: "lock.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.trailing, 4)
                    }
                    .opacity(0.65)
                }
            } else {
                EmptyState(symbol: "magnifyingglass", title: "Scan to see what's reclaimable",
                           message: "Safe items are pre-selected. Items marked Review or Risky are listed but never selected for you.")
            }
        }
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
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                Toggle("", isOn: isOn).labelsHidden().disabled(result.skippedReason != nil)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(result.target.title).font(.system(size: 13))
                        RiskBadge(risk: result.target.risk)
                    }
                    if let reason = result.skippedReason, reason != "Needs Sudo mode" {
                        Text(reason).font(.system(size: 12)).foregroundStyle(Theme.review)
                    } else if result.skippedReason == nil {
                        Text(result.target.detail).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                SizeText(bytes: result.bytes)
                if !result.items.isEmpty {
                    IconButton(symbol: "chevron.right", help: expanded ? "Hide files" : "Show files") {
                        withAnimation(Theme.spring) { expanded.toggle() }
                    }
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                } else {
                    Spacer().frame(width: 24)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            if expanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(result.items.prefix(200)) { item in
                        HStack(spacing: 10) {
                            Toggle("", isOn: Binding(get: { !model.excludedItems.contains(item.path) },
                                                     set: { on in
                                                         if on { model.excludedItems.remove(item.path) } else { model.excludedItems.insert(item.path) }
                                                     }))
                                .labelsHidden().controlSize(.small)
                            PathText(path: item.path)
                            Spacer()
                            IconButton(symbol: "magnifyingglass", help: "Show in Finder") { model.reveal(item.path) }
                            Text(Format.bytes(item.bytes)).font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                    if result.items.count > 200 { Text("… and \(result.items.count - 200) more").font(.caption).foregroundStyle(.secondary) }
                }
                .padding(.leading, 48).padding(.trailing, 16).padding(.bottom, 10)
                .transition(.opacity)
            }
        }
    }
}
