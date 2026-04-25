import SwiftUI
import AppKit
import Combine

/// Two display modes for the items section. Grid keeps the existing
/// square mosaic; list trades density for per-item readability by
/// rendering each item as a full-width row.
enum StackViewMode {
    case grid
    case list
}

/// Inline body for a single Stack — embedded as the content of a Stack
/// tab inside a workspace pane. No modal chrome of its own; the tab bar
/// owns close + activation. Supports:
///   - Editing name + description
///   - Seeding the stack with an inline note composer
///   - Browsing all items in a responsive grid OR a full-width list
///   - Removing items from the stack
///   - Pinning / unpinning the stack
struct StackBody: View {
    let stack: Stack
    var onOpenHighlight: (Highlight) -> Void = { _ in }
    /// Opens a substack as its own tab in the workspace. The parent
    /// screen remains open — navigation between parent and child is via
    /// the workspace's normal tab switching / focus logic.
    var onOpenSubstack: (Stack) -> Void = { _ in }
    /// Fires when the stack we're showing has been deleted out from under
    /// us (merged into another stack, removed from the all-stacks view,
    /// etc.). The owning workspace closes the tab in response.
    var onStackVanished: () -> Void = {}

    @State private var currentStack: Stack
    @State private var items: [Highlight] = []
    /// Substacks attached to the current stack, rendered in a section
    /// above the items grid. Loaded separately because their ordering
    /// and positions live in the independent `stack_stack` junction.
    @State private var substacks: [Stack] = []
    @State private var noteCounts: [String: Int] = [:]
    /// Full bodies of every note attached to a visible item, grouped by
    /// highlight id (oldest → newest). Loaded so the list view can render
    /// each annotation inline as a document — the user explicitly wants
    /// the list-mode stack to show every note in full, not collapse them
    /// behind a "+N more notes" badge.
    @State private var highlightNotes: [String: [HighlightNote]] = [:]
    @State private var nameDraft: String = ""
    @State private var descriptionDraft: String = ""
    @State private var isEditingName = false
    @State private var isEditingDescription = false
    /// Pinned stack (if any) — the candidate merge source. Kept in state
    /// so the merge button's label and disabled state refresh whenever
    /// the pin changes elsewhere.
    @State private var pinnedStack: Stack? = nil
    @State private var pinnedItemCount: Int = 0
    @State private var showMergeConfirm = false
    /// When true, the attach-existing-stack picker sheet is up.
    @State private var showAttachPicker = false
    /// Gates the destructive confirmation dialog for deleting the stack.
    @State private var showDeleteConfirm = false

    /// Multi-select state. Cmd-click toggles a cell, Shift-click extends
    /// a range from `anchorSelectionIndex` to the tapped cell. A floating
    /// action bar at the bottom surfaces bulk actions (remove, split to
    /// new stack) while the selection is non-empty. Plain click always
    /// opens the tapped item — selection and open coexist so the user
    /// can build a selection without losing the ability to peek an item.
    @State private var selectedIds: Set<String> = []
    @State private var anchorSelectionIndex: Int? = nil
    @State private var splitConfirmationText: String? = nil

    // Drag-to-reorder. The in-flow cell for the dragged item becomes
    // invisible while a floating preview — rendered as a sibling of the
    // grid in the same "stackGrid" coordinate space — follows the
    // cursor via `.position`. Decoupling the preview from the grid's
    // layout means cursor-tracking is instant and doesn't fight the
    // spring animation that reshuffles neighbour cells.
    @State private var cellFrames: [String: CGRect] = [:]
    @State private var slotSize: CGSize = .zero
    @State private var draggingId: String? = nil
    @State private var dragCursor: CGPoint = .zero
    @State private var dragCursorOffsetInCell: CGSize = .zero
    /// Set briefly on drag end so the concurrent `onTapGesture` in the
    /// cell doesn't fire `onOpen()` as a side-effect of the release.
    @State private var didJustDrag = false

    /// Per-row frames collected via a preference key so the list
    /// drag-to-reorder can find which row the cursor is over. Separate
    /// from `cellFrames` because the two views use different
    /// coordinate spaces and row geometries.
    @State private var listRowFrames: [String: CGRect] = [:]
    @State private var listContentWidth: CGFloat = 0

    /// Grid vs. list rendering of the items section. Session-local for
    /// now — list is an experiment; if it proves sticky we can persist
    /// per-stack or per-workspace.
    @State private var viewMode: StackViewMode = .grid

    /// Inline composer for seeding the stack with a note. `noteDraft` is
    /// the live text; `isComposingNote` toggles the expanded editor vs.
    /// the collapsed "write a note" affordance.
    @State private var noteDraft: String = ""
    @State private var isComposingNote: Bool = false

    init(
        stack: Stack,
        onOpenHighlight: @escaping (Highlight) -> Void = { _ in },
        onOpenSubstack: @escaping (Stack) -> Void = { _ in },
        onStackVanished: @escaping () -> Void = {}
    ) {
        self.stack = stack
        self.onOpenHighlight = onOpenHighlight
        self.onOpenSubstack = onOpenSubstack
        self.onStackVanished = onStackVanished

        // Hot-mount path: if this stack was rendered recently (e.g. the
        // user just dragged its tab into a new pane), paint the first
        // frame with cached data. `.onAppear` still fires `reload()`
        // to pick up any mutations made while we were unmounted.
        if let cached = StackBodyCache.shared.cached(stackId: stack.id) {
            _currentStack = State(initialValue: cached.stack)
            _items = State(initialValue: cached.items)
            _substacks = State(initialValue: cached.substacks)
            _noteCounts = State(initialValue: cached.noteCounts)
            _highlightNotes = State(initialValue: cached.highlightNotes)
            _pinnedStack = State(initialValue: cached.pinnedStack)
            _pinnedItemCount = State(initialValue: cached.pinnedItemCount)
            _nameDraft = State(initialValue: cached.stack.name ?? "")
            _descriptionDraft = State(initialValue: cached.stack.stackDescription ?? "")
        } else {
            _currentStack = State(initialValue: stack)
            _nameDraft = State(initialValue: stack.name ?? "")
            _descriptionDraft = State(initialValue: stack.stackDescription ?? "")
        }
    }

