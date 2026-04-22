# Per-app deeplink enrichers

## Context

After the mosaic pill shipped (URL / file / app-launch fallback), cards from non-browser apps only ever launch the source app — not the specific note, issue, or message. Upgrading those cases to real deeplinks would make the pill an actual navigation affordance for everything we capture, not just for web URLs.

The plumbing is already in place: `SourceEnricher` protocol, `SourceContextEntry` with a `url` field, and `MasonryCard.sourceLink` already consumes enricher URLs before other fallbacks. Shipped enrichers: Browser, Slack, Discord, Messages, Telegram.

Parked because each AppleScript-based enricher triggers a macOS automation permission prompt for the target app. Not a blocker, but enough friction that it shouldn't slip in without a deliberate UX pass.

## How an enricher works

### At capture time
`HighlightCapture` builds `RawCaptureInputs` (bundleId, windowTitle, pasteboard text/HTML/RTF). `SourceEnricherRegistry` dispatches to the first enricher matching the bundle id, on a background queue with a 300 ms hard budget. The enricher returns `[SourceContextEntry]` — each entry has a `key`, `label`, `value`, optional `icon`, and optional `url`. The array is JSON-encoded into `highlight.sourceContext`.

### At render time
`MasonryCard.sourceLink` picks the first `SourceContextEntry` with a non-nil `url`, falls back through `sourceUrl` → URL-copy `contentText` → file path → bare app launch. Each tier is independently valid — a failed enricher only means a weaker fallback is used.

## Durability — per extraction method

| Method | Breakage likelihood | Example |
|---|---|---|
| HTML pasteboard regex | Low — clipboard formats rarely change | Slack, Discord, Notion (potential) |
| Window title regex | Medium, but parse cost is ~zero | Linear (`TEAM-1234`) |
| AppleScript | Medium-high — Apple permissions / event dict changes | Notes, Mail, Things |
| AX tree read | Medium | Figma (deferred) |

HTML-pasteboard enrichers are the most durable. AppleScript is the fragile path — both across macOS versions *and* across per-user permission state.

## Safety

Every enricher is a pure `RawCaptureInputs → [SourceContextEntry]` function. Failures fold to `return []`. Blast radius is bounded by design:

- **Additive only.** Enrichers write to `sourceContext` (JSON sidecar). They never touch `contentText`, `sourceUrl`, or other highlight fields.
- **Pill validates.** `URL(string:)` + scheme check in `MasonryCard.sourceLink` means a malformed enricher URL falls through instead of crashing.
- **Per-bundle dispatch.** A buggy Notes enricher can't corrupt Slack captures.
- **Two-level timeouts.** Registry (300 ms) + per-enricher AppleScript call (200 ms).
- **Degrades gracefully on permission denial.** If the user declines automation permission, AppleScript returns nil → enricher returns `[]` → pill falls through to app-launch. Visible difference: pill says "Notes" instead of "My Note Title", and clicking opens Notes to wherever it was instead of the specific note.

### The one silent-wrong-behavior risk
An enricher could return a stale identifier — e.g., Notes front window isn't the one you copied from — and the pill would open the wrong note. Mitigation: for AppleScript-based enrichers, gate extraction on `inputs.windowTitle` matching the scripted front-window name. If mismatched, return `[]`.

### Backfill thundering herd
Registering a new enricher on launch would reprocess historical rows for its bundle(s) in one burst via `backfillSourceContextIfNeeded`. Before shipping any new enricher, throttle backfill to ~10 rows/sec for newly-supported bundles.

## Priority list

| App | Scheme | Extraction | Effort | Triggers permission prompt? |
|---|---|---|---|---|
| Linear | `https://linear.app/<org>/issue/<TEAM-1234>` | Regex window title | Low | No |
| Notion | `notion://www.notion.so/<page>` | HTML pasteboard regex | Medium | No |
| Apple Notes | `notes://showNote?identifier=<uuid>` | AppleScript | Medium | Yes |
| Apple Mail | `message://<messageID>` | AppleScript | Medium | Yes |
| Things 3 | `things:///show?id=<uuid>` | AppleScript | Low | Yes |
| Figma | `figma://file/<id>` | AX / pasteboard HTML | High | Maybe |

## Shipping plan

### Phase A — No new permissions required
Ship Linear + Notion. Pure pasteboard / window-title parsing, zero prompt surface.

### Phase B — Backfill throttling
Before any AppleScript enricher lands, throttle `backfillSourceContextIfNeeded` to ≤10 rows/sec for newly-supported bundles so a first-launch reprocess doesn't thundering-herd.

### Phase C — AppleScript-gated enrichers
Apple Notes, Apple Mail, Things 3 — one at a time, each with its own PR. Each enricher mirrors `MessagesSourceEnricher` but adds the active-window guard.

### Phase D — Permission UX
Before Phase C lands, design how we surface the permission prompts. Options:
- Ambient: let the system prompt fire on first copy from the app, accept the 200 ms stall.
- Opt-in: add a "Deeper integration with Notes / Mail / Things" setting that requests permission up front.

### Skip
- Messages / iMessage — no public deeplink scheme.
- Figma — deferred until a reliable ID-extraction path exists.

## Per-enricher checklist

1. New file under `Commonplace/Capture/Enrichers/<App>SourceEnricher.swift`
2. Mirror `SlackSourceEnricher` (HTML path) or `MessagesSourceEnricher` (AppleScript path)
3. Register in `CaptureApp.swift:45`
4. Fixture-based unit tests in `CommonplaceTests/` following the Slack/Discord pattern
5. For AppleScript enrichers: add the active-window guard
6. Manual verification: copy from the app → open Commonplace → hover the card → click the pill → confirm it opens the *specific* note/issue/message
