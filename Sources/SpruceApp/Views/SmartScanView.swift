import SwiftUI
import SpruceCore

struct SmartScanView: View {
    @Environment(AppModel.self) private var model

    private var phase: OrbPhase {
        model.scanProgress != nil ? .scanning : (model.smart == nil ? .idle : .done)
    }

    var body: some View {
        ModuleScroll {
            if model.health?.security.fullDiskAccess == false { FullDiskAccessCard() }
            hero
            if let smart = model.smart, phase != .scanning {
                summary(smart)
                breakdown(smart)
            } else if phase == .idle {
                HStack(alignment: .top, spacing: 12) {
                    feature(.cleanup, "Junk & caches", "50 cleanup rules. Safe items are pre-selected; nothing goes without a receipt.")
                    feature(.devPurge, "Dev artifacts", "node_modules, target, .build and Pods in projects you haven't touched.")
                    feature(.health, "Health & security", "Disk, memory, battery, SIP, FileVault, firewall and startup items.")
                }
                .reveal(delay: 0.05)
            }
        }
    }

    // MARK: Hero

    private var hero: some View {
        HStack(alignment: .center, spacing: 40) {
            GlassOrb(phase: phase, progress: model.scanProgress ?? 0, score: model.smart?.health.score,
                     junkBytes: model.smart?.quickWinBytes ?? 0, size: 290)
                .padding(.leading, 6)
            VStack(alignment: .leading, spacing: 12) {
                switch phase {
                case .idle:
                    Text("Ready when you are").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accentText)
                    Text("Spruce up \(model.machine.name)").font(.system(size: 34, weight: .bold)).lineLimit(2)
                    Text("\(model.machine.chip) · macOS \(model.machine.osVersion) · \(model.machine.isAdmin ? "Administrator" : "Standard account")")
                        .font(.system(size: 14)).foregroundStyle(.secondary)
                    Button("Start Scan") { Task { await model.runSmartScan() } }
                        .buttonStyle(.brand)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                        .padding(.top, 8)
                case .scanning:
                    Text("Scanning").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accentText)
                    Text(model.scanStage)
                        .font(.system(size: 28, weight: .bold))
                        .lineLimit(2)
                        .contentTransition(.opacity)
                        .animation(.easeOut(duration: 0.15), value: model.scanStage)
                    Text("Nothing is removed until you confirm a receipt.").font(.system(size: 14)).foregroundStyle(.secondary)
                case .done:
                    if let smart = model.smart {
                        Text(smart.quickWinBytes > 0 ? "Ready to spruce up" : "Spotless")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accentText)
                        BigBytes(bytes: smart.quickWinBytes, size: 88, duration: 1.2)
                        Text(heroDetail(smart)).font(.system(size: 15)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 10) {
                            Button("Spruce Up") { model.cleanNow() }
                                .buttonStyle(.brand)
                                .disabled(model.busy != nil || smart.quickWinBytes == 0)
                            Button("Review \(reviewCount(smart)) items") { go(.cleanup) }
                            Button { Task { await model.runSmartScan() } } label: { Image(systemName: "arrow.clockwise") }
                                .help("Scan again (⌘R)")
                                .disabled(model.busy != nil)
                        }
                        .controlSize(.large)
                        .padding(.top, 8)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12)
        .reveal()
    }

    private func reviewCount(_ smart: SmartScanResult) -> Int {
        smart.cleanup.results.filter { $0.skippedReason == nil && $0.bytes > 0 }.count
            + smart.artifacts.filter { !$0.recentlyActive }.count
    }

    private func heroDetail(_ smart: SmartScanResult) -> String {
        guard smart.quickWinBytes > 0 else { return "No caches, logs or idle build folders worth removing. Nice." }
        var text = "Caches, logs and idle build folders. All of it is safe to remove, and every file is listed before anything goes."
        if smart.sudoOnlyBytes > 0 && !model.sudo {
            text += model.machine.isAdmin ? " \(Format.bytes(smart.sudoOnlyBytes)) more in Admin mode." : " \(Format.bytes(smart.sudoOnlyBytes)) more needs an admin account."
        }
        return text
    }