    private let db = DatabaseManager.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(UITokens.surfaceBackground)
        .overlay(alignment: .bottom) {
            if !selectedIds.isEmpty {
                selectionActionBar
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .top) {
            if let text = splitConfirmationText {
                Text(text)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.9))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(UITokens.surfaceFloater)
                            .shadow(color: .black.opacity(0.25), radius: 10, y: 2)
                    )
                    .padding(.top, 70)
                    .transition(.opacity)
            }
        }
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .stackDataDidChange).receive(on: DispatchQueue.main)) { _ in
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .highlightDataDidChange).receive(on: DispatchQueue.main)) { notification in
            let userInfo = notification.userInfo ?? [:]
            let change = userInfo["change"] as? String ?? ""
            guard let hid = userInfo["highlightId"] as? String,
                  items.contains(where: { $0.id == hid }) else { return }
            switch change {
            case "userNote":
                if let updated = db.highlight(byId: hid),
                   let idx = items.firstIndex(where: { $0.id == hid }) {
                    items[idx] = updated
                }
            case "notes":
                let counts = db.noteCountsForHighlights(ids: [hid])
                noteCounts[hid] = counts[hid] ?? 0
                if let updated = db.highlight(byId: hid),
                   let idx = items.firstIndex(where: { $0.id == hid }) {
                    items[idx] = updated
                }
            default:
                break
            }
        }
        .onExitCommand {
            if !selectedIds.isEmpty {
                withAnimation(.easeInOut(duration: 0.15)) {
                    selectedIds.removeAll()
                    anchorSelectionIndex = nil
                }
            }
        }
        .sheet(isPresented: $showAttachPicker) {
            SubstackPickerSheet(
                parentId: currentStack.id,
                existingChildIds: Set(substacks.map(\.id)),
                onPick: { chosen in
                    db.addSubstack(chosen.id, toStack: currentStack.id)
                    showAttachPicker = false
                },
                onCancel: { showAttachPicker = false }
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 4) {
                    nameField
                    descriptionField
                    Text(countsSummary)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                }

                Spacer()

                HStack(spacing: 8) {
                    moreMenu
                    mergeButton
                    viewModeToggle
                    exportMenu
                    pinToggleButton
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private var nameField: some View {
        if isEditingName {
            TextField("Name this stack", text: $nameDraft, onCommit: commitName)
                .textFieldStyle(.plain)
                .font(.system(size: 20, weight: .semibold))
                .onExitCommand {
                    nameDraft = currentStack.name ?? ""
                    isEditingName = false
                }
        } else {
            Text(currentStack.isNamed ? (currentStack.name ?? "") : "Unnamed stack")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(currentStack.isNamed ? .primary : .secondary)
                .onTapGesture {
                    nameDraft = currentStack.name ?? ""
                    isEditingName = true
                }
        }
    }

    @ViewBuilder
    private var descriptionField: some View {
        if isEditingDescription {
            TextField("Add a description", text: $descriptionDraft, onCommit: commitDescription)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .onExitCommand {
                    descriptionDraft = currentStack.stackDescription ?? ""
                    isEditingDescription = false
                }
        } else {
            Text(currentStack.stackDescription?.isEmpty == false
                 ? (currentStack.stackDescription ?? "")
                 : "Add a description")
                .font(.system(size: 13))
                .foregroundStyle(currentStack.stackDescription?.isEmpty == false ? .secondary : .tertiary)
                .onTapGesture {
                    descriptionDraft = currentStack.stackDescription ?? ""
                    isEditingDescription = true
                }
        }
    }

    /// Multi-target export menu. Bear (Textbundle) sits alone at the top
    /// as the portable archival format; the "send to another tool" group
    /// below covers LLM handoff (ChatGPT, Claude) and plain clipboard
    /// markdown. Extending to more destinations is a one-line addition
    /// to `StackExportTargets.all`.
    private var exportMenu: some View {
        Menu {
            ForEach(Array(StackExportTargets.all.enumerated()), id: \.element.id) { index, target in
                if index == 1 {
                    Divider()
                }
                Button {
                    performExportTarget(target)
                } label: {
                    Label(target.displayName, systemImage: target.iconSystemName)
                }
                .help(target.help)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 10))
                Text("Export")
                    .font(.system(size: 11, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
                    .opacity(0.7)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(Color.primary.opacity(0.06))
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(items.isEmpty)
        .help("Export this stack to another tool")
    }

    /// Header-level "Merge pinned here" — fuses the currently-pinned stack
    /// into the stack on screen and deletes the pinned one. Hidden when
    /// there's no pin to merge, or when the viewed stack *is* the pin
    /// (self-merge is a no-op and would just delete the thing you're
    /// looking at).
    @ViewBuilder
    private var mergeButton: some View {
        if canMerge {
            Button(action: { showMergeConfirm = true }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.merge")
                        .font(.system(size: 10))
                    Text(mergeButtonLabel)
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(Color.primary.opacity(0.06))
                )
            }
            .buttonStyle(.plain)
            .help("Merge pinned stack’s items into this one and delete the pinned stack")
            .confirmationDialog(
                mergeDialogTitle,
                isPresented: $showMergeConfirm,
                titleVisibility: .visible
            ) {
                Button("Merge and Delete Pinned", role: .destructive, action: performMerge)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(mergeDialogMessage)
            }
        }
    }

    private var canMerge: Bool {
        guard let pinned = pinnedStack else { return false }
        return pinned.id != currentStack.id
    }

    private var mergeButtonLabel: String {
        guard let pinned = pinnedStack else { return "Merge pinned" }
        let name = pinned.isNamed ? (pinned.name ?? "Pinned") : "Unnamed stack"
        return "Merge ‘\(name)’ here"
    }

    private var mergeDialogTitle: String {
        guard let pinned = pinnedStack else { return "Merge pinned stack" }
        let source = pinned.isNamed ? (pinned.name ?? "Pinned") : "Unnamed stack"
        let dest = currentStack.isNamed ? (currentStack.name ?? "This stack") : "Unnamed stack"
        return "Merge ‘\(source)’ into ‘\(dest)’?"
    }

    private var mergeDialogMessage: String {
        let n = pinnedItemCount
        let items = "\(n) item\(n == 1 ? "" : "s")"
        return "All \(items) in the pinned stack will be added here. The pinned stack will then be deleted. This can’t be undone."
    }

    private var countsSummary: String {
        var parts: [String] = []
        if !substacks.isEmpty {
            parts.append("\(substacks.count) substack\(substacks.count == 1 ? "" : "s")")
        }
        parts.append("\(items.count) item\(items.count == 1 ? "" : "s")")
        return parts.joined(separator: " · ")
    }

    /// Header overflow menu — keeps the primary toolbar tight by hiding
    /// the less-frequent tree operations behind "•••". Attach existing
    /// stack opens the picker sheet; delete drops the stack (items stay
    /// in the library, stack rows + memberships are removed).
    private var moreMenu: some View {
        Menu {
            Button {
                showAttachPicker = true
            } label: {
                Label("Add existing stack as substack…", systemImage: "rectangle.stack.badge.plus")
            }
            .help("Attach any other stack as a child of this one")

            Divider()

            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Delete stack…", systemImage: "trash")
            }
            .help("Remove this stack. Items stay in the library.")
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More actions")
        .confirmationDialog(
            deleteDialogTitle,
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Stack", role: .destructive, action: performDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteDialogMessage)
        }
    }

    private var deleteDialogTitle: String {
        let name = currentStack.isNamed ? (currentStack.name ?? "this stack") : "Unnamed stack"
        return "Delete ‘\(name)’?"
    }

    private var deleteDialogMessage: String {
        let n = items.count
        let itemsPart = n == 0
            ? "The stack has no items."
            : "\(n) item\(n == 1 ? "" : "s") will stay in your library."
        let subPart = substacks.isEmpty
            ? ""
            : " Substack relationships will be removed (the substacks themselves are kept)."
        return "\(itemsPart)\(subPart) This can’t be undone."
    }

    private func performDelete() {
        db.deleteStack(id: currentStack.id)
    }

    /// Two-button segmented pill that flips between grid and list modes
    /// for the items section. Matches the header's other pill controls
    /// in height + corner radius so the toolbar reads as one group.
    private var viewModeToggle: some View {
        HStack(spacing: 2) {
            modeToggleButton(mode: .grid, icon: "square.grid.2x2", help: "Grid view")
            modeToggleButton(mode: .list, icon: "list.bullet", help: "List view")
        }
        .padding(2)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
    }

    @ViewBuilder
    private func modeToggleButton(mode: StackViewMode, icon: String, help: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { viewMode = mode }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(viewMode == mode ? Color.primary : .secondary)
                .frame(width: 24, height: 18)
                .background(
                    Capsule().fill(viewMode == mode ? Color.primary.opacity(0.12) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var pinToggleButton: some View {
        Button(action: togglePin) {
            HStack(spacing: 4) {
                Image(systemName: currentStack.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 10))
                Text(currentStack.isPinned ? "Pinned" : "Pin")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(currentStack.isPinned ? .white : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(currentStack.isPinned ? Color.accentColor : Color.primary.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
        .help(currentStack.isPinned ? "Unpin stack" : "Pin stack")
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                noteComposer
                if !substacks.isEmpty {
                    substacksSection
                }
                if !items.isEmpty {
                    itemsSection
                } else if substacks.isEmpty {
                    emptyItemsHint
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
        }
    }

    // MARK: - Note composer

    /// Collapsed affordance until tapped; expanded editor afterwards.
    /// The expanded state persists while there's any draft text so the
    /// user can click away without losing what they've typed.
    @ViewBuilder
    private var noteComposer: some View {
        if isComposingNote || hasDraftText {
            composerExpanded
        } else {
            composerCollapsed
        }
    }

    private var hasDraftText: Bool {
        !noteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var composerCollapsed: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            Text("Write a note to seed this stack…")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: UITokens.radiusCard)
                .fill(UITokens.surfaceCard.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: UITokens.radiusCard)
                .strokeBorder(UITokens.surfaceBorder, style: StrokeStyle(lineWidth: 0.75, dash: [4, 3]))
        )
        .contentShape(RoundedRectangle(cornerRadius: UITokens.radiusCard))
        .onTapGesture { isComposingNote = true }
    }

    private var composerExpanded: some View {
        VStack(spacing: 0) {
            NoteComposerTextView(
                text: $noteDraft,
                onSubmit: submitNoteDraft,
                onCancel: cancelNoteDraft,
                onFocusLost: {
                    if !hasDraftText {
                        isComposingNote = false
                    }
                }
            )
            .frame(minHeight: 72, maxHeight: 200)
            .padding(12)

            Divider().opacity(0.5)

            HStack(spacing: 10) {
                Spacer()
                Text("⌘↩ to add · Esc to cancel")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Button(action: submitNoteDraft) {
                    Text("Add to stack")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(hasDraftText ? Color.accentColor : Color.secondary.opacity(0.3))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!hasDraftText)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .background(
            RoundedRectangle(cornerRadius: UITokens.radiusCard)
                .fill(UITokens.surfaceCard.opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: UITokens.radiusCard)
                .strokeBorder(UITokens.surfaceBorder, lineWidth: 0.5)
        )
    }

    private func submitNoteDraft() {
        let trimmed = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let highlightId = HighlightCapture.shared.captureFromUserAdd(text: trimmed)
        db.addHighlight(highlightId, toStack: currentStack.id)
        noteDraft = ""
        isComposingNote = false
    }

    private func cancelNoteDraft() {
        noteDraft = ""
        isComposingNote = false
    }

    /// Small nudge shown inside the scroll view when the stack has no
    /// items AND no substacks. The composer above is the primary CTA;
    /// this hint just points at the secondary capture path.
    private var emptyItemsHint: some View {
        VStack(spacing: 6) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 22))
                .foregroundStyle(.quaternary)
            Text("Empty so far — add a note above, or pin this stack and capture from anywhere.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    // MARK: - Substacks section

    /// Horizontal-flow grid of substack tiles. Tapping a tile opens the
    /// child in its own workspace tab via `onOpenSubstack`. Order follows
    /// the `stack_stack.position` the DB layer hands back.
    @ViewBuilder
    private var substacksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "Stacks",
                count: substacks.count,
                trailingAction: { showAttachPicker = true },
                trailingIcon: "plus",
                trailingHelp: "Add an existing stack as a substack"
            )
            LazyVGrid(columns: substackGridColumns, alignment: .leading, spacing: 14) {
                ForEach(substacks) { child in
                    SubstackTile(
                        child: child,
                        parentId: currentStack.id,
                        onOpen: { onOpenSubstack(child) }
                    )
                }
            }
        }
    }

    private var substackGridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 220, maximum: 240), spacing: 14, alignment: .topLeading)]
    }

    // MARK: - Items section

    /// Items section wrapper — renders the header row (only when there's
    /// a sibling substacks section to disambiguate) and hands off to
    /// the grid or list body based on `viewMode`.
    @ViewBuilder
    private var itemsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !substacks.isEmpty {
                sectionHeader(title: "Items", count: items.count)
            }
            switch viewMode {
            case .grid:
                itemsGridBody
            case .list:
                itemsListBody
            }
        }
    }

    /// The existing square-cell grid with drag-to-reorder. Keeps the
    /// drag-reorder "stackGrid" coordinate space scoped to this subtree.
    private var itemsGridBody: some View {
        ZStack(alignment: .topLeading) {
            LazyVGrid(columns: gridColumns, spacing: 14) {
                ForEach(items) { item in
                    cellWrapper(for: item)
                }
            }

            if let id = draggingId,
               let draggedItem = items.first(where: { $0.id == id }) {
                floatingDragPreview(for: draggedItem)
            }
        }
        .coordinateSpace(name: "stackGrid")
        .onPreferenceChange(CellFramesKey.self) { frames in
            var dict: [String: CGRect] = [:]
            for frame in frames { dict[frame.id] = frame.frame }
            cellFrames = dict
            if let any = frames.first?.frame.size, any != .zero {
                slotSize = any
            }
        }
    }

    /// Document-style list. Items flow without per-row chrome; a drag
    /// handle appears on hover in the leading gutter and re-orders the
    /// list inline. The dragged row lifts into a floating preview that
    /// tracks the cursor while its neighbours animate around it.
    private var itemsListBody: some View {
        ZStack(alignment: .topLeading) {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(items) { item in
                    listRowWrapper(for: item)
                }
            }
            .background(
                GeometryReader { geo in
                    Color.clear
                        .preference(key: ListContentWidthKey.self, value: geo.size.width)
                }
            )

            if let id = draggingId,
               let draggedItem = items.first(where: { $0.id == id }) {
                floatingListDragPreview(for: draggedItem)
            }
        }
        .coordinateSpace(name: "stackList")
        .onPreferenceChange(ListRowFramesKey.self) { frames in
            var dict: [String: CGRect] = [:]
            for f in frames { dict[f.id] = f.frame }
            listRowFrames = dict
        }
        .onPreferenceChange(ListContentWidthKey.self) { w in
            listContentWidth = w
        }
    }

    @ViewBuilder
    private func listRowWrapper(for item: Highlight) -> some View {
        let isDragging = draggingId == item.id
        MaterialListRow(
            highlight: item,
            noteCount: noteCounts[item.id] ?? 0,
            notes: highlightNotes[item.id] ?? [],
            isSelected: selectedIds.contains(item.id),
            isBeingDragged: isDragging,
            didJustDrag: didJustDrag,
            onRemove: { db.removeHighlight(item.id, fromStack: currentStack.id) },
            onOpen: { handleCellTap(item) },
            onHandleDragChanged: { location in handleListDragChanged(item: item, location: location) },
            onHandleDragEnded: { handleListDragEnded(item: item) }
        )
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: ListRowFramesKey.self,
                    value: [ListRowFrame(id: item.id, frame: geo.frame(in: .named("stackList")))]
                )
            }
        )
        .opacity(isDragging ? 0 : 1)
    }

    /// Floating copy of the dragged row that tracks the cursor in the
    /// "stackList" coordinate space. The original row becomes invisible
    /// (via `.opacity(0)`) while this preview stands in, so the row's
    /// layout slot keeps its height and neighbours reshuffle cleanly.
    @ViewBuilder
    private func floatingListDragPreview(for item: Highlight) -> some View {
        let rowSize = listRowFrames[item.id]?.size ?? CGSize(width: max(listContentWidth, 320), height: 60)
        MaterialListRow(
            highlight: item,
            noteCount: noteCounts[item.id] ?? 0,
            isSelected: false,
            isBeingDragged: true,
            didJustDrag: false,
            onRemove: nil,
            onOpen: {},
            onHandleDragChanged: nil,
            onHandleDragEnded: nil
        )
        .frame(width: rowSize.width, height: rowSize.height)
        .scaleEffect(1.01)
        .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
        .position(
            x: rowSize.width / 2,
            y: dragCursor.y - dragCursorOffsetInCell.height + rowSize.height / 2
        )
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    private func handleListDragChanged(item: Highlight, location: CGPoint) {
        if draggingId == nil {
            let origin = listRowFrames[item.id]?.origin ?? .zero
            dragCursorOffsetInCell = CGSize(
                width: location.x - origin.x,
                height: location.y - origin.y
            )
            dragCursor = location
            draggingId = item.id
        } else {
            dragCursor = location
        }
        guard let targetId = listRowIDContaining(y: location.y),
              targetId != item.id,
              let from = items.firstIndex(where: { $0.id == item.id }),
              let to = items.firstIndex(where: { $0.id == targetId }) else {
            return
        }
        let destination = to > from ? to + 1 : to
        withAnimation(.interactiveSpring(response: 0.18, dampingFraction: 0.86)) {
            items.move(fromOffsets: IndexSet(integer: from), toOffset: destination)
        }
    }

    private func handleListDragEnded(item: Highlight) {
        guard draggingId == item.id else { return }
        let order = items.map(\.id)
        let stackId = currentStack.id
        Task.detached(priority: .userInitiated) {
            DatabaseManager.shared.reorderHighlightsInStack(stackId: stackId, orderedIds: order)
        }
        draggingId = nil
        didJustDrag = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            didJustDrag = false
        }
    }

    private func listRowIDContaining(y: CGFloat) -> String? {
        for (id, frame) in listRowFrames where y >= frame.minY && y <= frame.maxY {
            return id
        }
        return nil
    }

    @ViewBuilder
    private func sectionHeader(
        title: String,
        count: Int,
        trailingAction: (() -> Void)? = nil,
        trailingIcon: String? = nil,
        trailingHelp: String? = nil
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.85))
            Text("\(count)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
            Spacer()
            if let action = trailingAction, let icon = trailingIcon {
                Button(action: action) {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .help(trailingHelp ?? "")
            }
        }
    }

    @ViewBuilder
    private func cellWrapper(for item: Highlight) -> some View {
        let isDragging = draggingId == item.id
        let isSelected = selectedIds.contains(item.id)
        StackDetailItemCell(
            highlight: item,
            noteCount: noteCounts[item.id] ?? 0,
            isBeingDragged: isDragging,
            didJustDrag: didJustDrag,
            isSelected: isSelected,
            onRemove: {
                db.removeHighlight(item.id, fromStack: currentStack.id)
            },
            onOpen: {
                handleCellTap(item)
            }
        )
        .aspectRatio(1, contentMode: .fit)
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: CellFramesKey.self,
                    value: [CellFrame(id: item.id, frame: geo.frame(in: .named("stackGrid")))]
                )
            }
        )
        .opacity(isDragging ? 0 : 1)
        .simultaneousGesture(dragGesture(for: item))
    }

    /// Resolve a cell tap against the current modifier flags. Cmd toggles
    /// the item in the selection and anchors a range-start; Shift selects
    /// every cell between the anchor and the tapped index (inclusive);
    /// plain clicks are unaffected by selection state and always open the
    /// item, matching the "selection builds silently" pattern of Finder's
    /// grid views.
    private func handleCellTap(_ item: Highlight) {
        let flags = NSEvent.modifierFlags
        guard let tappedIndex = items.firstIndex(where: { $0.id == item.id }) else {
            onOpenHighlight(item)
            return
        }
        if flags.contains(.command) {
            if selectedIds.contains(item.id) {
                selectedIds.remove(item.id)
            } else {
                selectedIds.insert(item.id)
            }
            anchorSelectionIndex = tappedIndex
            return
        }
        if flags.contains(.shift), let anchor = anchorSelectionIndex {
            let lower = min(anchor, tappedIndex)
            let upper = max(anchor, tappedIndex)
            for i in lower...upper {
                selectedIds.insert(items[i].id)
            }
            return
        }
        onOpenHighlight(item)
    }

    /// Floats above the grid in the same coordinate space. `.position`
    /// is a pure-layout modifier that reads `dragCursor` directly — no
    /// animation, no dependency on the cell's natural slot origin, so
    /// it tracks the cursor 1:1 on every drag tick.
    @ViewBuilder
    private func floatingDragPreview(for item: Highlight) -> some View {
        StackDetailItemCell(
            highlight: item,
            noteCount: noteCounts[item.id] ?? 0,
            isBeingDragged: true,
            didJustDrag: false,
            isSelected: false,
            onRemove: {},
            onOpen: {}
        )
        .frame(width: slotSize.width, height: slotSize.height)
        .scaleEffect(1.04)
        .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
        .rotationEffect(.degrees(1.2))
        .position(
            x: dragCursor.x - dragCursorOffsetInCell.width + slotSize.width / 2,
            y: dragCursor.y - dragCursorOffsetInCell.height + slotSize.height / 2
        )
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    private func dragGesture(for item: Highlight) -> some Gesture {
        // Short minimumDistance keeps drag engagement feeling
        // immediate while still letting a pure click reach the cell's
        // onTapGesture (open-in-detail).
        DragGesture(minimumDistance: 3, coordinateSpace: .named("stackGrid"))
            .onChanged { value in
                if draggingId == nil {
                    let origin = cellFrames[item.id]?.origin ?? .zero
                    dragCursorOffsetInCell = CGSize(
                        width: value.startLocation.x - origin.x,
                        height: value.startLocation.y - origin.y
                    )
                    dragCursor = value.location
                    draggingId = item.id
                } else {
                    dragCursor = value.location
                }
                guard let targetId = cellIDContainingPoint(value.location),
                      targetId != item.id,
                      let from = items.firstIndex(where: { $0.id == item.id }),
                      let to = items.firstIndex(where: { $0.id == targetId }) else {
                    return
                }
                let destination = to > from ? to + 1 : to
                withAnimation(.interactiveSpring(response: 0.18, dampingFraction: 0.86)) {
                    items.move(fromOffsets: IndexSet(integer: from), toOffset: destination)
                }
            }
            .onEnded { _ in
                guard draggingId == item.id else { return }
                let order = items.map(\.id)
                let stackId = currentStack.id
                Task.detached(priority: .userInitiated) {
                    DatabaseManager.shared.reorderHighlightsInStack(stackId: stackId, orderedIds: order)
                }
                draggingId = nil
                didJustDrag = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    didJustDrag = false
                }
            }
    }

    private func cellIDContainingPoint(_ point: CGPoint) -> String? {
        // Require containment (not nearest-center) so cursors in the
        // gutter between cells don't thrash neighbouring cells.
        for (id, frame) in cellFrames where frame.contains(point) {
            return id
        }
        return nil
    }

    /// Adaptive square cells — column count scales with the window,
    /// but every cell shares the same width and (via the aspectRatio
    /// modifier above) the same height, producing the clean uniform
    /// grid the stack view had originally.
    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 14)]
    }

    // MARK: - Actions

    private func reload() {
        guard let refreshed = db.stack(byId: currentStack.id) else {
            DispatchQueue.main.async(execute: onStackVanished)
            StackBodyCache.shared.invalidate(stackId: currentStack.id)
            return
        }
        currentStack = refreshed
        items = db.highlightsForStack(stackId: currentStack.id)
        substacks = db.substacksForStack(stackId: currentStack.id)
        let ids = items.map(\.id)
        noteCounts = db.noteCountsForHighlights(ids: ids)
        highlightNotes = db.notesForHighlights(ids: ids)
        let pinned = db.pinnedStack()
        pinnedStack = pinned
        pinnedItemCount = pinned.map { db.itemCountForStack(stackId: $0.id) } ?? 0

        // Write the fast-path cache so the next mount (e.g. after a
        // pane move) starts with live data instead of a cold load.
        StackBodyCache.shared.store(
            stackId: currentStack.id,
            state: CachedStackBodyState(
                stack: refreshed,
                items: items,
                substacks: substacks,
                noteCounts: noteCounts,
                highlightNotes: highlightNotes,
                pinnedStack: pinnedStack,
                pinnedItemCount: pinnedItemCount
            )
        )

        // Drop selections for items that are no longer in the stack (they
        // may have just been removed by our own bulk action, merged away,
        // or edited by another window).
        let liveIds = Set(ids)
        if !selectedIds.isSubset(of: liveIds) {
            selectedIds = selectedIds.intersection(liveIds)
            if selectedIds.isEmpty { anchorSelectionIndex = nil }
        }
        // If the merge confirmation was staged against a pin that's since
        // changed or disappeared, close it so the user can't confirm an
        // action that no longer matches the labels on the button.
        if showMergeConfirm, !canMerge {
            showMergeConfirm = false
        }
    }

    private func performMerge() {
        guard let pinned = pinnedStack, pinned.id != currentStack.id else { return }
        _ = db.mergeStack(sourceId: pinned.id, into: currentStack.id)
    }

    // MARK: - Multi-select action bar

    /// Floating pill shown at the bottom of the grid while at least one
    /// cell is selected. Surfaces the bulk actions we care about today —
    /// remove from stack, split into a new stack — plus a cancel that
    /// clears the selection without mutating anything.
    private var selectionActionBar: some View {
        HStack(spacing: 14) {
            Text("\(selectedIds.count) selected")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.9))

            Divider().frame(height: 16)

            actionBarButton(icon: "rectangle.stack.badge.plus", label: "Group into substack", action: groupSelectionIntoSubstack)
            actionBarButton(icon: "arrow.up.and.line.horizontal.and.arrow.down", label: "Move to new stack", action: splitSelectionToNewStack)
            actionBarButton(icon: "minus.circle", label: "Remove from stack", action: removeSelection, tint: Color.red.opacity(0.85))

            Divider().frame(height: 16)

            actionBarButton(icon: "xmark", label: "Clear", action: clearSelection)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(UITokens.surfaceFloater)
                .shadow(color: .black.opacity(0.3), radius: 18, y: 6)
        )
        .overlay(Capsule().strokeBorder(UITokens.surfaceBorder, lineWidth: 0.5))
    }

    @ViewBuilder
    private func actionBarButton(icon: String, label: String, action: @escaping () -> Void, tint: Color = .primary) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                Text(label).font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(tint.opacity(0.85))
        }
        .buttonStyle(.plain)
        .help(label)
    }

    private func clearSelection() {
        withAnimation(.easeInOut(duration: 0.15)) {
            selectedIds.removeAll()
            anchorSelectionIndex = nil
        }
    }

    private func removeSelection() {
        let ids = selectedIds
        guard !ids.isEmpty else { return }
        for id in ids {
            db.removeHighlight(id, fromStack: currentStack.id)
        }
        clearSelection()
    }

    /// "Group into substack" — collapse the selected highlights into a
    /// new unnamed child stack that attaches to the parent. Unlike
    /// "Move to new stack" the new stack lives *inside* this one as a
    /// substack, and surfaces at the top of the substacks section.
    /// The user can rename the new substack inline from its detail view.
    private func groupSelectionIntoSubstack() {
        let ids = selectedIds
        guard !ids.isEmpty else { return }
        let ordered = items.filter { ids.contains($0.id) }.map(\.id)
        guard let newChild = db.extractSubstackFromSelection(
            highlightIds: ordered,
            inStack: currentStack.id
        ) else { return }
        clearSelection()
        showSplitConfirmation("Grouped \(ordered.count) into a substack")
        _ = newChild
    }

    /// Split the current selection out into a new unnamed stack. The
    /// source stack stays if it has survivors, or is auto-deleted by
    /// the DB method if the selection emptied it. A brief HUD toast
    /// names the new stack so the user knows where the items went.
    private func splitSelectionToNewStack() {
        let ids = selectedIds
        guard !ids.isEmpty else { return }
        let ordered = items.filter { ids.contains($0.id) }.map(\.id)
        guard let newStack = db.moveHighlightsToNewStack(highlightIds: ordered, fromStack: currentStack.id) else {
            return
        }
        clearSelection()
        showSplitConfirmation("Moved \(ordered.count) to new stack")
        _ = newStack
    }

    private func showSplitConfirmation(_ text: String) {
        withAnimation(.easeInOut(duration: 0.15)) { splitConfirmationText = text }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.3)) { splitConfirmationText = nil }
            }
        }
    }

    private func commitName() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        db.renameStack(id: currentStack.id, name: trimmed.isEmpty ? nil : trimmed)
        isEditingName = false
    }

    private func commitDescription() {
        let trimmed = descriptionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        db.setStackDescription(id: currentStack.id, description: trimmed.isEmpty ? nil : trimmed)
        isEditingDescription = false
    }

    private func togglePin() {
        if currentStack.isPinned {
            db.setPinnedStack(id: nil)
        } else {
            db.setPinnedStack(id: currentStack.id)
        }
    }

    private func performExportTarget(_ target: StackExportTarget) {
        do {
            if let toast = try target.perform(stack: currentStack) {
                showSplitConfirmation(toast)
            }
        } catch StackExporter.ExportError.targetExists(let existing) {
            let alert = NSAlert()
            alert.messageText = "Folder already exists"
            alert.informativeText = "A folder named “\(existing.lastPathComponent)” already exists in the destination. Move or rename it and try again."
            alert.alertStyle = .warning
            alert.runModal()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Export failed"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }
}

// MARK: - Grid cell
//
// The justified grid assigns each cell a fixed (width × height) box —
// all cells in a row share the same height, widths flex with the
// per-item aspect ratio. The cell fills that box: image-like types
// use aspect-fill so the thumbnail covers the whole card, text-like
// types show inline readable text. No internal aspect constraint,
// because the Layout above has already picked the box.

struct CellFrame: Equatable {
    let id: String
    let frame: CGRect
}

struct CellFramesKey: PreferenceKey {
    static let defaultValue: [CellFrame] = []
    static func reduce(value: inout [CellFrame], nextValue: () -> [CellFrame]) {
        value.append(contentsOf: nextValue())
    }
}

struct ListRowFrame: Equatable {
    let id: String
    let frame: CGRect
}

struct ListRowFramesKey: PreferenceKey {
    static let defaultValue: [ListRowFrame] = []
    static func reduce(value: inout [ListRowFrame], nextValue: () -> [ListRowFrame]) {
        value.append(contentsOf: nextValue())
    }
}

struct ListContentWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct StackDetailItemCell: View {
    let highlight: Highlight
    var noteCount: Int = 0
    var isBeingDragged: Bool = false
    var didJustDrag: Bool = false
    var isSelected: Bool = false
    var onRemove: () -> Void
    var onOpen: () -> Void

    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            cellBackground
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            bottomOverlay
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: UITokens.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: UITokens.radiusCard)
                .strokeBorder(
                    isSelected ? Color.accentColor : UITokens.surfaceBorder,
                    lineWidth: isSelected ? 2 : 0.5
                )
        )
        .shadow(color: UITokens.shadowCard, radius: isHovered ? 8 : 6, y: 2)
        .overlay(alignment: .topLeading) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white, Color.accentColor)
                    .padding(6)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .overlay(alignment: .topTrailing) {
            if isHovered && !isBeingDragged && !isSelected {
                removeButton.padding(6).transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isBeingDragged, !didJustDrag else { return }
            onOpen()
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
        }
    }

    @ViewBuilder
    private var cellBackground: some View {
        if isMediaLike {
            Color.black.opacity(0.35)
        } else {
            UITokens.surfaceCard
        }
    }

    @ViewBuilder
    private var content: some View {
        switch highlight.highlightType {
        case "screenshot", "recording":
            ImageThumbnail(highlight: highlight)
        case "file":
            FileThumbnail(highlight: highlight)
        case "highlight":
            TextBody(highlight: highlight, accent: Color.orange.opacity(0.8))
        case "note":
            TextBody(highlight: highlight, accent: nil)
        default:
            if highlight.isURLCopy {
                LinkThumbnail(highlight: highlight)
            } else {
                TextBody(highlight: highlight, accent: Color.primary.opacity(0.14))
            }
        }
    }

    /// Footer row that floats over every card, with a subtle gradient
    /// scrim for media cards so the timestamp stays legible. Shows the
    /// most-recent userNote for any item that has one — media OR text —
    /// so a stack always surfaces whatever commentary the user attached.
    @ViewBuilder
    private var bottomOverlay: some View {
        VStack(spacing: 4) {
            if let annotation = highlight.userNote,
               !annotation.isEmpty,
               !annotationDuplicatesContent {
                Text(annotation)
                    .font(.system(size: 11, design: .serif))
                    .foregroundStyle(annotationForeground)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 6) {
                AddToStackButton(highlightId: highlight.id)
                    .colorScheme(isMediaLike ? .dark : .light)
                Spacer(minLength: 4)
                Text(CardMetadata.timeAgo(from: highlight.date))
                    .font(.caption2)
                    .foregroundStyle(isMediaLike ? Color.white.opacity(0.85) : Color.secondary.opacity(0.7))
                if noteCount > 1 {
                    Text("+\(noteCount - 1)")
                        .font(.caption2)
                        .foregroundStyle(isMediaLike ? .white.opacity(0.8) : .orange.opacity(0.8))
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(footerBackground)
    }

    private var annotationForeground: Color {
        isMediaLike ? Color.white.opacity(0.95) : Color.primary.opacity(0.78)
    }

    /// For note/highlight/text captures the contentText IS the user's
    /// writing — we already render it in the body, so repeating it in
    /// the footer would just waste the whole bottom of the card.
    private var annotationDuplicatesContent: Bool {
        switch highlight.highlightType {
        case "highlight", "note":
            return true
        case "screenshot", "recording", "file":
            return false
        default:
            return !highlight.isURLCopy
        }
    }

    @ViewBuilder
    private var footerBackground: some View {
        if isMediaLike {
            LinearGradient(
                colors: [.clear, .black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            Color.clear
        }
    }

    private var isMediaLike: Bool {
        switch highlight.highlightType {
        case "screenshot", "recording", "file":
            return true
        default:
            return highlight.isURLCopy
        }
    }

    private var removeButton: some View {
        Button(action: onRemove) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.white, .black.opacity(0.55))
        }
        .buttonStyle(.plain)
        .help("Remove from stack")
    }
}

// The list-row component (and its leading thumbnails for media/file/link
// captures) live in `MaterialListRow.swift` so the same row renders in
// both this view and the All-view archive list.

// MARK: - Per-type content (fill whatever cell the grid provides)

/// Inline readable text for `highlight`, `note`, and text captures.
/// The card fills whatever box the grid gives it; the text fits as
/// many lines as will fit, truncating with an ellipsis. The leading
/// accent bar mirrors the mosaic TextCard / HighlightCard styling so
/// the two surfaces read as the same family.
private struct TextBody: View {
    let highlight: Highlight
    let accent: Color?

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if let accent {
                RoundedRectangle(cornerRadius: 1)
                    .fill(accent)
                    .frame(width: 3)
            }
            Text(text)
                .font(.system(size: 13, design: .serif))
                .foregroundStyle(.primary.opacity(0.88))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 38)  // leave room for footer overlay
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var text: String {
        let trimmed = highlight.contentText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "(empty)" : trimmed
    }
}

// MARK: - Substack tile

/// One substack inside a parent's detail view. Reuses the canonical
/// `StackCard` tile so nested stacks look and feel like any other stack
/// — name, mosaic, item count. A hover detach badge lets the user
/// unlink the relationship without deleting the child itself.
private struct SubstackTile: View {
    let child: Stack
    let parentId: String
    let onOpen: () -> Void

    @State private var isHovered = false
    private let db = DatabaseManager.shared

    var body: some View {
        StackCard(
            stack: child,
            isPinned: child.isPinned,
            onTap: onOpen
        )
        .overlay(alignment: .topTrailing) {
            if isHovered {
                SubstackDetachBadge {
                    db.removeSubstack(child.id, fromStack: parentId)
                }
                .offset(x: 6, y: -6)
                .transition(.opacity)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
        }
    }
}

/// Top-trailing badge that removes the parent↔child `stack_stack` row.
/// The child stack itself is untouched — it remains top-level and any
/// other parents stay attached. Mirrors `StackUnpinBadge` in shape.
private struct SubstackDetachBadge: View {
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(isHovered ? .white : .white.opacity(0.9))
                .frame(width: 18, height: 18)
                .background(
                    Circle().fill(
                        isHovered
                            ? Color.red.opacity(0.85)
                            : Color.black.opacity(0.55)
                    )
                )
                .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .help("Detach this substack (the stack itself is kept)")
    }
}

// MARK: - Substack picker

/// A sheet for attaching an existing stack as a substack of the current
/// one. Lists every other stack with a live filter. Self and already-attached
/// children are disabled rather than hidden so the user can see the
/// full inventory and understand why they can't re-pick something.
private struct SubstackPickerSheet: View {
    let parentId: String
    let existingChildIds: Set<String>
    let onPick: (Stack) -> Void
    let onCancel: () -> Void

    @State private var candidates: [Stack] = []
    @State private var searchText = ""

    private let db = DatabaseManager.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            list
            Divider().opacity(0.5)
            footer
        }
        .frame(minWidth: 420, idealWidth: 480, minHeight: 420, idealHeight: 520)
        .background(UITokens.surfaceBackground)
        .onAppear(perform: reload)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Add substack")
                .font(.system(size: 15, weight: .semibold))
            Text("Pick an existing stack to attach as a child of this one. Items stay where they are.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                TextField("Search stacks…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(UITokens.surfaceCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(UITokens.surfaceBorder, lineWidth: 0.5)
            )
            .padding(.top, 4)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(filteredCandidates) { stack in
                    row(for: stack)
                    Divider().opacity(0.3)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func row(for stack: Stack) -> some View {
        let isSelf = stack.id == parentId
        let alreadyChild = existingChildIds.contains(stack.id)
        let disabled = isSelf || alreadyChild
        let statusText: String? = {
            if isSelf { return "This stack" }
            if alreadyChild { return "Already attached" }
            return nil
        }()
        return Button {
            guard !disabled else { return }
            onPick(stack)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(disabled ? Color.secondary.opacity(0.4) : Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(stack.isNamed ? (stack.name ?? "") : "Unnamed stack")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(disabled ? .secondary : .primary)
                        .lineLimit(1)
                    if let status = statusText {
                        Text(status)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    } else if let desc = stack.stackDescription,
                              !desc.isEmpty {
                        Text(desc)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Text("\(db.itemCountForStack(stackId: stack.id))")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.55 : 1)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var filteredCandidates: [Stack] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return candidates }
        return candidates.filter { stack in
            guard let name = stack.name else { return false }
            return name.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private func reload() {
        candidates = db.allStacks()
    }
}

