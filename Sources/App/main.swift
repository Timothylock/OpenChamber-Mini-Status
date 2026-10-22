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
      mini-status --snapshot-settings PATH
                                   render the settings window to a PNG and exit
      mini-status --probe-remote    print OpenChamber session state and exit
      mini-status --probe-shell DIR print sessions with running background shells and exit
      mini-status --help           print this message
    """
}

func renderSnapshot(to path: String) {
    MainActor.assumeIsolated {
        let store = SessionStore()
        store.start()
        // Give the context probe a moment to answer before drawing.
        RunLoop.current.run(until: Date().addingTimeInterval(6))
        store.refresh()

        let view = HUDView(store: store, onSelect: { _ in })
            .background(Color.black.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: Config.cornerRadius, style: .continuous))

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            FileHandle.standardError.write(Data("could not render the snapshot\n".utf8))
            exit(1)
        }
        do {
            try png.write(to: URL(fileURLWithPath: path))
            print("wrote \(path)")
        } catch {
            FileHandle.standardError.write(Data("could not write \(path): \(error)\n".utf8))
            exit(1)
        }
        store.stop()
    }
    exit(0)
}

func renderSettingsSnapshot(to path: String) {
    MainActor.assumeIsolated {
        let previewDefaults = UserDefaults(suiteName: "dev.openchamber.mini-status.preview") ?? .standard
        let preferences = Preferences(defaults: previewDefaults)
        let view = SettingsView(preferences: preferences, installed: true, onResetPosition: {})
            .background(Color(nsColor: .windowBackgroundColor))

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            FileHandle.standardError.write(Data("could not render the settings snapshot\n".utf8))
            exit(1)
        }
        do {
            try png.write(to: URL(fileURLWithPath: path))
            print("wrote \(path)")
        } catch {
            FileHandle.standardError.write(Data("could not write \(path): \(error)\n".utf8))
            exit(1)
        }
    }
    exit(0)
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
