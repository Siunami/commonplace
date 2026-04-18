# Ideas for later

Sketched-out directions that aren't built (or were built, stripped out, and parked here for later). The goal of this file is to hold the *idea* so it isn't lost — not to commit to shipping it.

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
