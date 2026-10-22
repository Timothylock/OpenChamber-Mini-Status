import Foundation

/// Tiny harness: the toolchain here has no SwiftPM, so tests are a plain executable.
var failures = 0

func check(_ condition: Bool, _ label: String) {
    if condition {
        print("  ok   \(label)")
    } else {
        print("  FAIL \(label)")
        failures += 1
    }
}

func equal<T: Equatable>(_ value: T, _ expected: T, _ label: String) {
    check(value == expected, "\(label) (got \(value), expected \(expected))")
}

// MARK: formatting

equal(Format.tokens(999), "999 tok", "tokens under a thousand")
equal(Format.tokens(82_400), "82k tok", "tokens in thousands")
equal(Format.tokens(1_240_000), "1.2M tok", "tokens in millions")

equal(Format.money(0), "free", "free model")
equal(Format.money(0.1329), "$0.13", "cost rounded")
equal(Format.money(12.5), "$12.50", "cost over a dollar")

equal(Format.duration(0), "0s", "zero seconds")
equal(Format.duration(59_000), "59s", "under a minute")
equal(Format.duration(65_000), "1m05s", "minutes with padding")
equal(Format.duration(3_600_000 + 7 * 60_000), "1h07m", "hours")
equal(Format.duration(-5_000), "0s", "clamps negatives")

equal(
    Format.context(ContextUsage(used: 136_000, limit: 200_000), fallbackTokens: 9),
    "68% ctx",
    "context percentage"
)
equal(
    Format.context(ContextUsage(used: 9_000, limit: nil), fallbackTokens: 1),
    "9k tok",
    "context without a window"
)
equal(Format.context(nil, fallbackTokens: 1_500_000), "1.5M tok", "context unknown")

