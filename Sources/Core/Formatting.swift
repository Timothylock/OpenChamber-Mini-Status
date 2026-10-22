import Foundation

/// Small, allocation-light formatters. Pure functions so they are cheap to test.
public enum Format {
    public static func tokens(_ value: Int64) -> String {
        switch value {
        case 1_000_000...:
            return String(format: "%.1fM tok", Double(value) / 1_000_000)
        case 1_000...:
            return String(format: "%.0fk tok", Double(value) / 1_000)
        default:
            return "\(value) tok"
        }
    }

    public static func money(_ value: Double) -> String {
        if value <= 0 { return "free" }
        return String(format: "$%.2f", value)
    }

    /// Compact elapsed time: 42s, 13m05s, 2h07m.
    public static func duration(_ milliseconds: Int64) -> String {
        let seconds = max(0, milliseconds / 1000)
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 {
            return "\(seconds / 60)m" + String(format: "%02d", seconds % 60) + "s"
        }
        return "\(seconds / 3600)h" + String(format: "%02d", (seconds % 3600) / 60) + "m"
    }

    /// Context usage for the row: "68% ctx", or a token count when the window is unknown.
    public static func context(_ usage: ContextUsage?, fallbackTokens: Int64) -> String {
        guard let usage else { return tokens(fallbackTokens) }
        guard let fraction = usage.fraction else { return tokens(usage.used) }
        return "\(Int((fraction * 100).rounded()))% ctx"
    }

    /// OpenChamber gives chat-scratch sessions a directory of their own, which says nothing.
    /// Those rows show a linked ticket key instead, when the session metadata carries one.
    public static func projectLabel(directory: String, metadata: String) -> String {
        let base = (directory as NSString).lastPathComponent
        guard base.hasPrefix("session-") else { return base.isEmpty ? "chat" : base }
        guard let data = metadata.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let openchamber = root["openchamber"] as? [String: Any],
              let issues = openchamber["linked_issues"] as? [[String: Any]],
              let identifier = issues.first?["identifier"] as? String,
              identifier.range(
                of: "^([A-Z][A-Z0-9]*-[0-9]+|![0-9]+|#[0-9]+)$",
                options: .regularExpression
              ) != nil
        else { return "chat" }
        return identifier
    }

    /// OpenChamber keeps its In work flag in session metadata, not in a column.
    public static func workState(_ metadata: String) -> String? {
        guard let data = metadata.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let openchamber = root["openchamber"] as? [String: Any],
              let work = openchamber["work"] as? [String: Any],
              let state = work["state"] as? String
        else { return nil }
        return state
    }

    /// "provider/model", the key the model catalog uses.
    public static func modelKey(_ json: String) -> String {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let provider = object["providerID"] as? String,
              let id = object["id"] as? String
        else { return "" }
        return "\(provider)/\(id)"
    }
}

/// Which rows the widget shows: waiting first, then running, then most recent, cut short.
public enum Selection {
    /// Archived chats stay out of the list only while they are finished; resuming one
    /// marks it In work again, and a running chat must always show.
    public static func visible(archived: Bool, phase: Phase, onlyActive: Bool) -> Bool {
        guard phase == .done else { return true }
        return !archived && !onlyActive
    }

    public static func rows(
        attention: [Row],
        running: [Row],
        done: [Row],
        limit: Int = Config.rowLimit
    ) -> [Row] {
        Array((attention + running + done).prefix(max(0, limit)))
    }
}
