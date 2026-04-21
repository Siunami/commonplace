# Commonplace

![Commonplace](assets/Archive%20UI.png)

Commonplace is a macOS archive for the things you encounter while using your computer.

It captures screenshots, copied text, downloads, links, and notes, then keeps them in one browsable space. Instead of splitting reference material across folders, clipboard history, bookmarks, and notes apps, Commonplace treats them as part of the same working archive.

It is built for the stage before formal organization: when something feels worth keeping, but you do not yet know what it will become.

Runs in the menu bar, no dock icon. Requires macOS 15.6+.

## What it does differently

Most tools focus on one kind of saved material. Commonplace is built around the idea that screenshots, copied text, files, links, and notes often belong to the same stream of thought.

Commonplace lets you:

- capture what you see, copy, download, and jot down without deciding upfront where it belongs
- browse all of that material together in a single archive
- search across OCR text, copied content, URLs, apps, and window titles
- annotate and tag captures while the context is still fresh

The goal is not just to save things. It is to make them easier to revisit, connect, and reuse later.

## How it compares

**Screenshot tools** save images. Commonplace also captures copied text, downloads, links, and notes, so screenshots live alongside the rest of the material around them.

**Clipboard managers** keep history. Commonplace treats clipboard history as one input into a larger archive you can browse, search, annotate, and organize.

**Bookmark and read-later tools** save links. Commonplace keeps links together with screenshots, copied passages, files, and notes from the same working context.

**Notes apps** start with writing. Commonplace starts with capture. It is for collecting fragments before they become polished notes, documents, or projects.

## Core workflow

Everything lands in a single archive view. You can browse it as a visual grid, then filter by type, app, or tag, and search across content, OCR text, URLs, and window titles.

From the archive or any tagged view, the **+ Add** tile lets you type or paste, drag in a file or URL, or choose a file manually. New material lands directly in the space you are viewing.

Each capture also shows a toast notification. Click it to add a typed or voice note and apply tags while the capture is still fresh.

## Install

1. Download [`Commonplace.dmg`](https://github.com/Siunami/commonplace/releases/latest/download/Commonplace.dmg) from the [latest release](https://github.com/Siunami/commonplace/releases/latest)
2. Drag **Commonplace** to Applications
3. The app is not notarized yet, so macOS will block it. To open it:
   - **Right-click** the app → **Open** → click **Open** in the dialog, or
   - Run `xattr -cr /Applications/Commonplace.app` in Terminal
4. Grant Screen Recording and Accessibility when prompted

A camera icon appears in your menu bar. Click it to open the archive.

## Shortcuts

| Shortcut      | Action                       |
| ------------- | ---------------------------- |
| `Cmd+Shift+3` | Capture the current screen   |
| `Cmd+Shift+4` | Capture a selected region    |
| `Ctrl+Cmd+B`  | Open the archive             |

Clipboard copies and file downloads are captured automatically.

## Data

Commonplace stores its SQLite database at:

```
~/Library/Application Support/com.dubberly.Capture/
```

Everything stays on your Mac.

## Permissions

- **Screen Recording** — capture screenshots
- **Accessibility** — read source app and window metadata for copied content
- **Microphone + Speech Recognition** — record voice notes

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

See [`IDEAS.md`](IDEAS.md) for sketched-out features that are not built yet. Publishing to Cloudflare R2 is partially shipped and documented in [`FUTURE_CLOUDFLARE_SETUP.md`](FUTURE_CLOUDFLARE_SETUP.md).
