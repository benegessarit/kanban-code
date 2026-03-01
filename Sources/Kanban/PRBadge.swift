import SwiftUI
import KanbanCore

/// Displays a PR status badge with icon, color, and label.
struct PRBadge: View {
    let status: PRStatus
    let prNumber: Int

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: iconName)
                .font(.caption2)
            Text(verbatim: "#\(prNumber)")
                .font(.caption2)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Capsule().fill(badgeColor.opacity(0.15)))
        .foregroundStyle(badgeColor)
    }

    private var iconName: String {
        switch status {
        case .failing: "xmark.circle.fill"
        case .unresolved: "bubble.left.and.exclamationmark.bubble.right"
        case .changesRequested: "arrow.uturn.backward.circle"
        case .reviewNeeded: "eye"
        case .pendingCI: "clock"
        case .approved: "checkmark.circle.fill"
        case .merged: "arrow.triangle.merge"
        case .closed: "xmark"
        }
    }

    private var badgeColor: Color {
        switch status {
        case .failing: .red
        case .unresolved: .orange
        case .changesRequested: .orange
        case .reviewNeeded: .blue
        case .pendingCI: .yellow
        case .approved: .green
        case .merged: .purple
        case .closed: .secondary
        }
    }
}
