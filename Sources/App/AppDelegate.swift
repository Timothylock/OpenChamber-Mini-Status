import AppKit

/// Wires the three pieces together: the floating widget, the menu bar item and settings.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences: Preferences
    private let store: SessionStore
    private var hud: HUDController?
    private var menuBar: MenuBarController?
    private var settings: SettingsWindowController?

    init(preferences: Preferences = Preferences(), store: SessionStore? = nil) {
        self.preferences = preferences
        self.store = store ?? SessionStore(preferences: preferences)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        preferences.applyLoginItem()

        let hud = HUDController(store: store, preferences: preferences, onSettings: { [weak self] in
            self?.showSettings()
        })
        self.hud = hud
        hud.start()

        let menuBar = MenuBarController(preferences: preferences, onSettings: { [weak self] in
            self?.showSettings()
        })
        self.menuBar = menuBar
        menuBar.install()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hud?.stop()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    /// Reopening the app is the documented way back when the menu bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func showSettings() {
        let controller = settings ?? SettingsWindowController(
            preferences: preferences,
            onResetPosition: { [weak self] in self?.hud?.resetPosition() }
        )
        settings = controller
        controller.show()
    }
}
