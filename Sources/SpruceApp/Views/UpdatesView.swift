import SwiftUI
import SpruceCore

/// Apps with a newer version, grouped by where the update comes from. Spruce only finds them:
/// Homebrew, the App Store or the app's own updater does the updating.
struct UpdatesView: View {
    @Environment(AppModel.self) private var model
    @State private var showUnchecked = false

    private var report: UpdateReport? { model.updateReport }

    var body: some View {
        ModuleScroll {
            if let report {
                results(report)
            } else {
                start
            }
        }
        .navigationTitle("Updates")
        .onChange(of: model.tourSubpage) { _, page in
            if page == "updates-check" { Task { await model.checkUpdates() } }
        }
    }

    private var start: some View {
        VStack(spacing: 4) {
            ToolHero(module: .updates, title: "Updates", subtitle: "Newer versions of the apps you have.") {
                Button("Check") { Task { await model.checkUpdates() } }
                    .buttonStyle(.brand)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.busy != nil)
            }
            Text("Asks each app's own update feed, Apple's App Store and Homebrew. Only app IDs are sent, nothing else about this Mac.")
                .font(Theme.mono(11)).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center).frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func results(_ report: UpdateReport) -> some View {
        let ready = report.updates.filter(\.installable)
        let nothingChecked = report.updates.isEmpty && report.upToDate.isEmpty
        HeroHeader(title: "Updates",
                   value: nothingChecked ? "Nothing to check" : report.updates.isEmpty ? "All current" : "\(report.updates.count) available",
                   caption: "Checked \(Format.relative(report.checkedAt))"
                       + (report.upToDate.isEmpty ? "" : " · \(report.upToDate.count) \(report.upToDate.count == 1 ? "app" : "apps") up to date"),
                   symbol: Module.updates.symbol) {
            Button("Check Again") { Task { await model.checkUpdates() } }.disabled(model.busy != nil)
            if !ready.isEmpty {
                Button(ready.count == 1 ? "Update" : "Update All \(ready.count)") { model.confirmUpdates(ready) }
                    .buttonStyle(.brand)
                    .disabled(model.busy != nil)
            }
        }
        if nothingChecked {
            EmptyState(symbol: "questionmark.app", title: "No apps Spruce can check",
                       message: "None of your apps came from Homebrew or the App Store, or use an update feed Spruce can read. They still update themselves.", sphere: false)
                .card()
        } else if report.updates.isEmpty {
            EmptyState(symbol: "checkmark.circle", title: "Everything is up to date",
                       message: "Every app Spruce can check has its newest version.", sphere: false)
                .card()
        }
        ForEach(UpdateSource.allCases, id: \.self) { source in
            let list = report.updates.filter { $0.source == source }
            if !list.isEmpty { section(source, list) }
        }
        if !report.unchecked.isEmpty || !report.failed.isEmpty { footnotes(report) }
    }

    private func section(_ source: UpdateSource, _ list: [AppUpdate]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionTitle(title: source.rawValue, symbol: nil, trailing: "\(list.count)")
                if source == .appStore {
                    Button("Open App Store Updates") { model.openURL("macappstore://showUpdatesPage") }
                        .controlSize(.small)
                }
            }
            .padding(.vertical, 8)
            Text(Self.howTo(source)).font(.caption).foregroundStyle(.secondary).padding(.bottom, 6)
            ForEach(Array(list.enumerated()), id: \.element.id) { index, update in
                RowDivider(inset: index == 0 ? 0 : 44)
                row(update).reveal(index: index)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
        .surface()
    }

    private static func howTo(_ source: UpdateSource) -> String {
        switch source {
        case .homebrew: return "Installed with Homebrew. Spruce updates them with brew upgrade."
        case .appStore: return "Spruce updates these through the App Store with the mas tool, installing it with Homebrew if needed. You need to be signed in to the App Store."
        case .builtIn: return "Spruce downloads each new version from the developer, checks its signature, and swaps it in. Open apps are quit and reopened."
        }
    }

    private func row(_ update: AppUpdate) -> some View {
        HStack(spacing: 12) {
            Image(nsImage: FileIcon.image(update.appPath)).resizable().frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(update.name).font(Theme.sans(13, .medium)).lineLimit(1).truncationMode(.middle)
                HStack(spacing: 6) {
                    Text(update.installed).foregroundStyle(.secondary)
                    Image(systemName: "arrow.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
                    Text(update.latest).foregroundStyle(Module.updates.accentText)
                }
                .font(Theme.mono(11)).lineLimit(1)
            }
            Spacer(minLength: 8)
            if let notes = update.releaseNotesURL {
                Button("What's New") { model.openURL(notes) }.buttonStyle(.borderless).controlSize(.small)
            }
            if update.installable {
                Button("Update") { model.confirmUpdates([update]) }.disabled(model.busy != nil)
            } else {
                Button("Open \(update.name)") { model.openApp(update.appPath) }
                    .help("This app's feed has no download Spruce can verify; it updates itself when opened.")
            }
        }
        .padding(.vertical, 9)
        .rowHover()
    }

    private func footnotes(_ report: UpdateReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !report.failed.isEmpty {
                Label("Couldn't reach the update feed for \(report.failed.joined(separator: ", ")). Try again later.",
                      systemImage: "wifi.exclamationmark")
                    .font(.caption).foregroundStyle(Theme.review)
            }
            if !report.unchecked.isEmpty {
                DisclosureGroup(isExpanded: $showUnchecked) {
                    Text(report.unchecked.joined(separator: ", "))
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                } label: {
                    Text("\(report.unchecked.count) \(report.unchecked.count == 1 ? "app updates itself" : "apps update themselves") in a way Spruce can't read")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Chrome, Electron apps and apps with their own installers keep themselves current. Their own Check for Updates still works.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            if !report.usedHomebrew {
                Text("Homebrew isn't installed, so apps installed with it aren't checked.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface()
    }
}
