import SwiftUI
import Charts
import SpruceCore

extension Metric {
    var color: Color {
        switch self {
        case .cpu: return Color(hex: 0x3CB371)
        case .load: return Color(hex: 0xF0714E)
        case .memory: return Color(hex: 0xE6A93C)
        case .swap: return Color(hex: 0x8E84F0)
        case .diskFree: return Color(hex: 0x4FA3E3)
        case .netIn: return Color(hex: 0x16A37F)
        case .netOut: return Color(hex: 0x5B8DEF)
        }
    }

    var symbol: String {
        switch self {
        case .cpu: return "cpu"
        case .load: return "chart.bar"
        case .memory: return "memorychip"
        case .swap: return "arrow.left.arrow.right"
        case .diskFree: return "internaldrive"
        case .netIn: return "arrow.down"
        case .netOut: return "arrow.up"
        }
    }
}

/// Live vitals (Now) and the local history behind them (History).
struct StatusView: View {
    @Environment(AppModel.self) private var model
    @State private var mode = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                PillPicker(selection: $mode, options: [(0, "Now", "waveform.path.ecg"), (1, "History", "chart.xyaxis.line")])
                Spacer()
            }
            .padding(.horizontal, 32).padding(.bottom, 4)
            Group {
                if mode == 0 { StatusNow() } else { StatusHistory() }
            }
            .id(mode)
            .transition(.moduleSwap)
        }
        .animation(Theme.spring, value: mode)
        .padding(.top, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { MetricsMonitor.shared.watch() }
        .onDisappear { MetricsMonitor.shared.unwatch() }
    }
}

// MARK: - Now

private struct StatusNow: View {
    @Environment(AppModel.self) private var model
    @State private var daysUntilFull: Double?

    private var monitor: MetricsMonitor { .shared }