equal(
    Format.modelKey(#"{"id":"gpt-6-luna","providerID":"github-copilot"}"#),
    "github-copilot/gpt-6-luna",
    "model key"
)
equal(Format.modelKey("not json"), "", "model key from junk")

equal(
    Format.projectLabel(directory: "/Users/x/go/src/repo", metadata: ""),
    "repo",
    "project from a repository directory"
)
equal(
    Format.projectLabel(directory: "/Users/x/.config/openchamber/chats/2026-10-22/session-abc", metadata: ""),
    "chat",
    "scratch directory falls back to chat"
)
let metadata = #"{"openchamber":{"linked_issues":[{"identifier":"PIEIPE-39534"}]}}"#
equal(
    Format.projectLabel(directory: "/tmp/session-abc", metadata: metadata),
    "PIEIPE-39534",
    "scratch directory uses the linked ticket"
)
let noisyMetadata = #"{"openchamber":{"linked_issues":[{"identifier":"gitlab.ea.com"}]}}"#
equal(
    Format.projectLabel(directory: "/tmp/session-abc", metadata: noisyMetadata),
    "chat",
    "non key-like identifiers are ignored"
)

// MARK: ordering

func row(_ id: String, _ phase: Phase) -> Row {
    Row(
        session: ChatSession(
            id: id,
            title: id,
            project: "p",
            cost: 0,
            tokensIn: 0,
            tokensOut: 0,
            createdAt: 0,
            updatedAt: 0,
            idleAt: nil,
            lastMessageType: "assistant",
            model: "",
            workState: nil,
            lastUserMessageAt: nil,
            context: nil
        ),
        phase: phase
    )
}

let selected = Selection.rows(
    attention: [row("a1", .attention), row("a2", .attention)],
    running: [row("r1", .running)],
    done: [row("d1", .done), row("d2", .done)]
)
equal(selected.map(\.id), ["a1", "a2", "r1", "d1"], "waiting then running then recent, cut to four")
equal(Selection.rows(attention: [], running: [], done: [row("d1", .done)], limit: 0).count, 0, "zero limit")

check(Selection.visible(archived: true, phase: .running, onlyActive: true), "archived chat resumed into work shows")
check(Selection.visible(archived: true, phase: .attention, onlyActive: false), "archived chat that wants you shows")
check(!Selection.visible(archived: true, phase: .done, onlyActive: false), "archived finished chat stays hidden")
check(Selection.visible(archived: false, phase: .done, onlyActive: false), "finished chat shows when the filter is off")
check(!Selection.visible(archived: false, phase: .done, onlyActive: true), "finished chat hides when the filter is on")

// MARK: phases

let minute: Int64 = 60 * 1000
let now: Int64 = 1_800_000_000_000

equal(
    Phases.phase(idleAt: now - minute, lastMessageType: "assistant", updatedAt: now, now: now, ackedIdle: nil),
    .attention,
    "finished turn waits for you"
)
equal(
    Phases.phase(idleAt: now - minute, lastMessageType: "assistant", updatedAt: now, now: now, ackedIdle: now - minute),
    .done,
    "acknowledged turn stops waiting"
)
equal(
    Phases.phase(idleAt: now - minute, lastMessageType: "user", updatedAt: now, now: now, ackedIdle: nil),
    .done,
    "turn the user abandoned does not wait"
)
equal(
    Phases.phase(idleAt: now - 90 * minute, lastMessageType: "assistant", updatedAt: now, now: now, ackedIdle: nil),
    .attention,
    "a finished turn keeps waiting however long it takes"
)
equal(
    Phases.phase(
        idleAt: now - 90 * minute,
        lastMessageType: "assistant",
        updatedAt: now,
        now: now,
        ackedIdle: nil,
        unreadAfter: now - 10 * minute
    ),
    .done,
    "a turn finished before the widget started is not unread"
)
equal(
    Phases.phase(idleAt: nil, lastMessageType: "user", updatedAt: now - 1_000, now: now, ackedIdle: nil),
    .running,
    "recently written session is running"
)
equal(
    Phases.phase(idleAt: nil, lastMessageType: "assistant", updatedAt: now - 10 * minute, now: now, ackedIdle: nil),
    .done,
    "stale session without an idle stamp is done"
)
equal(
    Phases.phase(
        idleAt: now - 10 * minute,
        lastMessageType: "assistant",
        updatedAt: now - 10 * minute,
        now: now,
        ackedIdle: now - 10 * minute,
        workState: "open"
    ),
    .running,
    "In work stays running even when acknowledged"
)
equal(
    Phases.phase(
        idleAt: now - 10 * minute,
        lastMessageType: "assistant",
        updatedAt: now - 10 * minute,
        now: now,
        ackedIdle: nil,
        workState: "done"
    ),
    .attention,
    "a finished In work item that wants you still pulses"
)
equal(
    Phases.phase(
        idleAt: now - 40 * minute,
        lastMessageType: "assistant",
        updatedAt: now - 40 * minute,
        now: now,
        ackedIdle: now - 40 * minute,
        workState: "open"
    ),
    .running,
    "In work forty minutes later still counts as running"
)
equal(
    Phases.phase(
        idleAt: now - 38 * 60 * minute,
        lastMessageType: "assistant",
        updatedAt: now - 38 * 60 * minute,
        now: now,
        ackedIdle: now - 38 * 60 * minute,
        workState: "open"
    ),
    .done,
    "an In work chat left open for days is history"
)
equal(Format.workState(#"{"openchamber":{"work":{"state":"open"}}}"#), "open", "work state from metadata")
equal(Format.workState(#"{"openchamber":{}}"#), nil, "no work state in metadata")

// MARK: OpenChamber API

let settingsJSON = #"{"desktopLocalPort":57123,"desktopLocalClientToken":"oc_client_test"}"#
equal(
    OpenChamberEndpoints.connection(fromSettings: Data(settingsJSON.utf8))?.url.absoluteString,
    "http://127.0.0.1:57123/api/sessions/status",
    "desktop server address comes from settings"
)
equal(
    OpenChamberEndpoints.connection(fromSettings: Data(settingsJSON.utf8))?.token,
    "oc_client_test",
    "desktop server token comes from settings"
)
equal(
    OpenChamberEndpoints.connection(fromSettings: Data(#"{"desktopLocalPort":57123}"#.utf8)) == nil,
    true,
    "no token means no API"
)
let statusJSON = #"""
{"sessions":{"ses_busy":{"status":"busy","lastUpdateAt":123},"ses_idle":{"status":"idle","lastUpdateAt":99},"ses_blocked":{"status":"idle","lastUpdateAt":77}},"pending":{"ses_blocked":{"permissions":[{"id":"p"}],"forms":[],"pages":[]}},"serverTime":1}
"""#
let parsed = OpenChamberEndpoints.sessions(fromJSON: Data(statusJSON.utf8))
equal(parsed["ses_busy"], RemoteSession(blocked: false, idle: false, stamp: 123), "busy session parsed")
equal(parsed["ses_idle"], RemoteSession(blocked: false, idle: true, stamp: 99), "idle session parsed")
equal(parsed["ses_blocked"], RemoteSession(blocked: true, idle: true, stamp: 77), "pending permission marks a chat blocked")
equal(parsed.count, 3, "every session in the payload is kept")
equal(
    OpenChamberEndpoints.sessions(fromJSON: Data(#"{"sessions":{}}"#.utf8)),
    [:],
    "empty session payload"
)
equal(
    Phases.phase(
        idleAt: now - minute,
        lastMessageType: "assistant",
        updatedAt: now,
        now: now,
        ackedIdle: nil,
        remote: RemoteSession(blocked: true, idle: true, stamp: now - minute)
    ),
    .attention,
    "a pending permission waits on you"
)
equal(
    Phases.phase(
        idleAt: nil,
        lastMessageType: "user",
        updatedAt: now,
        now: now,
        ackedIdle: nil,
        remote: RemoteSession(blocked: true, idle: false, stamp: now)
    ),
    .attention,
    "a pending permission outranks busy"
)
equal(
    Phases.phase(
        idleAt: now - minute,
        lastMessageType: "assistant",
        updatedAt: now,
        now: now,
        ackedIdle: nil,
        remote: RemoteSession(blocked: false, idle: true, stamp: now - minute)
    ),
    .attention,
    "OpenChamber idle after a turn stays unread like the green mark"
)
equal(
    Phases.phase(
        idleAt: now - minute,
        lastMessageType: "assistant",
        updatedAt: now,
        now: now,
        ackedIdle: now - minute,
        remote: RemoteSession(blocked: false, idle: true, stamp: now - minute + 500)
    ),
    .done,
    "clicking an unread chat clears it even if the status stamp moved"
)
equal(
    Phases.phase(
        idleAt: now - 90 * minute,
        lastMessageType: "assistant",
        updatedAt: now,
        now: now,
        ackedIdle: nil,
        remote: RemoteSession(blocked: false, idle: true, stamp: now - 90 * minute),
        unreadAfter: now - 10 * minute
    ),
    .done,
    "OpenChamber idle from before launch is not unread"
)
equal(
    Phases.phase(
        idleAt: nil,
        lastMessageType: nil,
        updatedAt: now,
        now: now,
        ackedIdle: nil,
        remote: RemoteSession(blocked: false, idle: false, stamp: now)
    ),
    .running,
    "OpenChamber busy means running"
)

let shellJSON = #"""
{"location":{"directory":"/tmp"},"data":[{"id":"sh_1","status":"running","command":"sleep 500","cwd":"/tmp","shell":"zsh","file":"/tmp/out","metadata":{"sessionID":"ses_shell"},"time":{"started":1}},{"id":"sh_2","status":"exited","command":"ls","cwd":"/tmp","shell":"zsh","file":"/tmp/out2","metadata":{"sessionID":"ses_old"},"time":{"started":1,"completed":2}},{"id":"sh_3","status":"running","command":"make","cwd":"/tmp","shell":"zsh","file":"/tmp/out3","metadata":{},"time":{"started":1}}]}
"""#
equal(
    OpenChamberEndpoints.shellSessions(fromJSON: Data(shellJSON.utf8)),
    ["ses_shell"],
    "only running background shells tied to a session count"
)
equal(
    OpenChamberEndpoints.shellSessions(fromJSON: Data(#"{"location":{},"data":[]}"#.utf8)),
    [],
    "empty shell list"
)
equal(
    Phases.phase(
        idleAt: now - minute,
        lastMessageType: "assistant",
        updatedAt: now,
        now: now,
        ackedIdle: now - minute,
        remote: RemoteSession(blocked: false, idle: true, stamp: now - minute),
        hasShell: true
    ),
    .running,
    "an idle chat with a background shell stays blue like OpenChamber"
)
equal(
    Phases.phase(
        idleAt: now - minute,
        lastMessageType: "assistant",
        updatedAt: now,
        now: now,
        ackedIdle: nil,
        hasShell: true
    ),
    .running,
    "a background shell outranks the finished-turn pulse in fallback"
)
equal(
    Phases.phase(
        idleAt: now - minute,
        lastMessageType: "assistant",
        updatedAt: now,
        now: now,
        ackedIdle: nil,
        remote: RemoteSession(blocked: true, idle: true, stamp: now - minute),
        hasShell: true
    ),
    .attention,
    "a waiting prompt outranks a background shell"
)

// MARK: context tokens

equal(
    ContextProvider.tokensUsed(["input": 593, "output": 188, "reasoning": 126, "cache": ["read": 114_944, "write": 0]]),
    115_851,
    "context counts input, output, reasoning and cache"
)
equal(ContextProvider.tokensUsed(["input": 0, "output": 0]), nil, "no tokens means no measurement")
equal(ContextProvider.tokensUsed(nil), nil, "missing tokens")

// MARK: phase grace

var grace = PhaseGrace()
let base: Int64 = 1_000_000
equal(grace.resolve(sessionID: "a", phase: .running, now: base), .running, "running shows as running")
equal(
    grace.resolve(sessionID: "a", phase: .done, now: base + 2_000),
    .running,
    "a just finished chat keeps its running look"
)
equal(
    grace.resolve(sessionID: "a", phase: .done, now: base + 6_000),
    .done,
    "the look is released after five seconds"
)
var coldGrace = PhaseGrace()
equal(
    coldGrace.resolve(sessionID: "b", phase: .done, now: base),
    .done,
    "no hold without a running turn before it"
)
equal(
    coldGrace.resolve(sessionID: "c", phase: .attention, now: base),
    .attention,
    "needs-you rows are not held"
)

// MARK: archive shapes

let flat = #"{"ses_aaa":1791312127799,"ses_bbb":1791312130275}"#
equal(ArchivedSessions.ids(fromJSON: Data(flat.utf8)), ["ses_aaa", "ses_bbb"], "flat archive store")

let folders = #"""
{"foldersMap":{"__archived__:/repo":[{"name":"x","sessionIds":["ses_ccc"]}]}}
"""#
equal(ArchivedSessions.ids(fromJSON: Data(folders.utf8)), ["ses_ccc"], "folder archive store")
equal(ArchivedSessions.ids(fromJSON: Data("junk".utf8)), [], "unreadable archive")

// MARK: preferences

let suite = "dev.openchamber.mini-status.tests"
let testDefaults = UserDefaults(suiteName: suite)!
testDefaults.removePersistentDomain(forName: suite)

let fresh = Preferences(defaults: testDefaults)
equal(fresh.startAtLogin, true, "starts at login by default")
equal(fresh.fadeOnHover, true, "fades on hover by default")
equal(fresh.hideTrayIcon, false, "keeps the menu bar icon by default")
equal(fresh.onlyActive, false, "shows idle chats by default")

fresh.fadeOnHover = false
fresh.hideTrayIcon = true
fresh.onlyActive = true
let reloaded = Preferences(defaults: testDefaults)
equal(reloaded.fadeOnHover, false, "hover fade survives a relaunch")
equal(reloaded.hideTrayIcon, true, "hidden tray icon survives a relaunch")
equal(reloaded.onlyActive, true, "the active-only filter survives a relaunch")
testDefaults.removePersistentDomain(forName: suite)

// MARK: result

if failures == 0 {
    print("all tests passed")
    exit(0)
} else {
    print("\(failures) test(s) failed")
    exit(1)
}
