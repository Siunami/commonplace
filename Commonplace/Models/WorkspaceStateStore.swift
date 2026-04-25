import Foundation

/// JSON persistence for `WorkspaceState`. Stores the entire panes /
/// tabs / widths shape so the user's open tabs and pane layout
/// survive app restart.
///
/// Format is versioned (top-level `version` field) so future schema
/// changes can either migrate or, in the worst case, fall back to
/// `.initial` without wedging the workspace. v1 is the current shape;
/// load failures of any kind degrade to nil so the caller falls back
/// to the default workspace.
enum WorkspaceStateStore {
    private static let key = "workspaceStateV1"
    private static let currentVersion = 1

    /// Read the persisted state from UserDefaults. Returns nil on first
    /// launch, decode failure, version mismatch, or any validation
    /// failure — caller should fall back to `WorkspaceState.initial`.
    static func load() -> WorkspaceState? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            return nil
        }
        guard envelope.version == currentVersion else { return nil }
        return validate(envelope.state)
    }

    /// Persist state. Failures are logged + swallowed — losing the
    /// next-launch layout is annoying but not catastrophic, the user
    /// just restarts with the default workspace.
    static func save(_ state: WorkspaceState) {
        let envelope = Envelope(version: currentVersion, state: state)
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// Validate / repair a decoded state. Drops any stack tabs whose
    /// referenced stack id no longer exists in the database, fixes
    /// pane-width array length mismatches, and falls back to nil
    /// (caller uses `.initial`) if the result is unsalvageable.
    private static func validate(_ raw: WorkspaceState) -> WorkspaceState? {
        guard !raw.panes.isEmpty else { return nil }

        // Prune stack tabs whose stack vanished while the app was
        // closed. Walk every pane; collect surviving tabs.
        var prunedPanes: [WorkspacePane] = []
        for pane in raw.panes {
            let surviving = pane.tabs.filter { tab in
                if case .stack(let id) = tab.content {
                    return DatabaseManager.shared.stack(byId: id) != nil
                }
                return true
            }
            if surviving.isEmpty {
                // Pane lost all its tabs — substitute a fresh chooser
                // so the pane survives (otherwise the workspace might
                // shrink to zero panes).
                let fallbackTab = WorkspaceTab(content: .newTab)
                prunedPanes.append(WorkspacePane(tabs: [fallbackTab]))
            } else {
                let activeStillThere = surviving.contains(where: { $0.id == pane.activeTabId })
                let activeId = activeStillThere ? pane.activeTabId : surviving[0].id
                prunedPanes.append(WorkspacePane(id: pane.id, tabs: surviving, activeTabId: activeId))
            }
        }

        let activePaneId = prunedPanes.contains(where: { $0.id == raw.activePaneId })
            ? raw.activePaneId
            : prunedPanes[0].id

        let widths: [Double]?
        if raw.paneWidths.count == prunedPanes.count, raw.paneWidths.allSatisfy({ $0 > 0 }) {
            widths = raw.paneWidths
        } else {
            widths = nil // initializer regenerates even widths
        }

        return WorkspaceState(panes: prunedPanes, activePaneId: activePaneId, paneWidths: widths)
    }

    private struct Envelope: Codable {
        let version: Int
        let state: WorkspaceState
    }
}
