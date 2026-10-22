import AppKit
import SwiftUI

/// Three switches, each explained in one line, plus the escape hatch for a lost window.
struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    var installed: Bool = LoginItem.isInstallLocation
    var onResetPosition: () -> Void
    /// Documentation renders draw the checkbox glyph themselves, because ImageRenderer
    /// captures the AppKit checkbox as a placeholder.
    var renderControls = false

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            preference(
                "Start with Mac",
                "Opens automatically when you log in.",
                isOn: $preferences.startAtLogin,
                disabled: !installed,
                note: installed ? nil : "Available once the app is in Applications."
            )
            preference(
                "Fade When Hover",
                "Drops to 55% opacity while the pointer is over the widget.",
                isOn: $preferences.fadeOnHover
            )
            preference(
                "Only Show Running / Waiting Chats",
                "Hides grey rows: chats that finished and are not waiting on you.",
                isOn: $preferences.onlyActive
            )
            preference(
                "Hide System Tray Icon",
                "The menu bar icon goes away. Reopen the app from Applications or Spotlight to get back to this window.",
                isOn: $preferences.hideTrayIcon
            )

            Divider()

            HStack {
                Button("Reset Position", action: onResetPosition)
                Spacer()
                Text("Version \(version)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(width: 360)
    }

    private func preference(
        _ title: String,
        _ caption: String,
        isOn: Binding<Bool>,
        disabled: Bool = false,
        note: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if renderControls {
                HStack(spacing: 6) {
                    Image(systemName: isOn.wrappedValue ? "checkmark.square.fill" : "square")
                        .font(.system(size: 13))
                        .foregroundStyle(isOn.wrappedValue ? Color.accentColor : Color.secondary)
                    Text(title)
                        .font(.system(size: 13))
                }
            } else {
                Toggle(title, isOn: isOn)
                    .toggleStyle(.checkbox)
                    .disabled(disabled)
                    .accessibilityHint(caption)
            }
            Text(caption)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 18)
                .accessibilityHidden(true)
            if let note {
                Text(note)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.orange)
                    .padding(.leading, 18)
            }
        }
    }
}

/// A plain titled window, opened from the menu bar or by reopening the app.
final class SettingsWindowController: NSWindowController {
    init(
        preferences: Preferences,
        installed: Bool = LoginItem.isInstallLocation,
        onResetPosition: @escaping () -> Void
    ) {
        let root = SettingsView(
            preferences: preferences,
            installed: installed,
            onResetPosition: onResetPosition
        )
        let hosting = NSHostingController(rootView: root)
        hosting.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: hosting)
        window.title = "Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.setContentSize(hosting.view.fittingSize)
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
