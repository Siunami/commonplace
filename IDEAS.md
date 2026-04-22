# Ideas for later

Sketched-out directions that aren't built (or were built, stripped out, and parked here for later). The goal of this file is to hold the *idea* so it isn't lost — not to commit to shipping it.

Longer specs live under `ideas/` as their own files; this file stays the human-readable index with a short summary per entry. Inline ideas below are fine as-is until they grow enough to warrant a dedicated file.

---

## Design principles

Capture was never the hard part. **Retrieval is the most important part** — and specifically, how do you want to retrieve things?

- **Organization is sacred.** Each person has different grooves in their head, different latticeworks and models of reality. If you create a space that doesn't map to how they think, it won't feel like theirs. The choice to put objects in relation to each other is a deeply personal task.
- **Do as much as possible upfront** so the tool feels magical — but carefully. Too much and it feels like overstepping. Connections are fragile.
- **AI-synthesized dailys don't resonate** because the user didn't choose the organization. They don't recognize their own thinking in it.
- **Bootstrap off user actions.** Any action a user takes to organize things (moving into folders, tagging, grouping) reveals what they care about. Learn from that, don't impose.
- **Metadata already creates categories** — smart folders are just surfacing what's already there.
- **AI suggestion works for obvious categories** and semantic similarity (low-stakes taste questions). It feels noisy for subtle or personal organization.
- **Build trust with any recommender.** Show what it will do AND what it won't do.
- **Capture is easy. Retrieval is what's worth sharing.** Not everything is meant to be shared — only content in collections.

---

## Stacks

Small groups of content woven together — not full categories, but clusters that *could* become a category. A way to loosely associate 2-5 captures that feel related without committing to a named collection.

Use cases:
- Quickly group a few screenshots from the same research thread
- Bundle a link + a copy + a screenshot that all relate to the same idea
- Lightweight precursor to a collection — "these go together but I don't know what to call it yet"

Design questions:
- How do you create a stack? Select multiple items and group?
- Do stacks live in the sidebar or just as visual clusters in the grid?
- Can a stack be promoted to a collection with one action?
- Can AI suggest stacks based on temporal/semantic proximity?

## Batch organization

Fast ways to select many items and move them into a category. Label many things at once rather than one at a time. The current one-by-one tagging flow is too slow for large backlogs.

Ideas:
- Multi-select mode (shift-click, drag-select) → batch tag/move
- "More like this" — select one item, surface similar ones, bulk-add to collection
- Auto-suggest: when a user adds items to a collection, suggest other items that match the emerging pattern

---

## Pattern engine

Post-hoc analysis layered on the capture stream, surfaced as a separate view in Browse:

- **Context clusters** — consecutive captures from the same (app, URL domain) within a ~60-minute window, grouped into a single pattern.
- **Sessions** — the capture timeline split by 30+ minute idle gaps; each session shows its time range and the apps that dominated it.
- **Linked captures** — captures from the same app within ~5 seconds with different types (e.g. a copy + screenshot together), likely part of the same thought.

The stripped-out `PatternEngine.swift` had these computed on demand. Shipping it again would mean bringing back a Patterns view tab and wiring the engine to today's highlight store.

## Browsing timeline

Passive tab tracking that polls the active browser tab every few seconds (Accessibility / AppleScript) and records page visits: URL, title, domain, start/end, duration. Correlates with captures so you see "this copy happened while you were on X."

Stripped out because nothing surfaced the data in the UI. Would come back as a Timeline view mode showing page visits inline with captures.

## Chrome history import

Reads Chrome's local history + bookmarks database and imports visits on a schedule (history every few minutes, bookmarks every half hour). Incremental — tracks last-imported timestamp.

Stripped out alongside browsing timeline since the two share storage and no UI consumed either.

## Smart folders

Saved filter queries with boolean-combinable predicates: source app, URL, window title, bundle ID, capture type, content type, WiFi network, display name, appearance mode, tags. Persistent shortcuts that show up in the sidebar.

The views (`SmartFolderList`, `SmartFolderCreator`) and the storage (`SavedFilter` model + DB table) were written but never mounted. The DB table remains in migrations so old installs don't break.

## Multiple view modes

Right now Browse is one flat masonry grid. Ideas that were written into docs but not code:

- **Day** — today's captures with date navigation arrows
- **All grouped** — all captures, grouped by date sections
- **Patterns** — cluster/session view (see above)
- **Timeline** — page visits interleaved with captures (see above)

