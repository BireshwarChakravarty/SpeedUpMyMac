import SwiftUI
import Charts
import SpruceCore

/// The menu bar panel: health at a glance, live CPU, memory, disk and network, quick actions,
/// and the drag-to-uninstall box.
struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    var close: () -> Void = {}

    private var monitor: MetricsMonitor { .shared }
    @State private var contentHeight: CGFloat = 0

    /// The tallest the panel may be: the screen under the menu bar, less a margin. On a small
    /// screen the panel stops there and scrolls.
    private var maxHeight: CGFloat {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        return max(320, (screen?.visibleFrame.height ?? 800) - 24)
    }

    var body: some View {
        let limit = maxHeight
        ScrollView {
            content
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { contentHeight = $0 }
        }
        .scrollDisabled(contentHeight <= limit)
        .scrollIndicators(contentHeight > limit ? .automatic : .hidden)
        .frame(width: 360, height: min(contentHeight, limit))
        .foregroundStyle(Theme.text)
        .background(Theme.base.opacity(0.55))
        .buttonStyle(.quiet)
        .onAppear { MetricsMonitor.shared.watch() }
        .onDisappear { MetricsMonitor.shared.unwatch() }
    }

    private var content: some View {
        let live = Array(monitor.live.suffix(24))
        let latest = monitor.latest
        VStack(alignment: .leading, spacing: 12) {
            header
            chips
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                HUDTile(metric: .cpu, title: "CPU", value: latest.map { String(format: "%.0f", $0.cpu) } ?? "—", unit: "%",
                        footer: latest.map { String(format: "load %.2f", $0.load) } ?? "") {
                    Chart(Array(live.enumerated()), id: \.offset) { index, sample in
                        BarMark(x: .value("t", index), y: .value("CPU", max(sample.cpu, 2)))
                            .foregroundStyle(Metric.cpu.color).cornerRadius(1.5)
                    }
                    .chartYScale(domain: 0...100)
                }
                HUDTile(metric: .memory, title: "Memory", value: latest.map { String(format: "%.0f", $0.memory) } ?? "—", unit: "%",
                        footer: latest.map { "swap \(Format.bytes($0.swapBytes))" } ?? "") {
                    Chart(Array(live.enumerated()), id: \.offset) { index, sample in
                        AreaMark(x: .value("t", index), y: .value("mem", sample.memory))
                            .foregroundStyle(LinearGradient(colors: [Metric.memory.color.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("t", index), y: .value("mem", sample.memory)).foregroundStyle(Metric.memory.color)
                    }
                    .chartYScale(domain: 0...100)
                }
                HUDTile(metric: .diskFree, title: "Disk", value: latest.map { Format.bytes($0.diskFreeBytes) } ?? "—", unit: "free",
                        footer: model.health.map { "\(Int($0.disk.usedFraction * 100))% used" } ?? "") {
                    VStack {
                        Spacer()
                        GrowingBar(fraction: model.health?.disk.usedFraction ?? 0,
                                   fill: LinearGradient(colors: [Color(hex: 0xE6A93C), Color(hex: 0xF0714E)], startPoint: .leading, endPoint: .trailing),
                                   height: 7)
                        Spacer()
                    }
                }
                HUDTile(metric: .netIn, title: "Network", value: latest.map { Format.bytes(Int64($0.netIn)) } ?? "—", unit: "/s",
                        footer: latest.map { "↓ \(Format.bytes(Int64($0.netIn)))  ↑ \(Format.bytes(Int64($0.netOut)))" } ?? "") {
                    Chart(Array(live.enumerated()), id: \.offset) { index, sample in
                        LineMark(x: .value("t", index), y: .value("in", sample.netIn)).foregroundStyle(Metric.netIn.color)
                    }
                }
            }
            readyRow
            QuickUninstallPanel(close: close)
                .environment(\.pageModule, .uninstaller)
            footer
        }
        .padding(16)
        .frame(width: 360)
        .foregroundStyle(Theme.text)
        .buttonStyle(.quiet)
    }

    private var header: some View {
        HStack(spacing: 10) {
            SpruceMark().frame(width: 30, height: 30)
            if let health = model.health {
                Text("\(health.score)").font(Theme.mono(20, .bold))
                Text(health.notes.first.map(Self.short) ?? "All good")
                    .font(Theme.sans(13, .medium)).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Text("Spruce").font(Theme.sans(15, .semibold))
            }
            Spacer(minLength: 0)
            CloseButton(action: close)
        }
    }

    /// "Disk is almost full — 4 GB free" → "Disk is almost full".
    private static func short(_ note: String) -> String {
        String(note.split(separator: "—").first ?? Substring(note)).trimmingCharacters(in: .whitespaces)
    }

    private var chips: some View {
        HStack(spacing: 6) {
            ForEach([model.machine.chip, Format.bytes(model.machine.memoryBytes), "macOS \(model.machine.osVersion)"], id: \.self) { text in
                Text(text).font(Theme.mono(11)).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Theme.chipFill))
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder private var readyRow: some View {
        HStack(spacing: 10) {
            if let name = model.busy, model.quickScanning == nil {
                GradientSpinner(size: 14)
                Text(name).font(Theme.mono(11)).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
            } else if let smart = model.smart {
                Text(Format.bytes(smart.quickWinBytes)).font(Theme.mono(18, .bold))
                Text(smart.quickWinBytes > 0 ? "safe to clean" : "nothing to clean")
                    .font(Theme.mono(11)).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
                Button("Spruce Up") {
                    close()
                    AppDelegate.showMainWindow()
                    model.selection = .smartScan
                    model.cleanNow()
                }
                .buttonStyle(.brand)
                .disabled(smart.quickWinBytes == 0)
            } else {
                Text("Find what's safe to clean").font(Theme.sans(13)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("Smart Scan") { Task { await model.runSmartScan() } }.buttonStyle(.brand)
            }
        }
        .padding(.leading, 14).padding(.trailing, 8).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous).fill(Theme.cardFill))
    }

    private var footer: some View {
        HStack(spacing: 14) {
            ForEach([Module.smartScan, .status, .cleanup, .uninstaller, .health], id: \.self) { module in
                Button {
                    close()
                    AppDelegate.showMainWindow()
                    model.selection = module
                } label: {
                    Image(systemName: module.symbol)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(module.accent)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Theme.chipFill))
                }
                .buttonStyle(.plain)
                .help(module.title)
            }
            Spacer()
            Button("Open Spruce") { close(); AppDelegate.showMainWindow() }
                .buttonStyle(.plain)
                .font(Theme.sans(13, .semibold))
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Quit Spruce")
        }
    }
}

/// A compact metric tile for the menu bar panel.
private struct HUDTile<ChartContent: View>: View {
    var metric: Metric
    var title: String
    var value: String
    var unit: String
    var footer: String
    @ViewBuilder var chart: () -> ChartContent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: metric.symbol).font(.system(size: 10, weight: .bold))
                Text(title.uppercased()).font(Theme.mono(10, .bold)).tracking(1)
            }
            .foregroundStyle(metric.color)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(Theme.mono(20, .bold)).lineLimit(1).minimumScaleFactor(0.6)
                Text(unit).font(Theme.mono(11)).foregroundStyle(.secondary)
            }
            chart()
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 26)
            Text(footer.isEmpty ? " " : footer).font(Theme.mono(10)).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous).fill(Theme.cardFill))
    }
}
