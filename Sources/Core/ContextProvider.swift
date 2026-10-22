import Foundation
import os

/// Context window usage comes from the opencode server, not the database: the session
/// rows only keep lifetime totals, while the server knows how large each request was.
public final class ContextProvider {
    /// Updated on the main queue, read by the store when it builds rows.
    public private(set) var usage: [String: ContextUsage] = [:]
    /// Sessions with a background shell still running, which OpenChamber marks blue too.
    public private(set) var runningShellSessions: Set<String> = []
    /// Active sessions and pending requests read straight from the opencode server, used
    /// only while OpenChamber's desktop API is unreachable.
    public private(set) var fallbackStates: [String: RemoteSession] = [:]

    private let queue = DispatchQueue(label: "dev.openchamber.mini-status.context", qos: .utility)
    private let session: URLSession
    private let serversDirectory: String
    private let logger = Log.context

    private var base: URL?
    private var password: String?
    private var limits: [String: Int64] = [:]
    private var modelsLoadedAt: Date?
    private var lastServerAttempt: Date?
    private var targets: [(id: String, model: String)] = []
    private var directories: [String] = []
    private var fallbackEnabled = false
    private var timer: Timer?

    public init(serversDirectory: String = Config.managedServersDirectory) {
        self.serversDirectory = serversDirectory
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 4
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    deinit {
        timer?.invalidate()
        session.invalidateAndCancel()
    }

    public func start() {
        let timer = Timer(timeInterval: Config.contextInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    public func setTargets(_ targets: [(id: String, model: String)]) {
        queue.async { self.targets = targets }
    }

    /// Directories to ask for background shells; the server scopes its shell list by location.
    public func setDirectories(_ directories: [String]) {
        queue.async {
            guard self.directories != directories else { return }
            self.directories = directories
            self.tick()
        }
    }

    /// Turns the opencode-server fallback on or off as OpenChamber's own API comes and goes.
    public func setFallbackEnabled(_ enabled: Bool) {
        queue.async {
            guard self.fallbackEnabled != enabled else { return }
            self.fallbackEnabled = enabled
            if enabled {
                self.tick()
            } else {
                self.publishFallback([:])
            }
        }
    }

    // MARK: ticks

    private func tick() {
        queue.async {
            if self.base == nil || self.password == nil {
                let retryDue = self.lastServerAttempt.map {
                    Date().timeIntervalSince($0) > Config.serverRetryInterval
                } ?? true
                guard retryDue else { return }
                self.lastServerAttempt = Date()
                self.discover()
            }
            guard let base = self.base, let password = self.password else { return }

            let modelsStale = self.modelsLoadedAt.map {
                Date().timeIntervalSince($0) > Config.modelCacheTTL
            } ?? true
            if modelsStale {
                self.loadModels(base: base, password: password)
            }

            for target in self.targets.prefix(Config.contextTargetLimit) {
                self.probe(target, base: base, password: password)
            }
            self.loadShells(base: base, password: password)
            if self.fallbackEnabled {
                self.loadFallback(base: base, password: password)
            }
        }
    }

    // MARK: server discovery

    /// OpenChamber writes one JSON file per managed opencode server: pid, port, binary.
    private func discover() {
        base = nil
        password = nil
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: serversDirectory) else {
            return
        }
        for file in files.sorted() where file.hasSuffix(".json") {
            let path = serversDirectory + "/" + file
            guard let data = FileManager.default.contents(atPath: path),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let pid = object["pid"] as? Int,
                  let port = object["port"] as? Int,
                  kill(Int32(pid), 0) == 0,
                  let url = URL(string: "http://127.0.0.1:\(port)"),
                  let secret = serverPassword(pid: Int32(pid))
            else { continue }
            base = url
            password = secret
            logger.debug("context server on port \(port, privacy: .public)")
            return
        }
    }

    /// The managed server is handed its password in the environment it was started with.
    private func serverPassword(pid: Int32) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["eww", "-p", "\(pid)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            logger.info("cannot read server environment: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8),
              let range = text.range(of: "OPENCODE_SERVER_PASSWORD=")
        else { return nil }
        return String(text[range.upperBound...].prefix { !$0.isWhitespace })
    }

    // MARK: requests

    private func get(_ path: String, base: URL, password: String) -> Any? {
        guard let payload = getData(path, base: base, password: password) else { return nil }
        return try? JSONSerialization.jsonObject(with: payload)
    }

    private func getData(_ path: String, base: URL, password: String) -> Data? {
        guard let url = URL(string: path, relativeTo: base) else { return nil }
        var request = URLRequest(url: url)
        let credentials = Data("opencode:\(password)".utf8).base64EncodedString()
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")

        var payload: Data?
        var status = 0
        let semaphore = DispatchSemaphore(value: 0)
        session.dataTask(with: request) { data, response, _ in
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
            payload = data
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 5)

        guard status == 200, let payload else {
            if status == 401 { logger.info("context server rejected the password") }
            return nil
        }
        return payload
    }

    private func loadModels(base: URL, password: String) {
        guard let object = get("/api/model", base: base, password: password) as? [String: Any],
              let models = object["data"] as? [[String: Any]]
        else { return }

        var limits: [String: Int64] = [:]
        for model in models {
            guard let provider = model["providerID"] as? String,
                  let id = (model["modelID"] as? String) ?? (model["id"] as? String),
                  let limit = model["limit"] as? [String: Any],
                  let context = limit["context"] as? Int
            else { continue }
            limits["\(provider)/\(id)"] = Int64(context)
        }
        self.limits = limits
        modelsLoadedAt = Date()
        logger.debug("cached \(limits.count, privacy: .public) model windows")
    }

    /// A shell started in the background outlives the turn that launched it, so the chat
    /// still counts as active after its status goes idle.
    private func loadShells(base: URL, password: String) {
        var sessions: Set<String> = []
        for directory in directories.prefix(Config.shellDirectoryLimit) {
            guard let path = locationPath("/api/shell", directory),
                  let data = getData(path, base: base, password: password)
            else { continue }
            sessions.formUnion(OpenChamberEndpoints.shellSessions(fromJSON: data))
        }
        DispatchQueue.main.async {
            if self.runningShellSessions != sessions {
                self.runningShellSessions = sessions
            }
        }
    }

    /// OpenChamber's desktop API bundles active sessions and pending requests. When it is
    /// off, the opencode server still knows both, one directory at a time.
    private func loadFallback(base: URL, password: String) {
        var states: [String: RemoteSession] = [:]
        if let data = getData("/api/session/active", base: base, password: password) {
            for id in OpenChamberEndpoints.activeSessions(fromJSON: data) {
                states[id] = RemoteSession(blocked: false, idle: false, stamp: 0)
            }
        }

        var blocked: Set<String> = []
        for directory in directories.prefix(Config.fallbackDirectoryLimit) {
            for endpoint in ["/api/permission/request", "/api/form"] {
                guard let path = locationPath(endpoint, directory),
                      let data = getData(path, base: base, password: password)
                else { continue }
                blocked.formUnion(OpenChamberEndpoints.requestSessionIDs(fromJSON: data))
            }
        }
        for id in blocked {
            let active = states[id]
            states[id] = RemoteSession(blocked: true, idle: active?.idle ?? true, stamp: active?.stamp ?? 0)
        }
        logger.debug("fallback states: \(states.count, privacy: .public) sessions, \(blocked.count, privacy: .public) waiting")
        publishFallback(states)
    }

    private func publishFallback(_ states: [String: RemoteSession]) {
        DispatchQueue.main.async {
            if self.fallbackStates != states {
                self.fallbackStates = states
            }
        }
    }

    private func locationPath(_ endpoint: String, _ directory: String) -> String? {
        var components = URLComponents()
        components.path = endpoint
        components.queryItems = [URLQueryItem(name: "location[directory]", value: directory)]
        return components.string
    }

    private func probe(_ target: (id: String, model: String), base: URL, password: String) {        // The newest message can still be streaming, so ask for a few and take the last counted one.
        guard let object = get("/api/session/\(target.id)/message?limit=3", base: base, password: password)
            as? [String: Any],
              let messages = object["data"] as? [[String: Any]]
        else { return }

        for message in messages.reversed() {
            guard let used = Self.tokensUsed(message["tokens"] as? [String: Any]), used > 0 else { continue }
            let limit = limits[target.model]
            DispatchQueue.main.async {
                let next = ContextUsage(used: used, limit: limit)
                if self.usage[target.id] != next {
                    self.usage[target.id] = next
                }
            }
            return
        }
    }

    /// What the model had in its window on that request.
    public static func tokensUsed(_ tokens: [String: Any]?) -> Int64? {
        guard let tokens else { return nil }
        let input = tokens["input"] as? Int ?? 0
        let output = tokens["output"] as? Int ?? 0
        let reasoning = tokens["reasoning"] as? Int ?? 0
        let cache = tokens["cache"] as? [String: Any]
        let read = cache?["read"] as? Int ?? 0
        let write = cache?["write"] as? Int ?? 0
        let total = input + output + reasoning + read + write
        return total > 0 ? Int64(total) : nil
    }
}
