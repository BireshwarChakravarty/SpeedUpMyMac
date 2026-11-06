import AppKit
import SwiftUI
import SpruceCore

/// Spruce's menu bar item. A click opens a floating panel that stays open while you work in other
/// apps, so you can drag an app into it from Finder. SwiftUI's MenuBarExtra closes the moment
/// Finder is clicked, which made that impossible. You can also drop an app straight on the icon.
@MainActor
final class StatusItemController: NSObject, NSWindowDelegate, NSDraggingDestination {
    static private(set) var shared: StatusItemController?

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let model: AppModel
    private var panel: RootPanel?
    /// The point under the menu bar icon the panel hangs from, so it grows downwards.
    private var anchorTop: CGFloat = 0

    static func install(model: AppModel) {
        shared = StatusItemController(model: model)
    }

    private init(model: AppModel) {
        self.model = model
        super.init()
        guard let button = item.button else { return }
        button.image = NSImage(systemSymbolName: "number", accessibilityDescription: "Spruce")
        button.target = self
        button.action = #selector(toggle)
        // The status item's own window forwards drag events to its delegate.
        button.window?.registerForDraggedTypes([.fileURL])
        button.window?.delegate = self
    }

    var isShown: Bool { panel?.isVisible ?? false }

    @objc func toggle() {
        isShown ? hide() : show()
    }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if let host = panel.contentView { panel.setContentSize(host.fittingSize) }
        if let button = item.button, let window = button.window {
            let icon = window.convertToScreen(button.convert(button.bounds, to: nil))
            anchorTop = icon.minY - 6
            let size = panel.frame.size
            var x = icon.midX - size.width / 2
            if let screen = window.screen?.visibleFrame { x = min(max(x, screen.minX + 8), screen.maxX - size.width - 8) }
            panel.setFrameOrigin(NSPoint(x: x, y: anchorTop - size.height))
        }
        panel.orderFrontRegardless()
        panel.makeKey()
        item.button?.highlight(true)
        Task { if model.health == nil { await model.refreshHealth() } }
    }

    func hide() {
        panel?.orderOut(nil)
        item.button?.highlight(false)
    }

    private func makePanel() -> RootPanel {
        let panel = RootPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 480),
                              styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
                              backing: .buffered, defer: true)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        let dark = UserDefaults.standard.object(forKey: alwaysDarkKey) as? Bool ?? true
        let root = MenuBarView(close: { [weak self] in self?.hide() })
            .environment(model)
            .preferredColorScheme(dark ? .dark : nil)
            .tint(Theme.leaf)
            .fixedSize()
            .onGeometryChange(for: CGSize.self, of: \.size) { [weak self] size in self?.fit(size) }
        let host = NSHostingView(rootView: root)
        panel.contentView = host
        panel.setContentSize(host.fittingSize)
        panel.delegate = self
        panel.onEscape = { [weak self] in self?.hide() }
        return panel
    }

    /// Sizes the panel to its content, hanging from the menu bar as the content grows or shrinks.
    private func fit(_ size: CGSize) {
        guard let panel, size.width > 0, size.height > 0 else { return }
        var frame = panel.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        frame.origin.x = panel.frame.minX
        frame.origin.y = (anchorTop > 0 ? anchorTop : panel.frame.maxY) - frame.height
        panel.setFrame(frame, display: true, animate: false)
    }

    /// For the CI tour's log.
    var panelDescription: String {
        guard let panel else { return "no panel" }
        return "visible=\(panel.isVisible) frame=\(NSStringFromRect(panel.frame)) screen=\(NSStringFromRect(panel.screen?.frame ?? .zero))"
    }

    // MARK: Dropping an app on the menu bar icon

    private func droppedApp(_ sender: NSDraggingInfo) -> URL? {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                         options: [.urlReadingFileURLsOnly: true]) as? [URL]
        return urls?.first { $0.pathExtension == "app" }
    }

    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard droppedApp(sender) != nil else { return [] }
        item.button?.highlight(true)
        return .copy
    }

    func draggingExited(_ sender: NSDraggingInfo?) {
        if !isShown { item.button?.highlight(false) }
    }

    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = droppedApp(sender) else { return false }
        show()
        Task { await model.quickScan(url.path) }
        return true
    }
}

/// A floating panel that closes on Esc and can take keyboard focus without activating Spruce.
final class RootPanel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}
