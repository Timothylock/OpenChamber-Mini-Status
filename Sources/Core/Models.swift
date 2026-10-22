import Foundation

/// One chat as the widget needs it, assembled from the session database.
public struct ChatSession: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let project: String
    public let cost: Double
    public let tokensIn: Int64
    public let tokensOut: Int64
    public let createdAt: Int64
    public let updatedAt: Int64
    public let idleAt: Int64?
    public let lastMessageType: String?
    /// "provider/model", used to look up the context window.
    public let model: String
    /// OpenChamber's work state: "open" means it sits in its In work list.
    public let workState: String?
    /// When the current turn started, which is what a running clock counts from.
    public let lastUserMessageAt: Int64?
    public let context: ContextUsage?

    public init(
        id: String,
        title: String,
        project: String,
        cost: Double,
        tokensIn: Int64,
        tokensOut: Int64,
        createdAt: Int64,
        updatedAt: Int64,
        idleAt: Int64?,
        lastMessageType: String?,
        model: String,
        workState: String?,
        lastUserMessageAt: Int64?,
        context: ContextUsage?
    ) {
        self.id = id
        self.title = title
        self.project = project
        self.cost = cost
        self.tokensIn = tokensIn
        self.tokensOut = tokensOut
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.idleAt = idleAt
        self.lastMessageType = lastMessageType
        self.model = model
        self.workState = workState
        self.lastUserMessageAt = lastUserMessageAt
        self.context = context
    }

    public var tokens: Int64 { tokensIn + tokensOut }
}

/// Where a chat sits in the widget, which decides its order, colour and whether it pulses.
public enum Phase: Int, Comparable {
    case attention = 0
    case running = 1
    case done = 2

    public static func < (lhs: Phase, rhs: Phase) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct Row: Identifiable, Equatable {
    public let session: ChatSession
    public let phase: Phase

    public var id: String { session.id }

    public init(session: ChatSession, phase: Phase) {
        self.session = session
        self.phase = phase
    }
}

/// Tokens in play on a chat's last completed request, against the model's window.
public struct ContextUsage: Equatable {
    public let used: Int64
    public let limit: Int64?

    public init(used: Int64, limit: Int64?) {
        self.used = used
        self.limit = limit
    }

    public var fraction: Double? {
        guard let limit, limit > 0 else { return nil }
        return min(1, max(0, Double(used) / Double(limit)))
    }
}
