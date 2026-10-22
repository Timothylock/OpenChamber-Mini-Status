import Combine
import Foundation
import SQLite3
import os

/// What the window should say when it has nothing to show.
public enum StoreStatus: Equatable {
    case ready
    case databaseUnavailable
}

/// Reads OpenChamber's session database and turns it into four rows.
public final class SessionStore: ObservableObject {
    @Published public private(set) var rows: [Row] = []
    @Published public private(set) var now: Int64 = 0
    @Published public private(set) var status: StoreStatus = .ready
    /// Mirrors the setting so the view can explain an empty list.
    @Published public private(set) var onlyActive = false

    private let databasePath: String
    private let archivePath: String
    private let directoriesPath: String
    private let defaults: UserDefaults
    private let context: ContextProvider
    private let preferences: Preferences
    private let remote = RemoteStateClient()
    private let logger = Log.store
    /// Turns that ended before the widget started were already seen or dismissed;
    /// only later ones wait for a click.
    private let launchedAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)

    private var db: OpaquePointer?
    private var timer: Timer?
    private var acked: [String: Int64]
    private var preferenceCancellable: AnyCancellable?
    private var grace = PhaseGrace()
    private var remoteStates: [String: RemoteSession] = [:]
    private var archived: Set<String> = []
    private var archiveLoadedAt: Date?

    private let ackKey = "ackedIdle"

    private static let query = """
        select s.id, s.title, s.directory, s.cost, s.tokens_input, s.tokens_output,
               s.time_created, s.time_updated, s.time_idle, s.metadata, s.model,
               (select m.type from session_message m
                 where m.session_id = s.id and m.type in ('user','assistant')
                 order by m.seq desc limit 1),
               (select m.time_created from session_message m
                 where m.session_id = s.id and m.type = 'user'
                 order by m.seq desc limit 1)
        from session_v2 s
        where s.parent_id is null and s.time_archived is null
        order by s.time_updated desc
        limit 40
        """

    public init(
        databasePath: String = Config.databasePath,
        archivePath: String = Config.archivePath,
        directoriesPath: String = Config.directoriesPath,
        defaults: UserDefaults = .standard,
        context: ContextProvider = ContextProvider(),
        preferences: Preferences = Preferences()
    ) {
        self.databasePath = databasePath
        self.archivePath = archivePath
        self.directoriesPath = directoriesPath
        self.defaults = defaults
        self.context = context
        self.preferences = preferences
        if let raw = defaults.dictionary(forKey: ackKey) as? [String: NSNumber] {
            acked = raw.mapValues { $0.int64Value }
        } else {
            acked = [:]
        }
    }

    deinit {
        timer?.invalidate()
        preferenceCancellable?.cancel()
        if let db { sqlite3_close(db) }
    }

    // MARK: lifecycle

    public func start() {
        openDatabase()
        context.start()
        refresh()

        // OpenChamber's watcher knows busy and unread for real; the database rules are the fallback.
        remote.start { [weak self] states in
            guard let self, self.remoteStates != states else { return }
            self.remoteStates = states
            self.refresh()
        }

        // Rows are filtered before they are cut to four, so the switch can reveal the rest.
        preferenceCancellable = preferences.$onlyActive
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }

        let timer = Timer(timeInterval: Config.refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        preferenceCancellable?.cancel()
        preferenceCancellable = nil
        remote.stop()
        context.stop()
    }

    private func openDatabase() {
        if db != nil { return }
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databasePath, &handle, flags, nil) == SQLITE_OK else {
            if let handle { sqlite3_close(handle) }
            if status != .databaseUnavailable {
                logger.info("session database unavailable at \(self.databasePath, privacy: .public)")
            }
            status = .databaseUnavailable
            return
        }
        sqlite3_busy_timeout(handle, 500)
        db = handle
        status = .ready
    }

    // MARK: reading

    public func refresh() {
        let nowMS = Int64(Date().timeIntervalSince1970 * 1000)
        now = nowMS
        if onlyActive != preferences.onlyActive { onlyActive = preferences.onlyActive }
        openDatabase()
        guard let db else {
            if !rows.isEmpty { rows = [] }
            return
        }

        loadArchivedIfNeeded()

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, Self.query, -1, &statement, nil) == SQLITE_OK else {
            logger.error("session query failed: \(self.lastErrorMessage, privacy: .public)")
            sqlite3_close(db)
            self.db = nil
            status = .databaseUnavailable
            return
        }
        defer { sqlite3_finalize(statement) }

        var attention: [Row] = []
        var running: [Row] = []
        var done: [Row] = []
        var targets: [(id: String, model: String)] = []
        var directories: [String] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let session = session(from: statement) else { continue }
            if let directory = text(statement, 2), !directory.isEmpty, !directories.contains(directory) {
                directories.append(directory)
            }
            let phase = Phases.phase(
                idleAt: session.idleAt,
                lastMessageType: session.lastMessageType,
                updatedAt: session.updatedAt,
                now: nowMS,
                ackedIdle: acked[session.id],
                workState: session.workState,
                remote: remoteStates[session.id],
                hasShell: context.runningShellSessions.contains(session.id),
                unreadAfter: launchedAt
            )
            let shown = grace.resolve(sessionID: session.id, phase: phase, now: nowMS)
            let archivedSession = archived.contains(session.id)
            guard Selection.visible(
                archived: archivedSession,
                phase: shown,
                onlyActive: preferences.onlyActive
            ) else { continue }

            targets.append((id: session.id, model: session.model))
            let row = Row(session: session, phase: shown)
            switch shown {
            case .attention: attention.append(row)
            case .running: running.append(row)
            case .done: done.append(row)
            }
        }

        // Filtering to active chats drops the four-row ceiling: the point is to see all of them.
        let limit = preferences.onlyActive ? Int.max : Config.rowLimit
        rows = Selection.rows(attention: attention, running: running, done: done, limit: limit)
        context.setTargets(targets)
        context.setDirectories(directories)
    }

    private func session(from statement: OpaquePointer?) -> ChatSession? {
        guard let statement, let id = text(statement, 0) else { return nil }
        let directory = text(statement, 2) ?? ""
        let metadata = text(statement, 9) ?? ""
        let model = Format.modelKey(text(statement, 10) ?? "")
        return ChatSession(
            id: id,
            title: text(statement, 1) ?? "untitled",
            project: Format.projectLabel(directory: directory, metadata: metadata),
            cost: sqlite3_column_double(statement, 3),
            tokensIn: sqlite3_column_int64(statement, 4),
            tokensOut: sqlite3_column_int64(statement, 5),
            createdAt: sqlite3_column_int64(statement, 6),
            updatedAt: sqlite3_column_int64(statement, 7),
            idleAt: sqlite3_column_type(statement, 8) == SQLITE_NULL
                ? nil
                : sqlite3_column_int64(statement, 8),
            lastMessageType: text(statement, 11),
            model: model,
            workState: Format.workState(metadata),
            lastUserMessageAt: sqlite3_column_type(statement, 12) == SQLITE_NULL
                ? nil
                : sqlite3_column_int64(statement, 12),
            context: context.usage[id]
        )
    }

    private func text(_ statement: OpaquePointer?, _ column: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: pointer)
    }

    private var lastErrorMessage: String {
        guard let db, let message = sqlite3_errmsg(db) else { return "unknown error" }
        return String(cString: message)
    }

    // MARK: archive

    /// OpenChamber keeps its archive in JSON stores, not in the session rows.
    private func loadArchivedIfNeeded() {
        if let loaded = archiveLoadedAt, Date().timeIntervalSince(loaded) < Config.archiveCacheTTL {
            return
        }
        archiveLoadedAt = Date()
        var ids: Set<String> = []
        for path in [archivePath, directoriesPath] {
            guard let data = FileManager.default.contents(atPath: path) else { continue }
            ids.formUnion(ArchivedSessions.ids(fromJSON: data))
        }
        archived = ids
    }

    // MARK: acknowledgement

    /// Clicking a row counts as having seen the turn that finished. The stamp matches
    /// whichever clock the phase used, so the row stops pulsing immediately.
    public func acknowledge(_ id: String) {
        guard let row = rows.first(where: { $0.id == id }) else { return }
        // The idle stamp is what marks the turn unread, so acknowledge that one even
        // when the API also reports a newer status stamp.
        guard let stamp = row.session.idleAt ?? remoteStates[id]?.stamp, stamp > 0 else { return }
        acked[id] = stamp
        defaults.set(acked.mapValues { NSNumber(value: $0) }, forKey: ackKey)
        refresh()
    }
}

