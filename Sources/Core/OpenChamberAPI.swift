import Foundation

/// What OpenChamber's own event watcher says about a chat, which is the same state
/// its sidebar draws from.
public struct RemoteSession: Equatable {
    /// A permission request, question or form is waiting for an answer.
    public let blocked: Bool
    public let idle: Bool
    /// When the status last changed, used as the stamp a click acknowledges.
    public let stamp: Int64

    public init(blocked: Bool, idle: Bool, stamp: Int64) {
        self.blocked = blocked
        self.idle = idle
        self.stamp = stamp
    }
}

/// OpenChamber serves its session state on localhost, guarded by the client token
/// it writes into settings.json next to the port it picked.
public enum OpenChamberEndpoints {
    public static func connection(fromSettings data: Data) -> (url: URL, token: String)? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let port = root["desktopLocalPort"] as? NSNumber,
              let token = root["desktopLocalClientToken"] as? String,
              !token.isEmpty,
              let url = URL(string: "http://127.0.0.1:\(port.intValue)/api/sessions/status")
        else { return nil }
        return (url, token)
    }

    /// Background shells belong to a session through the metadata its creator attached.
    /// OpenChamber draws its blue terminal icon from exactly this list.
    public static func shellSessions(fromJSON data: Data) -> Set<String> {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let shells = root["data"] as? [[String: Any]]
        else { return [] }
        var result: Set<String> = []
        for shell in shells {
            guard (shell["status"] as? String) == "running",
                  let metadata = shell["metadata"] as? [String: Any],
                  let id = (metadata["sessionID"] as? String) ?? (metadata["sessionId"] as? String)
            else { continue }
            result.insert(id)
        }
        return result
    }

    public static func sessions(fromJSON data: Data) -> [String: RemoteSession] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sessions = root["sessions"] as? [String: Any]
        else { return [:] }
        // Pending permissions, questions and forms are the only real "needs you" signal.
        var blocked: Set<String> = []
        if let pending = root["pending"] as? [String: Any] {
            for (id, raw) in pending {
                guard let entry = raw as? [String: Any] else { continue }
                let waiting = ["permissions", "forms", "pages"].contains { key in
                    (entry[key] as? [Any])?.isEmpty == false
                }
                if waiting { blocked.insert(id) }
            }
        }
        var result: [String: RemoteSession] = [:]
        for (id, raw) in sessions {
            guard let value = raw as? [String: Any] else { continue }
            let status = value["status"] as? String ?? "idle"
            let stamp = (value["lastUpdateAt"] as? NSNumber)?.int64Value ?? 0
            result[id] = RemoteSession(
                blocked: blocked.contains(id),
                idle: status == "idle",
                stamp: stamp
            )
        }
        return result
    }
}

/// Polls OpenChamber on the main run loop, backing off when it is closed or refuses
/// the token so the HUD falls back to the database rules instead of waiting forever.
public final class RemoteStateClient {
    private let settingsPath: String
    private let interval: TimeInterval
    private let retryInterval: TimeInterval

    private var timer: Timer?
    private var inFlight = false
    private var failures = 0
    private var lastAttempt = Date.distantPast
    private var onUpdate: (([String: RemoteSession]) -> Void)?

    public init(
        settingsPath: String = Config.settingsPath,
        interval: TimeInterval = Config.refreshInterval,
        retryInterval: TimeInterval = Config.serverRetryInterval
    ) {
        self.settingsPath = settingsPath
        self.interval = interval
        self.retryInterval = retryInterval
    }

    public func start(_ update: @escaping ([String: RemoteSession]) -> Void) {
        onUpdate = update
        poll()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        onUpdate = nil
    }

    private func poll() {
        guard !inFlight else { return }
        if failures > 0, Date().timeIntervalSince(lastAttempt) < retryInterval { return }
        guard let data = FileManager.default.contents(atPath: settingsPath),
              let connection = OpenChamberEndpoints.connection(fromSettings: data)
        else {
            publish([:])
            return
        }

        inFlight = true
        lastAttempt = Date()
        var request = URLRequest(url: connection.url)
        request.timeoutInterval = 2
        request.setValue("Bearer \(connection.token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight = false
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                if let error { Log.remote.error("session state failed: \(error.localizedDescription, privacy: .public)") }
                if code == 200, let data {
                    self.failures = 0
                    let states = OpenChamberEndpoints.sessions(fromJSON: data)
                    Log.remote.debug("session state: \(states.count, privacy: .public) chats")
                    self.onUpdate?(states)
                } else {
                    self.failures += 1
                    Log.remote.error("session state failed: http \(code, privacy: .public)")
                    if self.failures >= 3 { self.onUpdate?([:]) }
                }
            }
        }.resume()
    }

    private func publish(_ states: [String: RemoteSession]) {
        failures = 0
        onUpdate?(states)
    }
}