    var body: some View {
        let live = monitor.live.suffix(40)
        let latest = monitor.latest
        ModuleScroll {
            header
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 14)], spacing: 14) {
                MetricCard(metric: .cpu, title: "CPU", value: latest.map { String(format: "%.1f", $0.cpu) } ?? "—", unit: "%",
                           badge: nil, footer: latest.map { String(format: "load %.2f", $0.load) } ?? "") {
                    Chart(Array(live.enumerated()), id: \.offset) { index, sample in
                        BarMark(x: .value("t", index), y: .value("CPU", max(sample.cpu, 1)))
                            .foregroundStyle(Metric.cpu.color)
                            .cornerRadius(2)
                    }
                    .chartYScale(domain: 0...100)
                }
                MetricCard(metric: .memory, title: "Memory", value: latest.map { String(format: "%.0f", $0.memory) } ?? "—", unit: "%",
                           badge: model.health?.memory.pressure.lowercased(),
                           footer: latest.map { "swap \(Format.bytes($0.swapBytes))" } ?? "") {
                    area(live.map(\.memory), color: Metric.memory.color, domain: 0...100)
                }
                MetricCard(metric: .load, title: "Load", value: latest.map { String(format: "%.2f", $0.load) } ?? "—", unit: "1m avg",
                           badge: "\(ProcessInfo.processInfo.activeProcessorCount) cores", footer: "") {
                    line(live.map(\.load), color: Metric.load.color)
                }
                diskCard(latest)
                MetricCard(metric: .netIn, title: "Network", value: latest.map { Format.bytes(Int64($0.netIn)) } ?? "—", unit: "/s",
                           badge: nil,
                           footer: latest.map { "↓ \(Format.bytes(Int64($0.netIn)))/s   ↑ \(Format.bytes(Int64($0.netOut)))/s" } ?? "") {
                    Chart {
                        ForEach(Array(live.enumerated()), id: \.offset) { index, sample in
                            LineMark(x: .value("t", index), y: .value("bytes", sample.netIn), series: .value("dir", "in"))
                                .foregroundStyle(Metric.netIn.color)
                            LineMark(x: .value("t", index), y: .value("bytes", sample.netOut), series: .value("dir", "out"))
                                .foregroundStyle(Metric.netOut.color)
                        }
                    }
                }
                healthCard
            }
            .reveal(delay: 0.04)
        }
        .task {
            let points = await MetricsMonitor.shared.series(.diskFree, over: 14 * 86_400, points: 28)
            daysUntilFull = DiskForecast.daysUntilFull(points)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 20) {
            if let health = model.health {
                ScoreRing(score: health.score, size: 92)
                VStack(alignment: .leading, spacing: 4) {
                    Text("STATUS").font(Theme.mono(11, .semibold)).tracking(1.4).foregroundStyle(Module.status.accentText)
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(health.score)").font(Theme.sans(46, .semibold))
                        Text(health.score >= 80 ? "Good" : health.score >= 60 ? "Fair" : "Poor")
                            .font(Theme.sans(20, .medium)).foregroundStyle(Theme.scoreColor(health.score))
                    }
                    Text(health.notes.first ?? "Nothing needs attention").font(Theme.sans(13)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(model.machine.chip) · \(Format.bytes(model.machine.memoryBytes)) · macOS \(model.machine.osVersion)")
                Text("sampling every \(monitor.watchers > 0 ? "2 s" : "30 s") · kept 90 days")
            }
            .font(Theme.mono(11)).foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .task { if model.health == nil { await model.refreshHealth() } }
    }

    private func diskCard(_ latest: MetricSample?) -> some View {
        let used = model.health?.disk.usedFraction ?? 0
        let forecast = daysUntilFull.map { days -> String in
            days > 365 ? "full in over a year" : days > 60 ? "full in ~\(Int(days / 30)) months" : "full in ~\(Int(days)) days"
        }
        return MetricCard(metric: .diskFree, title: "Disk", value: latest.map { Format.bytes($0.diskFreeBytes) } ?? "—", unit: "free",
                          badge: model.health.map { Format.bytes($0.disk.totalBytes) },
                          footer: "\(Int(used * 100))% used" + (forecast.map { " · \($0)" } ?? "")) {
            VStack {
                Spacer()
                GrowingBar(fraction: used, fill: used > 0.9 ? Theme.danger
                           : LinearGradient(colors: [Metric.diskFree.color, Color(hex: 0xE6A93C)], startPoint: .leading, endPoint: .trailing),
                           height: 8)
                Spacer()
            }
        }
    }

    private var healthCard: some View {
        let security = model.health?.security
        let issues = security?.issues ?? []
        return MetricCard(metric: .swap, title: "Security", value: issues.isEmpty ? "All on" : "\(issues.count)", unit: issues.isEmpty ? "" : "to fix",
                          badge: nil, footer: issues.isEmpty ? "SIP · Gatekeeper · FileVault · Firewall" : issues.joined(separator: " · "),
                          tint: issues.isEmpty ? Theme.safe : Theme.risky, symbol: "checkmark.shield") {
            HStack(spacing: 6) {
                ForEach(["SIP", "Gatekeeper", "FileVault", "Firewall"], id: \.self) { name in
                    let on: Bool? = name == "SIP" ? security?.sip : name == "Gatekeeper" ? security?.gatekeeper
                        : name == "FileVault" ? security?.fileVault : security?.firewall
                    Capsule().fill(on == false ? Theme.risky : on == true ? Theme.safe : Theme.track).frame(height: 8)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func area(_ values: [Double], color: Color, domain: ClosedRange<Double>? = nil) -> some View {
        Chart(Array(values.enumerated()), id: \.offset) { index, value in
            AreaMark(x: .value("t", index), y: .value("v", value))
                .foregroundStyle(LinearGradient(colors: [color.opacity(0.35), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.monotone)
            LineMark(x: .value("t", index), y: .value("v", value))
                .foregroundStyle(color)
                .interpolationMethod(.monotone)
        }
        .chartYScale(domain: domain ?? 0...max(values.max() ?? 1, 0.01) * 1.15)
    }

    private func line(_ values: [Double], color: Color) -> some View {
        Chart(Array(values.enumerated()), id: \.offset) { index, value in
            LineMark(x: .value("t", index), y: .value("v", value))
                .foregroundStyle(color)
                .interpolationMethod(.monotone)
        }
        .chartYScale(domain: 0...max(values.max() ?? 1, 0.01) * 1.15)
    }
}

/// A Status card: coloured label and badge, the reading in large type, a small chart, a footer.
private struct MetricCard<ChartContent: View>: View {
    var metric: Metric
    var title: String
    var value: String
    var unit: String
    var badge: String?
    var footer: String
    var tint: Color? = nil
    var symbol: String? = nil
    @ViewBuilder var chart: () -> ChartContent

    var body: some View {
        let color = tint ?? metric.color
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: symbol ?? metric.symbol).font(.system(size: 11, weight: .semibold))
                Text(title.uppercased()).font(Theme.mono(11, .semibold)).tracking(1.4)
                Spacer()
                if let badge {
                    Text(badge).font(Theme.mono(11)).foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Theme.chipFill))
                }
            }
            .foregroundStyle(color)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(Theme.sans(34, .semibold)).lineLimit(1).minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                Text(unit).font(Theme.mono(13)).foregroundStyle(.secondary)
            }
            chart()
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 52)
            Text(footer.isEmpty ? " " : footer).font(Theme.mono(11)).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface()
    }
}

// MARK: - History

