import AppKit
import SwiftUI

/// OpenChamber Mini Status: a floating four-row status widget for OpenChamber chats.
/// Run with no arguments for the widget, `--snapshot <path>` to render it to a PNG,
/// which is handy for checking the design without a screen recording permission.
let arguments = CommandLine.arguments

func usage() -> String {
    """
    OpenChamber Mini Status

    Usage:
      mini-status                  run the floating widget
      mini-status --snapshot PATH  render the widget to a PNG and exit
      mini-status --snapshot-demo PATH
                                   render the widget with example chats to a PNG and exit
      mini-status --snapshot-settings PATH
                                   render the settings window to a PNG and exit
      mini-status --probe-remote    print OpenChamber session state and exit
      mini-status --probe-shell DIR print sessions with running background shells and exit
      mini-status --help           print this message
    """
}

@MainActor
func writeSnapshot<Content: View>(_ view: Content, to path: String) -> Bool {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:])
    else {
        FileHandle.standardError.write(Data("could not render the snapshot\n".utf8))
        return false
    }
    do {
        try png.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
        return true
    } catch {
        FileHandle.standardError.write(Data("could not write \(path): \(error)\n".utf8))
        return false
    }
}

func widgetImage(for store: SessionStore) -> some View {
    HUDView(store: store, onSelect: { _ in })
        .background(Color.black.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: Config.cornerRadius, style: .continuous))
}

func renderSnapshot(to path: String) {
    MainActor.assumeIsolated {
        let store = SessionStore()
        store.start()
        // Give the context probe a moment to answer before drawing.
        RunLoop.current.run(until: Date().addingTimeInterval(6))
        store.refresh()

        let wrote = writeSnapshot(widgetImage(for: store), to: path)
        store.stop()
        exit(wrote ? 0 : 1)
    }
}

/// Renders the widget with invented chats, so the README never shows real projects.
func renderDemoSnapshot(to path: String) {
    MainActor.assumeIsolated {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let minute: Int64 = 60 * 1000

        func chat(
            _ id: String,
            _ title: String,
            _ project: String,
            cost: Double,
            used: Int64,
            age: Int64,
            idle: Int64?
        ) -> ChatSession {
            ChatSession(
                id: id,
                title: title,
                project: project,
                cost: cost,
                tokensIn: used,
                tokensOut: 2_400,
                createdAt: now - 4 * 60 * minute,
                updatedAt: now - age,
                idleAt: idle.map { now - $0 },
                lastMessageType: "assistant",
                model: "example/model",
                workState: "open",
                lastUserMessageAt: now - age,
                context: ContextUsage(used: used, limit: 200_000)
            )
        }

        let rows = [
            Row(session: chat("ses_demo_sync", "Refactor retry handling in the sync job",
                              "sync-service", cost: 0.37, used: 116_000,
                              age: 3 * minute, idle: 3 * minute), phase: .attention),
            Row(session: chat("ses_demo_notes", "Draft release notes for 2.4",
                              "website", cost: 0.06, used: 62_000,
                              age: 19 * minute, idle: 19 * minute), phase: .attention),
            Row(session: chat("ses_demo_login", "Fix flaky login test",
                              "web-app", cost: 0.94, used: 144_000,
                              age: 6 * minute + 12_000, idle: nil), phase: .running),
            Row(session: chat("ses_demo_export", "Add CSV export to reports",
                              "data-service", cost: 0.21, used: 90_000,
                              age: 48_000, idle: nil), phase: .running),
        ]

        let store = SessionStore.preview(rows: rows, now: now, onlyActive: true)
        exit(writeSnapshot(widgetImage(for: store), to: path) ? 0 : 1)
    }
}


func renderSettingsSnapshot(to path: String) {
    MainActor.assumeIsolated {
        let suite = "dev.openchamber.mini-status.preview"
        let previewDefaults = UserDefaults(suiteName: suite) ?? .standard
        // Renders always show the shipped defaults, not values left by an earlier run.
        previewDefaults.removePersistentDomain(forName: suite)
        let preferences = Preferences(defaults: previewDefaults)
        let view = SettingsView(preferences: preferences, installed: true, onResetPosition: {}, renderControls: true)
            .background(Color(nsColor: .windowBackgroundColor))

        exit(writeSnapshot(view, to: path) ? 0 : 1)
    }
}

func probeRemote() {
    guard let data = FileManager.default.contents(atPath: Config.settingsPath) else {
        print("no settings at \(Config.settingsPath)")
        exit(1)
    }
    guard let connection = OpenChamberEndpoints.connection(fromSettings: data) else {
        print("no connection in settings")
        exit(1)
    }
    print("url: \(connection.url.absoluteString)")
    var request = URLRequest(url: connection.url)
    request.timeoutInterval = 5
    request.setValue("Bearer \(connection.token)", forHTTPHeaderField: "Authorization")
    let semaphore = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: request) { data, response, error in
        print("error: \(error.map { String(describing: $0) } ?? "none")")
        print("code: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        if let data { print("sessions: \(OpenChamberEndpoints.sessions(fromJSON: data).count)") }
        semaphore.signal()
    }.resume()
    semaphore.wait()
    exit(0)
}

if arguments.contains("--probe-remote") { probeRemote() }

if let index = arguments.firstIndex(of: "--probe-shell") {
    guard arguments.count > index + 1 else {
        FileHandle.standardError.write(Data("--probe-shell needs a directory\n".utf8))
        exit(2)
    }
    let directory = arguments[index + 1]
    let provider = ContextProvider()
    provider.start()
    provider.setDirectories([directory])
    RunLoop.current.run(until: Date().addingTimeInterval(3))
    print("shell sessions: \(provider.runningShellSessions.sorted())")
    provider.stop()
    exit(0)
}

if arguments.contains("--help") || arguments.contains("-h") {
    print(usage())
    exit(0)
}

if let index = arguments.firstIndex(of: "--snapshot-settings") {
    guard arguments.count > index + 1 else {
        FileHandle.standardError.write(Data("--snapshot-settings needs a path\n".utf8))
        exit(2)
    }
    renderSettingsSnapshot(to: arguments[index + 1])
}

if let index = arguments.firstIndex(of: "--snapshot-demo") {
    guard arguments.count > index + 1 else {
        FileHandle.standardError.write(Data("--snapshot-demo needs a path\n".utf8))
        exit(2)
    }
    renderDemoSnapshot(to: arguments[index + 1])
}

if let index = arguments.firstIndex(of: "--snapshot") {
    guard arguments.count > index + 1 else {
        FileHandle.standardError.write(Data("--snapshot needs a path\n".utf8))
        exit(2)
    }
    renderSnapshot(to: arguments[index + 1])
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
