import SwiftUI
import RootCore

struct SmartScanView: View {
    @Environment(AppModel.self) private var model

    private var phase: OrbPhase {
        model.scanProgress != nil ? .scanning : (model.smart == nil ? .idle : .done)
    }

    var body: some View {
        ModuleScroll {
            hero
            if let smart = model.smart, phase != .scanning {
                breakdown(smart)
                HStack(alignment: .top, spacing: 16) {
                    issues(smart)
                    maintenance(smart)
                }
            } else if phase == .idle {
                HStack(spacing: 16) {
                    feature("trash.slash", "Junk & caches", "50 cleanup rules, safe items pre-selected", delay: 0.1)
                    feature("hammer", "Dev artifacts", "node_modules, target, .build, Pods…", delay: 0.16)
                    feature("heart.text.square", "Health & security", "Disk, memory, battery, SIP, FileVault", delay: 0.22)
                    feature("power", "Startup audit", "Unsigned and broken launch agents", delay: 0.28)
                }
            }
        }
        .navigationTitle("Smart Scan")
    }

    // MARK: Hero

    private var hero: some View {
        HStack(spacing: 10) {
            ScanOrb(phase: phase, progress: model.scanProgress ?? 0, size: 210, action: {
                Task { await model.runSmartScan() }
            }) {
                orbLabel
            }
            VStack(alignment: .leading, spacing: 8) {
                switch phase {
                case .idle:
                    Text("READY WHEN YOU ARE").font(.caption.weight(.bold)).tracking(1.6).foregroundStyle(.secondary)
                    Text("Clean \(model.machine.name) to the root").font(.system(size: 32, weight: .heavy, design: .monospaced))
                    Text("\(model.machine.chip) · macOS \(model.machine.osVersion) · \(model.machine.isAdmin ? "Administrator" : "Standard account")")
                        .foregroundStyle(.secondary)
                    Text("Tap the orb. Nothing is removed without a receipt.").font(.callout).foregroundStyle(.tertiary)
                case .scanning:
                    Text("SCANNING").font(.caption.weight(.bold)).tracking(1.6).foregroundStyle(Theme.brand)
                    Text(model.scanStage)
                        .font(.system(size: 26, weight: .semibold, design: .monospaced))
                        .lineLimit(2)
                        .contentTransition(.opacity)
                        .animation(.easeOut(duration: 0.2), value: model.scanStage)
                    GrowingBar(fraction: model.scanProgress ?? 0, height: 6).frame(maxWidth: 360)
                case .done:
                    if let smart = model.smart {
                        Text("RECLAIMABLE NOW").font(.caption.weight(.bold)).tracking(1.6).foregroundStyle(.secondary)
                        CountingBytes(bytes: smart.quickWinBytes, duration: 1.4)
                            .font(.system(size: 56, weight: .heavy, design: .monospaced))
                            .foregroundStyle(Theme.brand)
                        Text("Safe junk and idle build folders on \(model.machine.name).").foregroundStyle(.secondary)
                        if smart.sudoOnlyBytes > 0 && !model.sudo {
                            Label(model.machine.isAdmin ? "\(Format.bytes(smart.sudoOnlyBytes)) more with Sudo mode"
                                  : "\(Format.bytes(smart.sudoOnlyBytes)) more is system-level (needs an admin account)",
                                  systemImage: "lock.fill").font(.callout).foregroundStyle(Theme.sudo)
                        }
                        HStack(spacing: 10) {
                            Button {
                                model.cleanNow()
                            } label: {
                                Label("Clean now", systemImage: "sparkles")
                            }
                            .buttonStyle(.brand)
                            .disabled(model.busy != nil || smart.quickWinBytes == 0)
                            Button("Rescan") { Task { await model.runSmartScan() } }
                                .disabled(model.busy != nil)
                        }
                        .padding(.top, 6)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(Theme.spring, value: phase)
        }
        .padding(.vertical, 6)
        .card(padding: 14)
    }

    @ViewBuilder
    private var orbLabel: some View {
        switch phase {
        case .idle:
            VStack(spacing: 2) {
                Image(systemName: "number").font(.system(size: 30, weight: .bold))
                Text("scan").font(.system(size: 30, weight: .bold, design: .monospaced))
            }
        case .scanning:
            CountingText(value: (model.scanProgress ?? 0) * 100, duration: 0.3) { "\(Int($0))%" }
                .font(.system(size: 40, weight: .heavy, design: .monospaced))
        case .done:
            if let score = model.smart?.health.score {
                VStack(spacing: 0) {
                    CountingText(value: Double(score)) { "\(Int($0.rounded()))" }
                        .font(.system(size: 50, weight: .heavy, design: .monospaced))
                    Text("health").font(.callout.weight(.semibold)).opacity(0.8)
                }
            }
        }
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String, delay: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol).font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.brand)
            Text(title).font(.system(.headline, design: .monospaced))
            Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .glassCard()
        .hoverLift()
        .reveal(delay: delay)
    }

    // MARK: Results

    private func breakdown(_ smart: SmartScanResult) -> some View {
        let categories = smart.cleanup.byCategory()
        let artifactBytes = smart.artifacts.filter { !$0.recentlyActive }.reduce(0) { $0 + $1.bytes }
        let rows: [(String, String, Int64)] = categories.map { ($0.0.rawValue, $0.0.symbol, $0.1) }
            + (artifactBytes > 0 ? [("Idle build artifacts", "shippingbox.and.arrow.backward", artifactBytes)] : [])
        let sorted = rows.sorted { $0.2 > $1.2 }
        let maxBytes = max(sorted.first?.2 ?? 1, 1)
        return VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Where the space is", symbol: "chart.bar.xaxis", trailing: Format.bytes(rows.reduce(0) { $0 + $1.2 }))
            ForEach(Array(sorted.enumerated()), id: \.element.0) { index, row in
                HStack(spacing: 12) {
                    Image(systemName: row.1).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.brand).frame(width: 20)
                    Text(row.0).frame(width: 190, alignment: .leading)
                    GrowingBar(fraction: Double(row.2) / Double(maxBytes), delay: 0.15 + Double(index) * 0.06)
                    SizeText(bytes: row.2).frame(width: 90, alignment: .trailing)
                }
                .padding(.vertical, 2)
                .rowHover()
                .reveal(index: index)
            }
            HStack {
                Button("Review cleanup") { go(.cleanup) }
                Button("Review dev purge") { go(.devPurge) }
            }
            .padding(.top, 4)
        }
        .card()
    }

    private func issues(_ smart: SmartScanResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Health & security", symbol: "heart.text.square", trailing: nil)
            if smart.health.notes.isEmpty && smart.suspiciousStartupItems.isEmpty {
                Label("Nothing needs attention", systemImage: "checkmark.seal.fill").foregroundStyle(Theme.safe)
            }
            ForEach(smart.health.notes, id: \.self) { note in
                Label(note, systemImage: "exclamationmark.circle.fill").foregroundStyle(Theme.review)
            }
            if !smart.suspiciousStartupItems.isEmpty {
                Button {
                    go(.startup)
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
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Maintenance", symbol: "wrench.and.screwdriver", trailing: nil)
            if smart.recommendedTasks.isEmpty {
                Label("No maintenance needed — probes found nothing broken", systemImage: "checkmark.seal.fill").foregroundStyle(Theme.safe)
            } else {
                ForEach(smart.recommendedTasks) { task in Label(task.title, systemImage: task.symbol) }
                Button("Open Maintenance") { go(.maintenance) }
            }
        }
        .card()
    }

    private func go(_ module: Module) {
        SoundFX.shared.play(.select)
        withAnimation(Theme.spring) { model.selection = module }
    }
}
