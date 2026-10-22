import Foundation

/// Every tunable in one place, with the on-disk locations the app reads.
public enum Config {
    // MARK: rows

    /// How many chats the widget shows. Waiting chats win, then running, then recent.
    public static let rowLimit = 4
    /// A chat with no idle stamp counts as running only while it is still being written to.
    public static let runningWindow: Int64 = 120 * 1000
    /// OpenChamber's In work flag lags a turn's end by a few seconds; hold the blue look that long.
    public static let graceWindow: Int64 = 5 * 1000
    /// Chats left In work for this long are history, not running (some archived ones are weeks old).
    public static let staleWorkWindow: Int64 = 2 * 60 * 60 * 1000

    // MARK: polling

    public static let refreshInterval: TimeInterval = 1
    public static let contextInterval: TimeInterval = 4
    /// Chats asked for context usage per tick; the rest keep their last known value.
    public static let contextTargetLimit = 14
    /// Directories asked for running background shells per tick.
    public static let shellDirectoryLimit = 40
    /// Directories asked for pending permissions and forms when the desktop API is off.
    /// A chat waiting on a prompt was touched when it asked, so it sits near the top.
    public static let fallbackDirectoryLimit = 12
    public static let modelCacheTTL: TimeInterval = 900
    public static let archiveCacheTTL: TimeInterval = 15
    public static let serverRetryInterval: TimeInterval = 5

    // MARK: window

    public static let windowWidth: CGFloat = 330
    public static let restAlpha: CGFloat = 0.95
    public static let hoverAlpha: CGFloat = 0.55
    public static let edgeInset: CGFloat = 18
    public static let cornerRadius: CGFloat = 16
    /// Context usage past this share is where compaction starts to loom.
    public static let compactionWarning = 0.85

    // MARK: locations

    public static var home: String {
        FileManager.default.homeDirectoryForCurrentUser.path
    }

    public static var openChamberDirectory: String {
        home + "/.config/openchamber"
    }

    /// The session database owned by the OpenChamber-managed opencode server.
    public static var databasePath: String {
        if let override = ProcessInfo.processInfo.environment["MINI_STATUS_DB"], !override.isEmpty {
            return override
        }
        return home + "/.local/share/opencode/opencode.db"
    }

    public static var archivePath: String {
        openChamberDirectory + "/sessions-archive.json"
    }

    /// Holds the desktop server's port and client token.
    public static var settingsPath: String {
        if let override = ProcessInfo.processInfo.environment["MINI_STATUS_SETTINGS"], !override.isEmpty {
            return override
        }
        return openChamberDirectory + "/settings.json"
    }

    public static var directoriesPath: String {
        openChamberDirectory + "/sessions-directories.json"
    }

    public static var managedServersDirectory: String {
        openChamberDirectory + "/managed-opencode"
    }

    public static let openChamberBundleIdentifier = "dev.openchamber.desktop"
    public static let openChamberApplicationPath = "/Applications/OpenChamber.app"

    public static func chatURL(sessionID: String) -> URL? {
        URL(string: "openchamber://session/\(sessionID)")
    }
}