private struct StatusHistory: View {
    private static let ranges: [(String, TimeInterval)] = [
        ("5m", 300), ("1h", 3600), ("6h", 21_600), ("24h", 86_400), ("7d", 604_800), ("30d", 2_592_000), ("90d", 7_776_000),
    ]

    @State private var range: TimeInterval = 21_600
    @State private var selected: Metric = .cpu
    @State private var series: [Metric: [MetricPoint]] = [:]
    @State private var samples = 0
    @Namespace private var namespace

    private var monitor: MetricsMonitor { .shared }

    var body: some View {
        ModuleScroll {
            HStack(alignment: .center, spacing: 16) {
                Text("History").font(Theme.display(30))
                HStack(spacing: 2) {
                    ForEach(Self.ranges, id: \.0) { label, seconds in
                        Button {
                            SoundFX.shared.play(.select)
                            withAnimation(Theme.spring) { range = seconds }
                        } label: {
                            Text(label)
                                .font(Theme.mono(12, range == seconds ? .semibold : .regular))
                                .foregroundStyle(range == seconds ? Theme.onInverse : Theme.text.opacity(0.7))
                                .padding(.horizontal, 12).frame(height: 26)
                                .background { if range == seconds { Capsule().fill(Theme.inverse).matchedGeometryEffect(id: "range", in: namespace) } }
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(Capsule().fill(Theme.chipFill))
                .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
                Spacer()
                Text("\(samples) samples\(monitor.latest.map { " · latest \(Format.relative($0.time))" } ?? "")")
                    .font(Theme.mono(11)).foregroundStyle(.secondary)
            }
            bigChart
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                ForEach(Metric.allCases) { metric in
                    smallCard(metric)
                }
            }
            InfoNote(text: "Spruce records these while it's running (in the menu bar counts), one sample every 30 seconds, and keeps 90 days on this Mac only.")
        }
        .task(id: range) { await load() }
    }

    private var bigChart: some View {
        let points = series[selected] ?? []
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: selected.symbol).font(.system(size: 11, weight: .semibold))
                Text(selected.title.uppercased()).font(Theme.mono(11, .semibold)).tracking(1.4)
                Spacer()
                if let peak = points.map(\.peak).max() {
                    Text("peak \(selected.format(peak))").font(Theme.mono(11)).foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(selected.color)
            if points.isEmpty {
                Text("No samples in this range yet. Spruce records while it's running.")
                    .font(Theme.sans(13)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                Chart(points) { point in
                    if selected == .cpu {
                        BarMark(x: .value("Time", point.time), y: .value(selected.title, point.average))
                            .foregroundStyle(selected.color)
                    } else {
                        AreaMark(x: .value("Time", point.time), y: .value(selected.title, point.average))
                            .foregroundStyle(LinearGradient(colors: [selected.color.opacity(0.3), selected.color.opacity(0)],
                                                            startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("Time", point.time), y: .value(selected.title, point.average))
                            .foregroundStyle(selected.color)
                            .interpolationMethod(.monotone)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                        AxisGridLine().foregroundStyle(Theme.hairline)
                        AxisValueLabel().font(Theme.mono(10)).foregroundStyle(.secondary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine().foregroundStyle(Theme.hairline)
                        AxisValueLabel {
                            if let v = value.as(Double.self) { Text(selected.format(v)).font(Theme.mono(10)) }
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 260)
            }
        }
        .padding(20)
        .surface(cornerRadius: Theme.radiusLarge)
        .animation(Theme.spring, value: selected)
    }

    private func smallCard(_ metric: Metric) -> some View {
        let points = series[metric] ?? []
        let isSelected = metric == selected
        return Button {
            SoundFX.shared.play(.select)
            withAnimation(Theme.spring) { selected = metric }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle().fill(metric.color).frame(width: 7, height: 7)
                    Text(metric.title.uppercased()).font(Theme.mono(10, .semibold)).tracking(1.2).foregroundStyle(.secondary)
                }
                Text(points.last.map { metric.format($0.average) } ?? "—").font(Theme.sans(22, .semibold)).lineLimit(1)
                Chart(points) { point in
                    LineMark(x: .value("Time", point.time), y: .value("v", point.average))
                        .foregroundStyle(metric.color)
                        .interpolationMethod(.monotone)
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 34)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surface()
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                .strokeBorder(isSelected ? metric.color : .clear, lineWidth: 1.5))
            .contentShape(RoundedRectangle(cornerRadius: Theme.radiusCard))
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        var loaded: [Metric: [MetricPoint]] = [:]
        for metric in Metric.allCases {
            loaded[metric] = await monitor.series(metric, over: range, points: metric == selected ? 180 : 60)
        }
        series = loaded
        samples = await monitor.sampleCount(over: range)
    }
}
