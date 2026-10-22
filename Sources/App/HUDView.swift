import SwiftUI

enum Theme {
    static let running = Color(red: 0.36, green: 0.66, blue: 1.0)
    static let attention = Color(red: 1.0, green: 0.72, blue: 0.30)
    static let finished = Color.white.opacity(0.35)
    static let warning = Color(red: 1.0, green: 0.42, blue: 0.36)
    static let secondaryText = Color.white.opacity(0.45)
}

struct HUDView: View {
    @ObservedObject var store: SessionStore
    var onSelect: (ChatSession) -> Void

    private var attentionCount: Int {
        store.rows.filter { $0.phase == .attention }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header

            if store.rows.isEmpty {
                Text(emptyMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 1) {
                    ForEach(store.rows) { row in
                        SessionRowView(row: row, now: store.now)
                            .onTapGesture { onSelect(row.session) }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(.vertical, 8)
        .frame(width: Config.windowWidth, alignment: .leading)
    }

    private var emptyMessage: String {
        if store.status == .databaseUnavailable { return "waiting for OpenChamber" }
        return store.onlyActive ? "no active chats" : "no chats yet"
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("OPENCHAMBER")
                .font(.system(size: 9, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(.white.opacity(0.45))
            Spacer()
            if attentionCount > 0 {
                Text("\(attentionCount) need you")
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.attention)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(Theme.attention.opacity(0.16)))
            }
        }
        .padding(.horizontal, 9)
    }
}

struct SessionRowView: View {
    let row: Row
    let now: Int64

    @State private var pulse = false
    @State private var hovering = false

    private var dot: Color {
        switch row.phase {
        case .attention: return Theme.attention
        case .running: return Theme.running
        case .done: return Theme.finished
        }
    }

    private var timing: String {
        switch row.phase {
        case .running:
            // A running row counts the current turn, not the age of the whole chat.
            let start = row.session.lastUserMessageAt ?? row.session.createdAt
            return Format.duration(now - start)
        case .attention, .done:
            let reference = row.session.idleAt ?? row.session.updatedAt
            return Format.duration(now - reference) + " ago"
        }
    }

    private var contextFraction: Double? { row.session.context?.fraction }

    private var contextColor: Color {
        guard let fraction = contextFraction else { return Theme.secondaryText }
        return fraction >= Config.compactionWarning ? Theme.warning : .white.opacity(0.55)
    }

    private var barColor: Color {
        guard let fraction = contextFraction else { return .clear }
        return fraction >= Config.compactionWarning ? Theme.warning.opacity(0.9) : dot.opacity(0.55)
    }

    private var background: Color {
        switch row.phase {
        case .attention: return Theme.attention.opacity(0.10)
        case .running: return .clear
        case .done: return .white.opacity(hovering ? 0.10 : 0.0)
        }
    }

    /// The badge row stays still; only the dot, clock and context bar breathe.
    private var pulseOpacity: Double {
        row.phase == .attention && pulse ? 0.35 : 1.0
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            statusDot
            details
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(background))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onAppear(perform: startPulseIfNeeded)
    }

    private var statusDot: some View {
        Circle()
            .fill(dot)
            .frame(width: 7, height: 7)
            .background(
                Circle()
                    .fill(dot.opacity(0.30))
                    .frame(width: 13, height: 13)
                    .scaleEffect(row.phase == .attention && pulse ? 1.45 : 1.0)
                    .opacity(row.phase == .attention ? (pulse ? 0.95 : 0.25) : 0)
                    .allowsHitTesting(false)
            )
            .padding(.top, 5)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(row.session.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(row.phase == .done ? 0.75 : 0.95))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Text(Format.money(row.session.cost))
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(row.session.cost > 0 ? 0.85 : 0.4))
            }
            HStack(spacing: 5) {
                Text(row.session.project)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("·")
                Text(Format.context(row.session.context, fallbackTokens: row.session.tokens))
                    .monospacedDigit()
                    .foregroundStyle(contextColor)
                Text("·")
                Text(timing)
                    .monospacedDigit()
                    .foregroundStyle(row.phase == .running ? Theme.running : Theme.secondaryText)
                    .opacity(pulseOpacity)
            }
            .font(.system(size: 10, design: .rounded))
            .foregroundStyle(Theme.secondaryText)

            contextBar
        }
    }

    private var contextBar: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(.white.opacity(0.07))
            if let fraction = contextFraction {
                GeometryReader { geometry in
                    Capsule()
                        .fill(barColor)
                        .frame(width: max(3, geometry.size.width * fraction))
                }
            }
        }
        .frame(height: 2.5)
        .padding(.top, 2)
        .opacity(pulseOpacity)
    }

    private func startPulseIfNeeded() {
        guard row.phase == .attention else { return }
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
            pulse = true
        }
    }
}
