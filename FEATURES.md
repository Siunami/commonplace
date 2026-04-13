# Commonplace — Feature Overview

## Capture Methods

### Screenshots (Cmd+Shift+3 / Cmd+Shift+4)
Overrides macOS default screenshot shortcuts. Full-screen captures the active display; region shows a crosshair overlay for selecting an area. Images saved as PNG to app storage. OCR runs automatically on every screenshot using Vision framework — extracted text is stored and searchable. Metadata captured: source app, window title, URL, display info.

### Screen Recording (Cmd+Shift+5)
Overrides macOS default. Shows a floating toolbar with Full Screen / Region toggle, audio on/off, and a Record button. Region mode lets you select an area with a dim overlay. Records H.264 MOV via ScreenCaptureKit. Max duration: 10 minutes (auto-stops). Generates a thumbnail from the first frame. A recording indicator with elapsed timer appears at the top of the screen.

### Clipboard Monitoring (automatic)
Polls the system clipboard every 0.5 seconds. When new text is copied, it's saved with context (source app, window title, URL). Deduplicates consecutive identical copies. Also logs copies to a daily markdown file (`links/YYYY-MM-DD.md`).

### File/Download Monitoring (automatic)
Watches `~/Downloads` (default) plus any user-configured folders. Detects new files via DispatchSource directory monitoring. Waits for files to finish downloading (3-second size-stability check, skips `.crdownload`, `.part`, `.tmp`, etc.). Copies files to persistent app storage. Generates QuickLook thumbnails. Categorizes by content type (pdf, image, video, audio, archive, code, etc.).

### Quick Notes (Ctrl+Cmd+N)
Floating mini-window for typing a note. Cmd+Return to save, Esc to dismiss. Notes appear in the timeline alongside other captures.

### macOS Services ("Clip to Capture")
Right-click selected text or image in any app → Services → "Clip to Capture". Saves to the capture database with source context.

---

## Browsing & Viewing

### Menu Bar Icon
Camera viewfinder icon in the menu bar. Single click opens the Browse window.

### Browse Window (Ctrl+Cmd+B)
Main dashboard. Opens at 95% of screen size. Has six view modes:

- **Day** (default): Masonry grid of today's captures with date navigation arrows
- **All Grouped**: All captures grouped by date sections
- **All Ungrouped**: Flat masonry feed, paginated (200 per page)
- **Patterns**: Captures clustered by context or session (see Pattern Engine below)
- **Timeline**: Browsing history with page visits, durations, bookmarks
- **Smart Folders**: Saved filter views

All modes share:
- **Type filter pills**: All, Screenshots, Recordings, Copies, Notes, Files
- **Tag filter**: Filter by one or more tags
- **Search**: Full-text across content, OCR text, source app, URL, window title, notes, file names, tag names
- **Card detail**: Click any card → sheet with full content, metadata, notes timeline, related captures, action buttons (Copy, Show in Finder, Open URL)

### Clipboard History Panel (Ctrl+Cmd+V)
Floating panel showing recent clipboard entries. Click an entry to restore it to the clipboard.

### Toast Notification
Appears in the bottom-right corner after every capture. Shows a thumbnail (for images) or text preview. Auto-dismisses after 8 seconds. Hover pauses the timer. Click to expand into a full annotation window.

### Annotation Window
Opens when you click the toast. Proper window with title bar. Shows the captured image or text prominently. Bottom bar has: note field with voice transcription, copy/finder icon buttons, tag input, Done button. Esc or close button to dismiss.

---

## Data & Intelligence

### Storage
SQLite database via GRDB at `~/Library/Application Support/com.dubberly.Capture/`. Subdirectories: `screenshots/`, `recordings/`, `files/`, `thumbnails/`, `links/`. Crash recovery: backs up corrupt databases and starts fresh. Daily maintenance: WAL checkpoint + integrity check. Disk usage warning at 2 GB.

### Capture Metadata
Every capture records: timestamp, content hash, source app, window title, bundle ID, source URL, document path, content type, display name, display resolution, appearance mode (light/dark), WiFi network.

### Tags
User-created tags on any capture. Tag input with autocomplete in the annotation window and Browse detail view. Filter by tags in the Browse window.

### Smart Folders
Saved filter queries. Predicates: source app, URL, window title, bundle ID, capture type, content type, WiFi network, display name, appearance mode, tags. Operators: equals, contains, startsWith, isEmpty, isNotEmpty.

### Pattern Engine
Post-hoc analysis on captures, displayed in the Patterns view mode:
- **Context Clustering**: Groups consecutive captures by (app, URL domain) within 60-minute gaps
- **Session Detection**: Splits capture timeline by 30+ minute gaps; shows time range and app summary
- **Linked Captures**: Groups captures from the same app within 5 seconds with different types (e.g., a copy + screenshot together)

App facet sidebar filters patterns by source app.

### Browsing Timeline
Passive tab tracking — polls the active browser tab every 3 seconds via Accessibility/AppleScript. Records page visits with URL, title, domain, start/end time, duration. Correlates captures with active page visits (capture count on each visit).

### Chrome History Import
Imports browsing history and bookmarks from Chrome's local database. Runs at startup and every 5 minutes (history) / 30 minutes (bookmarks). Incremental — tracks last imported timestamp.

### OCR
Runs automatically on every screenshot. Vision framework with accurate recognition and language correction. Filters UI text (menus, buttons) and low-confidence results. Excludes status bar and dock regions. Extracted text is stored in the database and included in search.

### Voice Annotation
Available in the annotation window. On-device speech recognition (no network). Real-time audio level visualization. Max 60 seconds. Requires microphone + speech recognition permissions.

---

## System Integration

### Hotkey Override & Recovery
Overrides Cmd+Shift+3/4/5 with Carbon Event Manager. On exit, restores macOS defaults. Crash recovery: signal handlers (SIGTERM, SIGINT, SIGABRT, etc.), atexit hook, uncaught exception handler, and a watchdog background process that monitors the app PID and restores hotkeys if it dies unexpectedly (handles SIGKILL from Xcode).

### Launch at Login
Toggle in Settings. Uses ServiceManagement (SMAppService). App starts minimized.

### Permissions Required
- **Screen Recording**: For screenshots and screen recording (ScreenCaptureKit)
- **Accessibility**: For browser tab tracking
- **Microphone**: For voice annotation
- **Speech Recognition**: For voice-to-text transcription

---

## Settings

- Launch at Login toggle
- Database storage path (read-only)
- Watched Folders: list of monitored directories with add/remove
- Shortcuts reference (read-only)

---

## Hotkey Reference

| Action | Shortcut |
|---|---|
| Full-screen screenshot | Cmd+Shift+3 |
| Region screenshot | Cmd+Shift+4 |
| Recording toolbar | Cmd+Shift+5 |
| Clipboard panel | Ctrl+Cmd+V |
| Browse window | Ctrl+Cmd+B |
| Quick note | Ctrl+Cmd+N |
