# Claude ↔ Commonplace archive bridge

A safe way to let Claude Code (and other LLM agents) read the full Commonplace archive, spot patterns across it, and propose organization without ever mutating the user's curated data.

## Why

Capture is the easy part. Retrieval — and the sense-making layered on top — is what makes an archive worth keeping. LLMs are unusually good at that layer: noticing that three screenshots from last month are all about the same half-formed idea, surfacing a link between an article and a copy snippet from two weeks earlier, proposing a tag that already describes a dozen highlights.

What LLMs are *not* good at is being trusted with write access to a personal archive. Hallucinated tags, accidental bulk edits, or "helpful" schema migrations would destroy the one thing the archive has going for it: the user recognizes their own thinking in it. **AI-synthesized organization doesn't resonate when the user didn't choose it** (see IDEAS.md § Design principles).

This spec is how we give Claude full read access and a structured way to *suggest*, while keeping the user the only writer into the main archive.

## Principles

1. **Two-DB split with asymmetric access.** Claude reads main, writes only into its own suggestions DB.
2. **LLM output is proposals; humans are the only writers into main.** Every change to the curated archive passes through a human `accept`.
3. **Main DB schema is never touched by Claude tooling.** Not even additive columns. The bridge lives entirely outside the app's storage contract.
4. **Physical guarantees over conventions.** "Don't write to main" is enforced by how the connection is opened, not by discipline.
5. **Full audit trail.** Every suggestion, acceptance, and rollback is logged so a bulk mistake can be inverse-applied.

## Architecture

```
                  ┌──────────────────────────┐
                  │   main Commonplace DB    │
                  │   (SQLite)               │
                  │   opened read-only       │  ← Claude never writes here
                  └───────────▲──────────────┘
                              │ read
                              │
            ┌─────────────────┴─────────────────┐
            │          cp-ai CLI                │
            │  (shell wrapper around sqlite3    │
            │   + small helpers)                │
            └─────┬─────────────────────────▲───┘
                  │ write                   │ read
                  │                         │
                  ▼                         │
       ┌──────────────────────────┐         │
       │  claude-suggestions.db   │─────────┘
       │  (Claude-owned SQLite)   │
       │  proposals + notes       │
       └──────────────────────────┘
                  │
                  │ accept / reject
                  ▼
            human review → writes into main
```

- **Main DB** is opened via a `file:...?mode=ro` URI. This is a SQLite-level guarantee: even a buggy `UPDATE` fails at the driver, not at a check-we-wrote.
- **`claude-suggestions.sqlite`** lives next to the main DB (or under `~/Library/Application Support/Commonplace/`, TBD). Claude owns it — schema, migrations, and retention are not the main app's concern.
- **No foreign keys into main.** Suggestions reference main rows by stable highlight ID (string), so the two DBs can diverge in either direction without the bridge breaking.

## Suggestions DB schema

```sql
CREATE TABLE suggestions (
  id                   INTEGER PRIMARY KEY,
  created_at           TEXT NOT NULL,           -- ISO8601
  type                 TEXT NOT NULL,           -- 'tag' | 'collection' | 'link' | 'note'
  target_highlight_id  TEXT,                    -- nullable for collection-level suggestions
  payload_json         TEXT NOT NULL,           -- type-specific structured data
  reason               TEXT,                    -- Claude's rationale, free text
  status               TEXT NOT NULL DEFAULT 'pending',
                                                -- 'pending' | 'accepted' | 'rejected' | 'rolled_back'
  reviewed_at          TEXT
);

CREATE INDEX idx_suggestions_status ON suggestions(status);
CREATE INDEX idx_suggestions_target ON suggestions(target_highlight_id);

CREATE TABLE claude_notes (
  id            INTEGER PRIMARY KEY,
  highlight_id  TEXT NOT NULL,
  note          TEXT NOT NULL,
  created_at    TEXT NOT NULL
);
```

`payload_json` shape by type:

- `tag` → `{ "tag": "onboarding-research" }`
- `collection` → `{ "name": "Figma onboarding", "item_ids": ["h_123", "h_456"] }`
- `link` → `{ "from_id": "h_123", "to_id": "h_456", "relation": "follow-up-to" }`
- `note` → duplicated in `claude_notes`; `payload_json` mirrors `{ "note": "..." }` for uniform review UI.

## CLI surface (`cp-ai`)

Read-only against main:

- `cp-ai query "SELECT ... FROM highlights WHERE ..."` — raw SQL, connection forced to `?mode=ro`.
- `cp-ai search "onboarding"` — convenience wrapper over common searches (content text, OCR text, URLs, window titles).
- `cp-ai list-highlights [--since DATE] [--app BUNDLE] [--limit N]` — recent captures, filtered.
- `cp-ai list-collections` — existing tags / collections, for Claude to check before proposing new ones.

Proposal commands (write only to suggestions DB):

- `cp-ai suggest tag <highlight-id> <tag> --reason "..."`
- `cp-ai suggest collection <name> --items <id,id,...> --reason "..."`
- `cp-ai suggest link <id-a> <id-b> --relation "..." --reason "..."`
- `cp-ai note <highlight-id> "free text"`

Human review:

- `cp-ai pending [--type tag|collection|link]` — human-readable list with IDs, targets, and reasons.
- `cp-ai accept <suggestion-id>` — user-invoked; the **only** command that writes to main. Opens main read-write, applies the change, marks the suggestion `accepted`.
- `cp-ai reject <suggestion-id>` — marks `rejected`, no main-DB writes.

## Rollout

**Phase 1 — shell wrapper + docs.** `scripts/cp-ai` is a thin shell/Swift script that shells out to `sqlite3` with the right URI for reads and opens the suggestions DB for writes. A `CLAUDE.md` at project root documents:

- main DB path and schema (generated, not hand-maintained)
- suggestions DB schema
- safety rules ("never open main without `?mode=ro`", "never `DELETE FROM` anything in main, ever")
- example `cp-ai` session

No Swift app changes. No new build target. Claude + a terminal is the whole surface.

**Phase 2 (optional, later).** The Commonplace app reads `claude-suggestions.sqlite` and surfaces pending items in a dedicated sidebar section with one-click accept/reject. At that point `cp-ai accept` and the UI button call into the same code path.

## Safety

- **Main DB opened read-only at the URI level.** `file:...?mode=ro` is enforced by SQLite itself — even a bug in `cp-ai` can't mutate main.
- **`accept` is the only write path into main**, and it's user-invoked. There is no batch-accept-everything command in Phase 1 on purpose.
- **`rolled_back` status** lets us inverse-apply a suggestion if a bulk accept turns out badly. The audit trail in `suggestions` is enough to reconstruct what changed.
- **No destructive suggestion types.** `cp-ai` can suggest *adding* tags, collections, links, and notes. It cannot suggest removing or renaming. Destructive curation stays a human-only action.
- **Full audit trail** lives in the suggestions DB: who (Claude vs human), when, why, and outcome for every proposal.

## Open questions

- **Do suggestions expire if ignored?** A 30-day `pending` TTL keeps the review queue from becoming infinite, but risks losing slow-burn good ideas. Probably: surface "stale" pending items separately rather than auto-rejecting.
- **External CLI vs in-process.** Should `cp-ai` run inside Commonplace's process (richer typing, reuses the DB layer, shared models) or stay external (simpler, language-agnostic, works even when the app is closed)? Phase 1 is external; Phase 2 may justify moving in-process.
- **Orphaned suggestions.** What happens to a pending suggestion whose `target_highlight_id` has been deleted from main? Options: auto-reject on next `pending`, surface as "orphaned" with a different status, or leave as-is and let the user reject manually.
- **Multi-agent concurrency.** If two Claude sessions run `cp-ai suggest` at once, is SQLite's default locking enough? Almost certainly yes at this scale, but worth noting.
- **Scope of `accept`.** Does `accept` on a `collection` suggestion create the collection *and* add every item, or just create the empty collection? Probably the former, but it's the one `accept` path that materially changes many rows at once.
