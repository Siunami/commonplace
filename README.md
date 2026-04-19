# Commonplace

![Commonplace](assets/Archive%20UI.png)

A macOS utility that captures what you see, copy, and save — screenshots, clipboard, downloads, notes — and keeps it browsable in one place.

Runs in the menu bar, no dock icon. Requires macOS 15.6+.

## Install

1. Download [`Commonplace.dmg`](https://github.com/Siunami/commonplace/releases/latest/download/Commonplace.dmg) from the [latest release](https://github.com/Siunami/commonplace/releases/latest)
2. Drag **Commonplace** to Applications
3. The app isn't notarized yet, so macOS will block it. To open it:
   - **Right-click** the app → **Open** → click **Open** in the dialog, or
   - Run `xattr -cr /Applications/Commonplace.app` in Terminal
4. Grant Screen Recording and Accessibility when prompted

A camera icon appears in your menu bar. Click it to open the archive.

## Shortcuts

| Shortcut      | What happens                  |
| ------------- | ----------------------------- |
| `Cmd+Shift+3` | Screenshot the current screen |
| `Cmd+Shift+4` | Screenshot a selected region  |
| `Ctrl+Cmd+B`  | Open the Browse window        |

Clipboard copies and file downloads are captured automatically.

## Archive

Everything lands in a single masonry grid. Filter by type, app, or tag; search across content, OCR text, URLs, and window titles. Click any card for full detail, notes, and metadata.

On the All view and inside any collection (tag) view, the top-left of the grid is a **+ Add** tile. Click to type or paste, drag a file or URL onto it, or use **choose** to pick a file — whatever you add lands in the space you're viewing (and inherits the collection's tag).

Every capture shows a toast in the corner — click it to annotate (typed or voice) and tag.

## Data

SQLite database at `~/Library/Application Support/com.dubberly.Capture/`. Everything stays on your Mac.

## Permissions

- **Screen Recording** — for screenshots
- **Accessibility** — for source-app / window metadata on copies
- **Microphone + Speech Recognition** — for voice notes (optional)

## Development

```bash
open Commonplace.xcodeproj
```

Build and run with Xcode. Targets macOS 15.6+.

### Release DMG

1. Xcode → Product → Archive → Distribute App → Developer ID
2. `./scripts/create-dmg.sh /path/to/exported/Commonplace.app`

Produces `build/Commonplace.dmg` with a drag-to-Applications layout.

---

See [`IDEAS.md`](IDEAS.md) for sketched-out features that aren't built yet. Publishing to Cloudflare R2 is a partially-shipped feature documented in [`FUTURE_CLOUDFLARE_SETUP.md`](FUTURE_CLOUDFLARE_SETUP.md).
