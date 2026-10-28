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
                summary(smart)
                breakdown(smart)
            } else if phase == .idle {
                HStack(alignment: .top, spacing: 12) {
                    feature("Junk & caches", "50 cleanup rules. Safe items are pre-selected; nothing goes without a receipt.")
                    feature("Dev artifacts", "node_modules, target, .build and Pods in projects you haven't touched.")
                    feature("Health & security", "Disk, memory, battery, SIP, FileVault, firewall and startup items.")
                }
                .reveal(delay: 0.05)
            }
        }
    }

    // MARK: Hero

    private var hero: some View {
        HStack(alignment: .center, spacing: 44) {
            ScanRing(phase: phase, progress: model.scanProgress ?? 0, score: model.smart?.health.score)
            VStack(alignment: .leading, spacing: 10) {
                switch phase {
                case .idle:
                    Text("Ready when you are").font(.system(size: 13)).foregroundStyle(.secondary)
                    Text("Scan \(model.machine.name)").font(.system(size: 30, weight: .semibold)).lineLimit(2)
                    Text("\(model.machine.chip) · macOS \(model.machine.osVersion) · \(model.machine.isAdmin ? "Administrator" : "Standard account")")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                    Button("Start Scan") { Task { await model.runSmartScan() } }
                        .buttonStyle(.brand)
                        .keyboardShortcut(.defaultAction)
                        .padding(.top, 10)
                case .scanning:
                    Text("Scanning").font(.system(size: 13)).foregroundStyle(.secondary)
                    Text(model.scanStage)
                        .font(.system(size: 24, weight: .semibold))
                        .lineLimit(2)
                        .contentTransition(.opacity)
                        .animation(.easeOut(duration: 0.15), value: model.scanStage)
                    Text("Nothing is removed until you confirm a receipt.").font(.system(size: 13)).foregroundStyle(.secondary)
                case .done:
                    if let smart = model.smart {
                        Text(smart.quickWinBytes > 0 ? "Ready to clean" : "Nothing to clean").font(.system(size: 13)).foregroundStyle(.secondary)
                        BigBytes(bytes: smart.quickWinBytes, size: 64, duration: 1.2)
                        Text(heroDetail(smart)).font(.system(size: 14)).foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            Button("Clean \(Format.bytes(smart.quickWinBytes))") { model.cleanNow() }
                                .buttonStyle(.brand)
                                .disabled(model.busy != nil || smart.quickWinBytes == 0)
                            Button("Review…") { go(.cleanup) }
                            Button("Rescan") { Task { await model.runSmartScan() } }
                                .disabled(model.busy != nil)
                        }
                        .padding(.top, 10)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 40).padding(.vertical, 36)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(RadialGradient(colors: [Theme.lime.opacity(0.09), .clear], center: .topLeading, startRadius: 0, endRadius: 520)))
        )
        .reveal()
    }

    private func heroDetail(_ smart: SmartScanResult) -> String {
        var text = "Caches, logs and idle build folders."
        if smart.sudoOnlyBytes > 0 && !model.sudo {
            text += model.machine.isAdmin ? " \(Format.bytes(smart.sudoOnlyBytes)) more with Sudo." : " \(Format.bytes(smart.sudoOnlyBytes)) more needs an admin account."
        }
        return text
    }

    private func feature(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .surface()
    }

    // MARK: Results

    private func summary(_ smart: SmartScanResult) -> some View {
        let categories = smart.cleanup.results.filter { $0.target.risk == .safe && $0.skippedReason == nil && $0.bytes > 0 }
        let security = securityIssues(smart.health)
        return HStack(alignment: .top, spacing: 12) {
            tile("Junk", Format.bytes(smart.quickWinBytes),
                 categories.isEmpty ? "Nothing worth removing" : "\(categories.count) categor\(categories.count == 1 ? "y" : "ies"), all safe",
                 color: nil) { go(.cleanup) }
            tile("Security", security.isEmpty ? "All good" : "\(security.count) to fix",
                 security.isEmpty ? "SIP, Gatekeeper, FileVault and firewall" : security.joined(separator: ", ") + " off",
                 color: security.isEmpty ? nil : Theme.review) { go(.health) }
            tile("Startup", smart.suspiciousStartupItems.isEmpty ? "Clean" : "\(smart.suspiciousStartupItems.count) unsigned",
                 smart.suspiciousStartupItems.isEmpty ? "Every launch item is signed" : "Review in Startup Items",
                 color: nil) { go(.startup) }
            tile("Maintenance", smart.recommendedTasks.isEmpty ? "Nothing to do" : "\(smart.recommendedTasks.count) suggested",
                 smart.recommendedTasks.isEmpty ? "Checks found nothing broken" : smart.recommendedTasks.map(\.title).prefix(2).joined(separator: ", "),
                 color: nil) { go(.maintenance) }
        }
        .reveal(delay: 0.06)
    }

    private func securityIssues(_ h: HealthReport) -> [String] {
        var out: [String] = []
        if h.security.sip == false { out.append("SIP") }
        if h.security.fileVault == false { out.append("FileVault") }
        if h.security.firewall == false { out.append("Firewall") }
        if h.security.gatekeeper == false { out.append("Gatekeeper") }
        return out
    }

    private func tile(_ label: String, _ value: String, _ detail: String, color: Color?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
                Text(value).font(.system(size: 20, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                Text(detail).font(.system(size: 12)).foregroundStyle(color ?? .secondary).lineLimit(2)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .surface()
            .hoverLift()
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func breakdown(_ smart: SmartScanResult) -> some View {
        let categories = smart.cleanup.byCategory()
        let artifactBytes = smart.artifacts.filter { !$0.recentlyActive }.reduce(0) { $0 + $1.bytes }
        let rows: [(String, Int64)] = categories.map { ($0.0.rawValue, $0.1) }
            + (artifactBytes > 0 ? [("Idle build artifacts", artifactBytes)] : [])
        let sorted = rows.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }
        let maxBytes = max(sorted.first?.1 ?? 1, 1)
        return VStack(alignment: .leading, spacing: 4) {
            Text("Where the space is").font(.system(size: 15, weight: .semibold)).padding(.bottom, 6)
            ForEach(Array(sorted.enumerated()), id: \.element.0) { index, row in
                Rectangle().fill(Theme.separator).frame(height: 1)
                HStack(spacing: 18) {
                    Text(row.0).font(.system(size: 13)).frame(width: 190, alignment: .leading)
                    GrowingBar(fraction: Double(row.1) / Double(maxBytes), delay: 0.1 + Double(index) * 0.04)
                        .opacity(1 - min(Double(index) * 0.08, 0.4))
                    Text(Format.bytes(row.1)).font(.system(size: 13).monospacedDigit()).foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .trailing)
                }
                .padding(.vertical, 9)
            }
        }
        .reveal(delay: 0.1)
    }

    private func go(_ module: Module) {
        SoundFX.shared.play(.select)
        withAnimation(Theme.spring) { model.selection = module }
    }
}