/// Phase rules, kept pure so the ordering is straightforward to reason about and test.
public enum Phases {
    public static func phase(
        idleAt: Int64?,
        lastMessageType: String?,
        updatedAt: Int64,
        now: Int64,
        ackedIdle: Int64?,
        workState: String? = nil,
        remote: RemoteSession? = nil,
        hasShell: Bool = false,
        unreadAfter: Int64 = 0,
        runningWindow: Int64 = Config.runningWindow,
        staleWorkWindow: Int64 = Config.staleWorkWindow
    ) -> Phase {
        // OpenChamber's watcher has the real answer when it is reachable. Its
        // needsAttention flag is stale by design (nothing clears it), so a turn is
        // unread here until the user opens it, like the green sidebar mark.
        if let remote {
            if remote.blocked { return .attention }
            if remote.idle && hasShell { return .running }
            if remote.idle {
                if let idleAt, lastMessageType == "assistant",
                   idleAt >= unreadAfter, ackedIdle != idleAt {
                    return .attention
                }
                return .done
            }
            return .running
        }
        // A background shell outlives the turn that started it; OpenChamber keeps its
        // terminal icon blue until the command ends.
        if hasShell { return .running }
        // A finished turn that nobody looked at outranks everything.
        if let idleAt {
            let finishedByAssistant = lastMessageType == "assistant"
            let fresh = idleAt >= unreadAfter
            let unacknowledged = ackedIdle != idleAt
            if finishedByAssistant && fresh && unacknowledged {
                return .attention
            }
        }
        // OpenChamber's In work flag is the honest answer: idle stamps stay put while a turn streams.
        // Old chats keep the flag forever, so it only counts while something touched the chat lately.
        if workState == "open" { return now - updatedAt < staleWorkWindow ? .running : .done }
        if idleAt == nil {
            return now - updatedAt < runningWindow ? .running : .done
        }
        return .done
    }
}

