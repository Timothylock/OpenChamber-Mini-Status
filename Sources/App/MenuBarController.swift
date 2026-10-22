import AppKit
import Combine

/// The menu bar item: the one way back into settings when the widget is hidden or moved away.
final class MenuBarController: NSObject {
    private let preferences: Preferences
    private let onSettings: () -> Void
    private var item: NSStatusItem?
    private var cancellable: AnyCancellable?

    init(preferences: Preferences, onSettings: @escaping () -> Void) {
        self.preferences = preferences
        self.onSettings = onSettings
        super.init()
    }

    func install() {
        applyVisibility()
        cancellable = preferences.$hideTrayIcon
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyVisibility() }
    }

    private func applyVisibility() {
        if preferences.hideTrayIcon {
            if let item {
                NSStatusBar.system.removeStatusItem(item)
                self.item = nil
            }
        } else if item == nil {
            item = makeItem()
        }
    }

    private func makeItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(
                systemSymbolName: "gauge.medium",
                accessibilityDescription: "OpenChamber Mini Status"
            )
            image?.isTemplate = true
            button.image = image
            button.toolTip = "OpenChamber Mini Status"
        }

        let menu = NSMenu()
        let settings = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(
            title: "Quit OpenChamber Mini Status",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        return item
    }

    @objc private func openSettings() {
        onSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
