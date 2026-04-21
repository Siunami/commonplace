# AI suggestions for Stacks

How AI can help with stacks without breaking their provisional, low-commitment feel. This is a follow-up to the Stacks feature spec (`.context/attachments/Stacks - by Matthew Siu - Notebook.pdf`), which names this as an open question on page 8.

## Design constraint — keep stacks provisional

Stacks' whole charm is that they're low-commitment. A pushy "you should stack these!" banner breaks the feel. Any AI surface must stay *ambient*: ghost cards, dimmed affordances, dismissible in one click, never modal, never a notification. Suggestions are an extra browse target, not a task.

This also dovetails with the principle from `claude-archive-cli.md`: **AI-synthesized organization doesn't resonate when the user didn't choose it.** Suggestions propose; the user is the only writer.

## Two axes of suggestion

1. **Suggest items for an existing stack** — Spotify "add to playlist" pattern. Low stakes: the stack exists, the user is already curating.
2. **Suggest entire stacks** from the archive — higher value, higher noise risk. A bad cluster is clutter; a good one is a gift.

Also worth considering downstream:
- **Name suggestion** for unnamed stacks — attacks the unnamed → named friction point directly.
- **Merge detection** — "Stacks A and B look like the same thing."
- **Split detection** — "This stack has two themes; want to split?"

## Ladder of approaches, cheapest → richest

### 1. Heuristics (free, local, deterministic)
- **Burst detection.** If the user captures ≥N items within a short window (e.g. 5 in 10 minutes), offer to auto-stack them. Pure timestamp math.
- **Same-source clustering.** Same domain, same app, same file-monitor source in a session.
- **Tag / collection overlap.** Items that already share tags are stack candidates.

Good first move because it requires no ML, no embeddings, no remote calls. Fits the existing `Highlight` model directly.

### 2. Embeddings (moderate, local)
- Vector similarity over capture text / OCR / titles to power "items like what's already in this stack."
- Feels Spotify-like and is the most natural fit for the pinned-stack detail view: a dimmed row at the bottom labeled "Related from your archive."
- Can also power merge detection (stack-to-stack similarity) and pivot-point strength (how strongly an item belongs to multiple stacks).
- Local embedding models keep this private and free at inference time. Ingestion cost is a one-time per-highlight pass.

### 3. LLM (remote, expensive, best for language tasks)
Two sweet spots where LLMs specifically outperform heuristics + embeddings:
- **Naming unnamed stacks.** "This stack looks about 'X', want to name it?" Directly attacks the unnamed → named friction point from the spec.
- **Thematic grouping.** Given a bag of archive items, propose candidate *named* stacks with rationale. Higher noise, but the naming is the value-add.

Per `claude-archive-cli.md`, any LLM output lives in a separate suggestions DB — the main archive is never mutated by the model.

## Recommended first move

**Spotify-style "suggested items" row at the bottom of the pinned-stack detail view**, powered by embeddings + recency.

Why this first:
- Maps to a pattern users already understand.
- Honors provisionality — suggestions don't commit anything.
- Uses signals we can compute locally.
- No LLM round-trip, so no remote dependency for v1.
- Integrates with the existing stack detail view; no new surface to design.

Rough shape:
- At the bottom of `StackDetailView`, a dimmed "Related" row.
- Query: average the embeddings of items already in the stack → nearest K unstacked items from the archive.
- Each suggested item has a one-tap "add" affordance; tapping the item itself just opens it (browse, not commit).
- Dismissed suggestions are remembered so they don't reappear in the same stack.

## Second move

**Burst-detection stacks** — cheapest possible way to *propose a new stack* without LLM risk.

- Background job: when N captures land within window W and nothing is currently pinned, offer "Stack these N items?" as a lightweight toast / archive card.
- Accept → creates an unnamed stack and pins it. Dismiss → never ask about that burst again.
- Unit of trust is small: the user sees exactly what's being grouped.

## Third move

**LLM-generated name suggestions** for unnamed stacks once they have ≥3 items.

- Stack detail view shows a "Suggest name" affordance near the empty name field.
- LLM gets item titles + snippets, returns 2–3 candidate names + 1-line rationales.
- User picks one or ignores. Never applied automatically.

## Fourth move (ambitious)

**Full stack discovery** — LLM clusters the archive into candidate stacks on demand.

- Surfaced only when the user asks for it ("Suggest stacks"). Never proactive — the noise ratio is too high for an ambient surface.
- Each proposed cluster is a reviewable card: here's a name, a rationale, and the items. Accept builds the stack; reject kills the suggestion.

## Signals we already have

- `captured_at` → burst detection
- `source_url`, `source_app` → source clustering
- OCR / text / title fields → embeddings + LLM input
- Existing `highlight_tag` → tag-overlap heuristic
- New `highlight_stack` → stack-to-stack similarity for merge detection

## Open questions

- Where do embeddings live? New table, or co-located with `highlight`? How do we backfill historical items?
- Local embedding model choice — Apple's on-device models vs. a bundled ONNX model vs. a small local Python service.
- How is "dismissed suggestion" memory scoped — per stack, per item, global?
- Do suggested items count toward the 6-item mosaic on the pinned card? (Probably not — they're not *in* the stack yet.)
- If multiple stacks could claim an item, do we show that in the suggestion UI ("also suggested for Stack B")?

## Out of scope for v1

- Auto-applying any suggestion without user confirmation.
- Cross-user or cross-device learning.
- Realtime "as you capture" suggestions (nice-to-have, but adds latency + focus-stealing risk).
- Mutating the name/description of an existing stack without explicit user acceptance.