/// A chat that just finished stays in its running look for a few seconds, because
/// OpenChamber's In work flag flips after the turn ends and the row would blink out.
public struct PhaseGrace {
    private var runningUntil: [String: Int64] = [:]

    public init() {}

    public mutating func resolve(
        sessionID: String,
        phase: Phase,
        now: Int64,
        window: Int64 = Config.graceWindow
    ) -> Phase {
        runningUntil = runningUntil.filter { $0.value > now }
        if phase == .running {
            runningUntil[sessionID] = now + window
            return .running
        }
        if phase == .done, let until = runningUntil[sessionID], now < until {
            return .running
        }
        return phase
    }
}

/// Archive ids out of OpenChamber's JSON stores, in either shape they have shipped with.
public enum ArchivedSessions {
    public static func ids(fromJSON data: Data) -> Set<String> {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        return ids(from: root)
    }

    public static func ids(from root: [String: Any]) -> Set<String> {
        var ids: Set<String> = []
        // Archived folders sit either at the top level or under "foldersMap".
        ids.formUnion(archivedFolders(in: root))
        if let folders = root["foldersMap"] as? [String: Any] {
            ids.formUnion(archivedFolders(in: folders))
        }
        // The flat store is just session id -> archived timestamp.
        for (key, value) in root where key.hasPrefix("ses_") && value is NSNumber {
            ids.insert(key)
        }
        return ids
    }

    private static func archivedFolders(in map: [String: Any]) -> Set<String> {
        var ids: Set<String> = []
        for (key, value) in map where key.hasPrefix("__archived__") {
            for entry in entries(in: value) {
                ids.formUnion(entry["sessionIds"] as? [String] ?? [])
            }
        }
        return ids
    }

    /// A folder's value has shipped as a list of entries and as a map of them.
    private static func entries(in group: Any) -> [[String: Any]] {
        if let list = group as? [[String: Any]] { return list }
        if let single = group as? [String: Any] {
            if single["sessionIds"] != nil { return [single] }
            return single.values.flatMap { entries(in: $0) }
        }
        return []
    }
}

/// Loggers so failures land in Console without a debugger attached.
public enum Log {
    public static let store = Logger(subsystem: "dev.openchamber.mini-status", category: "store")
    public static let context = Logger(subsystem: "dev.openchamber.mini-status", category: "context")
    public static let remote = Logger(subsystem: "dev.openchamber.mini-status", category: "remote")
    public static let window = Logger(subsystem: "dev.openchamber.mini-status", category: "window")
}
