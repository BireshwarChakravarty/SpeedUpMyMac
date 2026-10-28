import SwiftUI
import BurnishCore

struct SmartScanView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ModuleScroll {
            hero
            if let smart = model.smart {
                breakdown(smart)
                HStack(alignment: .top, spacing: 16) {
                    issues(smart)
                    maintenance(smart)
                }
            } else {
                EmptyState(symbol: "sparkles", title: "One scan, every corner",
                           message: "Smart Scan measures junk and build artifacts, checks health and security, probes maintenance tasks and audits what starts with your Mac. Nothing is removed without a receipt.")
                    .card()
            }
        }
        .navigationTitle("Smart Scan")
    }

    private var hero: some View {
        HStack(spacing: 26) {
            ScoreRing(score: model.smart?.health.score ?? model.health?.score ?? 0, size: 132)
                .opacity(model.smart == nil && model.health == nil ? 0.35 : 1)
            VStack(alignment: .leading, spacing: 6) {
                Text(model.smart == nil ? "Ready when you are" : "Reclaimable now").font(.headline).foregroundStyle(.secondary)
                Text(model.smart.map { Format.bytes($0.quickWinBytes) } ?? "—").font(Theme.hero).contentTransition(.numericText())
                if let smart = model.smart {
                    Text("Safe junk and idle build folders on \(model.machine.name).").foregroundStyle(.secondary)
                    if smart.sudoOnlyBytes > 0 && !model.sudo {
                        Label(model.machine.isAdmin ? "\(Format.bytes(smart.sudoOnlyBytes)) more with Sudo mode"
                              : "\(Format.bytes(smart.sudoOnlyBytes)) more is system-level (needs an admin account)",
                              systemImage: "lock.shield").font(.callout).foregroundStyle(Theme.sudo)
                    }
                } else {
                    Text("\(model.machine.chip) · macOS \(model.machine.osVersion) · \(model.machine.isAdmin ? "Administrator" : "Standard account")")
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(spacing: 10) {
                if model.smart == nil {
                    Button("Scan") { Task { await model.runSmartScan() } }
                        .buttonStyle(.polish)
                        .disabled(model.busy != nil)
                } else {
                    Button("Rescan") { Task { await model.runSmartScan() } }
                        .controlSize(.large)
                        .disabled(model.busy != nil)
                }
                if model.smart != nil {
                    Button("Burnish now") { model.burnishNow() }
                        .buttonStyle(.polish)
                        .disabled(model.busy != nil || (model.smart?.quickWinBytes ?? 0) == 0)
                }
            }
        }
        .card(padding: 24)
    }

    private func breakdown(_ smart: SmartScanResult) -> some View {
        let categories = smart.cleanup.byCategory()
        let artifactBytes = smart.artifacts.filter { !$0.recentlyActive }.reduce(0) { $0 + $1.bytes }
        let rows: [(String, String, Int64)] = categories.map { ($0.0.rawValue, $0.0.symbol, $0.1) }
            + (artifactBytes > 0 ? [("Idle build artifacts", "shippingbox.and.arrow.backward", artifactBytes)] : [])
        let maxBytes = max(rows.map(\.2).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Where the space is").font(.headline)
            ForEach(rows.sorted { $0.2 > $1.2 }, id: \.0) { row in
                HStack {
                    Label(row.0, systemImage: row.1).frame(width: 220, alignment: .leading)
                    GeometryReader { geo in
                        Capsule().fill(Theme.polish)
                            .frame(width: max(6, geo.size.width * CGFloat(Double(row.2) / Double(maxBytes))))
                    }
                    .frame(height: 8)
                    SizeText(bytes: row.2).frame(width: 90, alignment: .trailing)
                }
            }
            HStack {
                Button("Review cleanup") { model.selection = .cleanup }
                Button("Review dev purge") { model.selection = .devPurge }
            }
            .padding(.top, 4)
        }
        .card()
    }

    private func issues(_ smart: SmartScanResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Health & security").font(.headline)
            if smart.health.notes.isEmpty && smart.suspiciousStartupItems.isEmpty {
                Label("Nothing needs attention", systemImage: "checkmark.seal").foregroundStyle(Theme.safe)
            }
            ForEach(smart.health.notes, id: \.self) { note in
                Label(note, systemImage: "exclamationmark.circle").foregroundStyle(Theme.review)
            }
            if !smart.suspiciousStartupItems.isEmpty {
                Button {
                    model.selection = .startup
                } label: {
                    Label("\(smart.suspiciousStartupItems.count) unsigned or broken startup item(s)", systemImage: "power")
                        .foregroundStyle(Theme.risky)
                }
                .buttonStyle(.plain)
            }
            if !smart.health.security.fullDiskAccess {
                Button("Grant Full Disk Access…") { model.openFullDiskAccessSettings() }
            }
        }
        .card()
    }

    private func maintenance(_ smart: SmartScanResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Maintenance").font(.headline)
            if smart.recommendedTasks.isEmpty {
                Label("No maintenance needed — probes found nothing broken", systemImage: "checkmark.seal").foregroundStyle(Theme.safe)
            } else {
                ForEach(smart.recommendedTasks) { task in Label(task.title, systemImage: task.symbol) }
                Button("Open Maintenance") { model.selection = .maintenance }
            }
        }
        .card()
    }
}
