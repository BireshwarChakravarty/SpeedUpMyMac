import SwiftUI
import SpruceCore

struct SmartScanView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(fdaCardDismissedKey) private var fdaCardDismissed = false

    private var phase: OrbPhase {
        model.scanProgress != nil ? .scanning : (model.smart == nil ? .idle : .done)
    }

    var body: some View {
        ModuleScroll {
            if model.health?.security.fullDiskAccess == false && !fdaCardDismissed { FullDiskAccessCard() }
            hero
            if let smart = model.smart, phase != .scanning {
                summary(smart)
                breakdown(smart)
            }
        }
    }

    // MARK: Hero

    private var hero: some View {
        Group {
            switch phase {
            case .idle:
                ToolHero(module: .smartScan, title: "Smart Scan",
                         subtitle: "Junk, idle build folders, health and startup items, checked in one pass.") {
                    Button("Scan") { Task { await model.runSmartScan() } }
                        .buttonStyle(.brand)
                        .keyboardShortcut(.defaultAction)
                    Button("Status") { go(.status) }
                }
            case .scanning:
                ToolHero(module: .smartScan, title: "Scanning…", subtitle: model.scanStage, pulsing: true) {
                    Text("\(Int((model.scanProgress ?? 0) * 100))%")
                        .font(Theme.mono(13, .medium)).foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
            case .done:
                if let smart = model.smart {
                    ToolHero(module: .smartScan, title: "",
                             subtitle: heroDetail(smart),
                             result: smart.quickWinBytes > 0 ? "\(Format.bytes(smart.quickWinBytes)) found" : "All clear") {
                        Button("Spruce Up") { model.cleanNow() }
                            .buttonStyle(.brand)
                            .disabled(model.busy != nil || smart.quickWinBytes == 0)
                        Button("Review \(reviewCount(smart)) items") { go(.cleanup) }
                        Button("Rescan") { Task { await model.runSmartScan() } }
                            .disabled(model.busy != nil)
                    }
                    healthLine(smart.health)
                }
            }
        }
    }

    /// One quiet line under the result: the health score and what's pulling it down.
    private func healthLine(_ health: HealthReport) -> some View {
        HStack(spacing: 8) {
            Circle().fill(Theme.scoreColor(health.score)).frame(width: 8, height: 8)
            Text("HEALTH \(health.score)").font(Theme.mono(11, .bold)).tracking(1.2)
            Text(health.notes.first ?? "Nothing needs attention").font(Theme.mono(11)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Capsule().fill(Theme.chipFill))
        .frame(maxWidth: .infinity)
    }

    private func reviewCount(_ smart: SmartScanResult) -> Int {
        smart.cleanup.results.filter { $0.skippedReason == nil && $0.bytes > 0 }.count
            + smart.artifacts.filter { !$0.recentlyActive }.count
    }

    private func heroDetail(_ smart: SmartScanResult) -> String {
        guard smart.quickWinBytes > 0 else { return "No caches, logs or idle build folders worth removing." }
        var text = "Caches, logs and idle build folders, all safe to remove. Every file is listed before anything goes."
        if smart.sudoOnlyBytes > 0 && !model.sudo {
            text += model.machine.isAdmin ? " \(Format.bytes(smart.sudoOnlyBytes)) more in Admin mode." : " \(Format.bytes(smart.sudoOnlyBytes)) more needs an admin account."
        }
        return text
    }

    private func feature(_ module: Module, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            IconTile(module: module, size: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Theme.sans(14, .semibold))
                Text(detail).font(Theme.sans(12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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
                 security.isEmpty ? "SIP, Gatekeeper, FileVault and firewall are on" : "See how to turn them on") {
                if !security.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "exclamationmark.shield.fill").font(.system(size: 12))
                        Text(security.joined(separator: ", ") + " off").font(.system(size: 12, weight: .semibold)).lineLimit(2)
                    }
                    .foregroundStyle(Theme.risky)
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
                    Image(systemName: module.symbol).font(.system(size: 11, weight: .semibold))
                    Text(label.uppercased()).font(Theme.mono(11, .semibold)).tracking(1.4)
                }
                .foregroundStyle(module.accentText)
                Text(value).font(Theme.sans(26, .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                visual()
                Text(detail).font(Theme.mono(11)).foregroundStyle(.secondary).lineLimit(2)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
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
                        Text(row.0).font(Theme.sans(13)).frame(width: 190, alignment: .leading)
                        GrowingBar(fraction: Double(row.1) / Double(maxBytes), fill: colours[index % colours.count].barGradient,
                                   delay: 0.1 + Double(index) * 0.04, height: 7)
                        Text(Format.bytes(row.1)).font(Theme.mono(12)).foregroundStyle(.secondary)
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

let fdaCardDismissedKey = "fullDiskAccessCardDismissed"

/// Asks once for Full Disk Access, the one permission that stops macOS asking about each folder.
/// Can be dismissed for good (on a managed or standard-account Mac, the user may not be allowed to
/// grant it); Settings → About keeps "Grant Full Disk Access…" for later.
struct FullDiskAccessCard: View {
    @Environment(AppModel.self) private var model
    @AppStorage(fdaCardDismissedKey) private var dismissed = false

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
            Button("Not Now") {
                withAnimation(Theme.spring) { dismissed = true }
                model.report("Hidden. You can grant Full Disk Access later from Settings.")
            }
            .help("Hide this card. Spruce keeps skipping protected folders.")
        }
        .padding(16)
        .surface()
        .reveal()
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.recheckFullDiskAccess()
        }
    }
}
