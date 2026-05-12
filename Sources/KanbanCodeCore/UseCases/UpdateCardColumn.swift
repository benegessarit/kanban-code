import Foundation

/// Updates a link's column based on current activity state, PR status, and worktree existence.
/// Wraps AssignColumn with persistence via CoordinationStore.
///
/// For local-task cards (cards with `localTaskLink != nil`), formaltask status
/// is the workflow lifecycle authority and decides the column BEFORE any
/// activity/PR inference runs. The runner sidecar status written to
/// `<state_dir>/workers/<runner-agent>.json` (running/blocked/failed/completed)
/// describes the spawned terminal session and is DISPLAY-ONLY — it never
/// shifts a local-task card between workflow columns. See
/// scripts/lib/runner.py for the sidecar shape.
///
/// For non-local cards (GitHub issue, manual, discovered), the existing
/// activity/PR inference runs unchanged.
public enum UpdateCardColumn {

    /// Update a single link's column assignment.
    /// PR state is read directly from `link.prLinks`.
    public static func update(
        link: inout Link,
        activityState: ActivityState?,
        hasWorktree: Bool
    ) {
        let newColumn: KanbanCodeColumn
        if link.localTaskLink != nil, !link.manualOverrides.column,
           let mapped = mapLocalTaskStatus(link.localTaskLink?.status) {
            // Local-task mapping wins over activity/PR inference. Even if both
            // localTaskLink and issueLink are present (a user may manually
            // attach PR metadata to a local-task card), the formaltask status
            // remains workflow-lifecycle authority.
            newColumn = mapped
        } else {
            let hasPR = !link.prLinks.isEmpty
            let allPRsDone = link.allPRsDone
            newColumn = AssignColumn.assign(
                link: link,
                activityState: activityState,
                hasPR: hasPR,
                allPRsDone: allPRsDone,
                hasWorktree: hasWorktree
            )
        }

        // If an archived card becomes actively working, clear the archive flag
        // so it stays in waiting (not allSessions) once work stops.
        if link.manuallyArchived && newColumn == .inProgress {
            link.manuallyArchived = false
        }

        if newColumn != link.column {
            link.column = newColumn
            link.updatedAt = .now
        }
    }

    /// Map a formaltask lifecycle status to a kanban column.
    /// Returns nil for unrecognized statuses so the caller falls through to
    /// existing inference rather than guessing.
    /// Mapping per plan §Lifecycle table:
    ///   open           → backlog
    ///   in_progress    → inProgress
    ///   blocked_user   → waiting (closest analog; no dedicated blocked lane)
    ///   pending_review → inReview
    ///   completed      → done
    ///   cancelled      → done (no separate cancelled lane)
    static func mapLocalTaskStatus(_ status: String?) -> KanbanCodeColumn? {
        switch status {
        case "open": return .backlog
        case "in_progress": return .inProgress
        case "blocked_user": return .waiting
        case "pending_review": return .inReview
        case "completed": return .done
        case "cancelled": return .done
        default: return nil
        }
    }
}
