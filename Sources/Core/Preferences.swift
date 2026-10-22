import Combine
import Foundation
import ServiceManagement

/// User-facing switches, persisted in the app's own defaults so nothing else needs a plist.
public final class Preferences: ObservableObject {
    public enum Key {
        public static let startAtLogin = "pref.startAtLogin"
        public static let fadeOnHover = "pref.fadeOnHover"
        public static let hideTrayIcon = "pref.hideTrayIcon"
        public static let onlyActive = "pref.onlyActive"
    }

    private let defaults: UserDefaults

    @Published public var startAtLogin: Bool {
        didSet {
            guard !syncing else { return }
            defaults.set(startAtLogin, forKey: Key.startAtLogin)
            LoginItem.setEnabled(startAtLogin)
        }
    }

    @Published public var fadeOnHover: Bool {
        didSet {
            guard !syncing else { return }
            defaults.set(fadeOnHover, forKey: Key.fadeOnHover)
        }
    }

    @Published public var hideTrayIcon: Bool {
        didSet {
            guard !syncing else { return }
            defaults.set(hideTrayIcon, forKey: Key.hideTrayIcon)
        }
    }

    /// Hides grey rows: chats that finished and are not waiting on you.
    @Published public var onlyActive: Bool {
        didSet {
            guard !syncing else { return }
            defaults.set(onlyActive, forKey: Key.onlyActive)
        }
    }

    private var syncing = false

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.startAtLogin: true,
            Key.fadeOnHover: true,
            Key.hideTrayIcon: false,
            Key.onlyActive: false,
        ])
        startAtLogin = defaults.bool(forKey: Key.startAtLogin)
        fadeOnHover = defaults.bool(forKey: Key.fadeOnHover)
        hideTrayIcon = defaults.bool(forKey: Key.hideTrayIcon)
        onlyActive = defaults.bool(forKey: Key.onlyActive)
    }

    /// Re-applies the saved login choice on launch, which repairs a moved app or a stale agent.
    public func applyLoginItem() {
        guard startAtLogin else { return }
        LoginItem.setEnabled(true)
    }
}

/// Login item handling: the modern API first, a LaunchAgent for the ad hoc signed builds.
public enum LoginItem {
    public static let label = "dev.openchamber.mini-status"

    public static var agentPath: String {
        Config.home + "/Library/LaunchAgents/" + label + ".plist"
    }

    /// A login item only makes sense once the app sits where the user keeps apps.
    public static var isInstallLocation: Bool {
        let bundle = Bundle.main.bundlePath
        return bundle.hasPrefix("/Applications/") || bundle.hasPrefix(Config.home + "/Applications/")
    }

    public static func setEnabled(_ enabled: Bool) {
        guard isInstallLocation else {
            Log.window.info("login item skipped, app is not in Applications")
            return
        }
        if enabled {
            register()
        } else {
            unregister()
        }
    }

    private static var smAppServiceEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    private static func register() {
        if smAppServiceEnabled { return }
        do {
            try SMAppService.mainApp.register()
            Log.window.info("login item registered with the system")
            removeAgent()
        } catch {
            Log.window.info("system login item refused: \(error.localizedDescription, privacy: .public)")
            writeAgent()
        }
    }

    private static func unregister() {
        if smAppServiceEnabled {
            do {
                try SMAppService.mainApp.unregister()
            } catch {
                Log.window.info("could not unregister login item: \(error.localizedDescription, privacy: .public)")
            }
        }
        removeAgent()
    }

    /// Fallback used when the system refuses the app: a per-user LaunchAgent that restarts it on login.
    private static func writeAgent() {
        let executable = Bundle.main.executablePath ?? CommandLine.arguments.first ?? ""
        let agents = Config.home + "/Library/LaunchAgents"
        try? FileManager.default.createDirectory(atPath: agents, withIntermediateDirectories: true)
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key><string>\(label)</string>
          <key>ProgramArguments</key>
          <array><string>\(executable)</string></array>
          <key>RunAtLoad</key><true/>
          <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
          <key>ProcessType</key><string>Interactive</string>
        </dict>
        </plist>
        """
        try? plist.write(toFile: agentPath, atomically: true, encoding: .utf8)
        Log.window.info("login item written as a LaunchAgent")
    }

    private static func removeAgent() {
        guard FileManager.default.fileExists(atPath: agentPath) else { return }
        bootoutAgent()
        try? FileManager.default.removeItem(atPath: agentPath)
    }

    private static func bootoutAgent() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["bootout", "gui/\(getuid())/\(label)"]
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}