    private func feature(_ module: Module, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            IconTile(module: module, size: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .surface()
    }

    // MARK: Results

    private func summary(_ smart: SmartScanResult) -> some View {
        let categories = smart.cleanup.results.filter { $0.target.risk == .safe && $0.skippedReason == nil && $0.bytes > 0 }
        let security = securityIssues(smart.health)
        let junk = junkSegments(smart)
        return HStack(alignment: .top, spacing: 12) {
            tile(.cleanup, "Junk", Format.bytes(smart.quickWinBytes),
                 categories.isEmpty ? "Nothing worth removing" : "\(categories.count) categor\(categories.count == 1 ? "y" : "ies"), all safe") {
                if !junk.isEmpty {
                    GeometryReader { geo in
                        let total = max(1, junk.reduce(0) { $0 + $1.1 })
                        HStack(spacing: 2) {
                            ForEach(Array(junk.enumerated()), id: \.offset) { _, segment in
                                Capsule().fill(segment.0.barGradient)
                                    .frame(width: max(4, (geo.size.width - CGFloat(junk.count - 1) * 2) * CGFloat(segment.1) / CGFloat(total)))
                            }
                        }
                    }
                    .frame(height: 7)
                }
            } action: { go(.cleanup) }
            tile(.health, "Security", security.isEmpty ? "All good" : "\(security.count) to fix",
                 security.isEmpty ? "SIP, Gatekeeper, FileVault and firewall are on" : "Tap to see how to turn them on") {
                if !security.isEmpty {
                    HStack(spacing: 5) {
                        ForEach(security, id: \.self) { name in
                            Text("\(name) off").font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.risky)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Capsule().fill(Theme.risky.opacity(0.14)))
                        }
                    }
                }
            } action: { go(.health) }
            tile(.startup, "Startup", smart.suspiciousStartupItems.isEmpty ? "Clean" : "\(smart.suspiciousStartupItems.count) to review",
                 smart.suspiciousStartupItems.isEmpty ? "Every launch item is signed and loadable" : "Unsigned, broken or won't load") {
                if !smart.suspiciousStartupItems.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(0..<min(6, smart.suspiciousStartupItems.count), id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Module.startup.gradient).frame(width: 18, height: 18)
                        }
                    }
                }
            } action: { go(.startup) }
            tile(.maintenance, "Maintenance", smart.recommendedTasks.isEmpty ? "Nothing to do" : "\(smart.recommendedTasks.count) suggested",
                 smart.recommendedTasks.isEmpty ? "Checks found nothing broken" : smart.recommendedTasks.map(\.title).prefix(2).joined(separator: ", ")) {
                if smart.recommendedTasks.isEmpty {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 16)).foregroundStyle(Module.maintenance.accent)
                }
            } action: { go(.maintenance) }
        }
        .reveal(delay: 0.06)
    }

    /// Junk by section colour, biggest first, for the stacked bar in the Junk tile.
    private func junkSegments(_ smart: SmartScanResult) -> [(Module, Int64)] {
        let colours: [Module] = [.cleanup, .devPurge, .uninstaller, .processes, .spaceLens, .fleet, .maintenance, .health]
        let artifactBytes = smart.artifacts.filter { !$0.recentlyActive }.reduce(0) { $0 + $1.bytes }
        let rows = smart.cleanup.byCategory().map(\.1) + (artifactBytes > 0 ? [artifactBytes] : [])
        return rows.sorted(by: >).prefix(colours.count).enumerated().map { (colours[$0.offset], $0.element) }
    }

    private func securityIssues(_ h: HealthReport) -> [String] {
        var out: [String] = []
        if h.security.sip == false { out.append("SIP") }
        if h.security.fileVault == false { out.append("FileVault") }
        if h.security.firewall == false { out.append("Firewall") }
        if h.security.gatekeeper == false { out.append("Gatekeeper") }
        return out
    }

    private func tile<Visual: View>(_ module: Module, _ label: String, _ value: String, _ detail: String,
                                    @ViewBuilder visual: () -> Visual, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Circle().fill(module.accent).frame(width: 7, height: 7).shadow(color: module.accent.opacity(0.6), radius: 3)
                    Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                }
                Text(value).font(.system(size: 24, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
                visual()
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .surface()
            .hoverLift()
            .contentShape(RoundedRectangle(cornerRadius: 16))
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
        let colours: [Module] = [.cleanup, .devPurge, .uninstaller, .processes, .spaceLens, .fleet, .maintenance, .health]
        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Where the space is", symbol: nil, trailing: nil)
            VStack(spacing: 0) {
                ForEach(Array(sorted.enumerated()), id: \.element.0) { index, row in
                    if index > 0 { RowDivider(inset: 0) }
                    HStack(spacing: 18) {
                        Text(row.0).font(.system(size: 13)).frame(width: 190, alignment: .leading)
                        GrowingBar(fraction: Double(row.1) / Double(maxBytes), fill: colours[index % colours.count].barGradient,
                                   delay: 0.1 + Double(index) * 0.04, height: 7)
                        Text(Format.bytes(row.1)).font(.system(size: 13, design: .rounded).monospacedDigit()).foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .trailing)
                    }
                    .padding(.vertical, 11)
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 4)
            .surface()
        }
        .reveal(delay: 0.1)
    }

    private func go(_ module: Module) {
        SoundFX.shared.play(.select)
        withAnimation(Theme.spring) { model.selection = module }
    }
}

/// Asks once for Full Disk Access, the one permission that stops macOS asking about each folder.
struct FullDiskAccessCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            IconTile(module: .health, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text("Give Spruce Full Disk Access once").font(.system(size: 13, weight: .semibold))
                Text("Then macOS stops asking about Desktop, Documents and Downloads, and Spruce can see Mail, Safari and other apps' caches. Until then, Spruce skips those places instead of interrupting you.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button("Open Settings") { model.openFullDiskAccessSettings() }.buttonStyle(.brand)
        }
        .padding(16)
        .surface()
        .reveal()
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.recheckFullDiskAccess()
        }
    }
}
