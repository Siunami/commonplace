# AGENTS.md

Notes for AI agents working in this repo. Human contributors should also read this — these are project-wide invariants, not agent-only rules.

## Screenshot hotkey override is a load-bearing invariant

**Cmd+Shift+3 and Cmd+Shift+4 MUST be intercepted by Commonplace at all times when the app is running with Accessibility permission.**

The app installs a `CGEvent.tapCreate` session tap in `Commonplace/Capture/ScreenshotShortcutHandler.swift` and consumes these key combos (returns `nil` from the callback) so macOS's built-in "screenshot to Desktop" flow never fires. Highlights must land in the Commonplace archive, not in `~/Desktop/Screenshot …png`.

### Do NOT

- Remove `case 20:` (Cmd+Shift+3 full screen) from the switch in `eventTapCallback`.
- Remove `case 21:` (Cmd+Shift+4 region) from the switch in `eventTapCallback`.
- Change `return nil` (which consumes the event) to `return Unmanaged.passRetained(event)` for either case — that would let the system screenshot flow run in parallel.
- Narrow the modifier guard in a way that lets either combo fall through to macOS. The current guard is `hasCmd && hasShift && !hasCtrl && !hasAlt`; keep it that way unless a new combo is being added.
- Weaken the `isInstalled` check back to `eventTap != nil`. It must call `CGEvent.tapIsEnabled(tap:)` so the onboarding verifier reports genuine enablement, not just tap creation.

### Do

- Cmd+Shift+5 (keyCode 23) deliberately falls through to the macOS Screenshot utility — leave it that way.
- If the tap is reported disabled (`tapDisabledByTimeout` / `tapDisabledByUserInput`), re-enable it in place. The existing callback already does this; preserve that behavior.
- Any regression that restores the system's default ⌘⇧3 / ⌘⇧4 handling is a bug. Treat it as a release blocker.

### Why this matters

Commonplace's entire capture model depends on screenshots landing in-app with their source-app context attached. Losing the override means users silently drop captures onto their Desktop and context is lost. This has regressed at least once before (Cmd+Shift+4 was accidentally deleted from the switch); re-adding it is the fix, not working around it.