## Screen recording (Cmd+Shift+5)

Overrides macOS's recording shortcut. Floating toolbar with full-screen vs. region, audio on/off, and record. ScreenCaptureKit → H.264 MOV with a 10-minute cap, thumbnail from first frame, live elapsed timer at the top of the screen.

The capture code (`ScreenRecordingCapture.swift`, `RecordingToolbarWindow.swift`) was removed. Viewing legacy recordings still works — the `RecordingRecord` model and `recording(byId:)` lookup are kept so old rows render in Browse.

## Semantic search

Retrieval today is keyword across `contentText`, OCR text, URLs, window titles, notes, and tags. The "that Figma thing from last week about onboarding" query doesn't match literal tokens and silently fails.

Local embeddings (on-device, e.g. via Core ML or a quantized sentence model) over OCR + clipboard + notes would unlock fuzzy retrieval. The hard part is staying cheap: embed on capture, cache, only re-embed on edits.

## Proactive patterns in Day view

Day view currently leads with a flat grid. A sharper version: summarize today's sessions and clusters at the top ("you spent 45 min across X and Y, captured 12 things"), then the grid below. Makes the Pattern Engine the default story of the day instead of a tab you click into.

## Signal-weighted ranking

Re-access, dwell time, annotation, and tagging are strong "this mattered" signals. Use them to rank search results and fade unannotated noise. Combined with semantic search this starts to feel like actual memory retrieval instead of a reverse-chronological log.

## Permissions onboarding with Permiso

Reference: https://github.com/zats/permiso — a macOS library for accessibility permission dialogs (seen in Codex Computer Use). Could replace or improve the current `PermissionsSetupView` with a more polished, system-native permission request flow.

**Current state:** We have a custom `PermissionsSetupView.swift` that shows permission cards with live polling. It works but is hand-rolled.

**Implementation difficulty: Low.** Permiso is a small, focused library. Integration would mean:
1. Add the SPM dependency
2. Replace the manual `AXIsProcessTrusted()` polling + "Open Settings" button with Permiso's dialog
3. Keep the Screen Recording permission handling as-is (Permiso focuses on Accessibility)
4. ~1-2 hours of work, mostly UI replacement

The bigger win might come if Permiso handles edge cases we don't (permission revocation detection, system settings deep-linking on newer macOS versions, etc.).

## DMG distribution

Packaging Commonplace as a `.dmg` for distribution outside the Mac App Store. Right now the app only runs from Xcode's build directory.

**Implementation difficulty: Medium.** Steps:
1. Set up code signing with a Developer ID certificate (not just the dev cert)
2. Enable Hardened Runtime in build settings
3. Notarize the app with `notarytool` (Apple requirement for non-App Store distribution)
4. Create the DMG using `create-dmg` (CLI tool) or `hdiutil` with a background image and Applications symlink
5. Add a CI/build script to automate: archive → sign → notarize → package DMG

Tools: `create-dmg` (npm), `SwiftyDMG` (Swift), or raw `hdiutil` + `osascript`. The notarization step is the main friction — requires an Apple Developer account ($99/yr) and waiting for Apple's servers.

Entitlements to audit: Screen Recording, Accessibility, and the CGEvent tap all need specific entitlements that work under Hardened Runtime. The current development build skips these checks.

## Claude ↔ archive bridge

A CLI (`cp-ai`) that gives Claude Code full *read* access to the Commonplace archive and a structured way to propose organization — tags, collections, links, notes — without ever mutating the curated data. Two-DB split: main is opened read-only at the SQLite URI level (`?mode=ro`, a physical guarantee), while Claude writes into a separate `claude-suggestions.sqlite`. The only command that touches main is a user-invoked `accept`, so the user stays the sole writer into their own archive.

Full spec: [ideas/claude-archive-cli.md](ideas/claude-archive-cli.md).

## Per-app deeplink enrichers

Upgrade the mosaic top-right pill so captures from Notes, Linear, Mail, Things, Notion open the *specific* note / issue / message — not just launch the source app. Infrastructure (`SourceEnricher`, `SourceContextEntry.url`, `MasonryCard.sourceLink`) already wires this up; each app just needs its own enricher. HTML-pasteboard and window-title paths are safe; AppleScript-based ones (Notes, Mail, Things) trigger macOS automation permission prompts per app — not a blocker, but the reason this is parked for now.

Full spec: [ideas/per-app-deeplink-enrichers.md](ideas/per-app-deeplink-enrichers.md).
