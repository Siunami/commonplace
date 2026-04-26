import AppKit
import CoreWLAN
import CryptoKit
import Foundation

/// Why a card is being written. Threaded into `HighlightCapture` so the
/// archive can answer "where did this come from?" without inferring it
/// from heuristics. V1 origins:
/// - `.captured`: arrived from outside (default — clipboard, screenshot,
///   file watcher, drag-import). Existing call sites all map to this.
/// - `.workspaceCreated`: authored inline in a workspace canvas. The
///   canvas writes both the highlight (with originType set) and the
///   placement at the click point.
/// - `.derived`: produced from a parent card (V1: text-excerpt only).
///   The parent's provenance is snapshotted into `inheritedProvenance`
///   at derive time so the derived card stays self-contained even if
///   the parent is later deleted.
enum OriginContext {
    case captured
    case workspaceCreated(workspaceId: String)
    case derived(parentCardId: String, range: NSRange)
}

struct CaptureContext {
    // App & window
    let windowTitle: String?
    let bundleId: String?
    let sourceUrl: String?
    let documentPath: String?
    let clipboardTypes: String?
    let sourceAppName: String?

    // Environment
    let displayName: String?
    let displayResolution: String?
    let appearanceMode: String?
    let wifiNetwork: String?

    // v21 per-app enricher output (JSON-encoded [SourceContextEntry])
    let sourceContext: String?

    static func current(frontApp: NSRunningApplication? = nil, captureClipboardTypes: Bool = false) -> CaptureContext {
        let frontApp = frontApp ?? NSWorkspace.shared.frontmostApplication
        let bundleId = frontApp?.bundleIdentifier
        let appName = frontApp?.localizedName
        let pid = frontApp?.processIdentifier
        let windowTitle = activeWindowTitle()
        let (documentPath, documentUrl) = activeDocumentInfo(pid: pid)

        // Pasteboard flavors — only read when this capture originates from
        // a clipboard/paste event. Reading pasteboard contents outside of a
        // copy event returns stale data which would just confuse enrichers.
        var pasteboardTypesRaw: [String] = []
        var pasteboardHTML: String? = nil
        var pasteboardRTF: String? = nil
        var pasteboardText: String? = nil
        if captureClipboardTypes {
            pasteboardTypesRaw = NSPasteboard.general.types?.map({ $0.rawValue }) ?? []
            pasteboardHTML = NSPasteboard.general.string(forType: .html)
            pasteboardText = NSPasteboard.general.string(forType: .string)
            if let rtfData = NSPasteboard.general.data(forType: .rtf),
               let attr = try? NSAttributedString(data: rtfData, options: [:], documentAttributes: nil) {
                pasteboardRTF = attr.string
            }
        }

        // Run the enricher registry before resolving sourceUrl so a
        // browser-enricher-supplied page_url can seed the field.
        let rawInputs = RawCaptureInputs(
            bundleId: bundleId,
            appName: appName,
            windowTitle: windowTitle,
            pid: pid,
            pasteboardTypes: pasteboardTypesRaw,
            pasteboardHTML: pasteboardHTML,
            pasteboardRTF: pasteboardRTF,
            pasteboardText: pasteboardText
        )
        let entries = SourceEnricherRegistry.shared.enrich(inputs: rawInputs)

        // Source URL precedence: enricher page_url → AX document URL.
        // The enricher already runs BrowserURLExtractor internally, so
        // re-invoking it here just doubled the AppleScript call and the
        // user-visible latency. AX document URL is synchronous and
        // covers the case where AppleScript times out but the browser
        // still exposes the URL through accessibility.
        var sourceUrl: String? = entries.first(where: { $0.key == "page_url" })?.url
        if sourceUrl == nil {
            sourceUrl = documentUrl
        }

        var clipboardTypesJSON: String? = nil
        if captureClipboardTypes, !pasteboardTypesRaw.isEmpty,
           let data = try? JSONSerialization.data(withJSONObject: pasteboardTypesRaw),
           let json = String(data: data, encoding: .utf8) {
            clipboardTypesJSON = json
        }

        var sourceContextJSON: String? = nil
        if !entries.isEmpty,
           let data = try? JSONEncoder().encode(entries),
           let json = String(data: data, encoding: .utf8) {
            sourceContextJSON = json
        }

        // Environment snapshot
        let screen = NSScreen.main
        let displayName = screen?.localizedName
        let displayResolution: String? = {
            guard let s = screen else { return nil }
            let w = Int(s.frame.width)
            let h = Int(s.frame.height)
            let scale = Int(s.backingScaleFactor)
            return "\(w)x\(h)@\(scale)x"
        }()
        let appearanceMode = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? "dark" : "light"
        let wifiNetwork = CWWiFiClient.shared().interface()?.ssid()

        return CaptureContext(
            windowTitle: windowTitle,
            bundleId: bundleId,
            sourceUrl: sourceUrl,
            documentPath: documentPath,
            clipboardTypes: clipboardTypesJSON,
            sourceAppName: appName,
            displayName: displayName,
            displayResolution: displayResolution,
            appearanceMode: appearanceMode,
            wifiNetwork: wifiNetwork,
            sourceContext: sourceContextJSON
        )
    }

    private static func activeWindowTitle() -> String? {
        // First try Accessibility API — gets the real document/tab title
        // (e.g., "On Self-Respect" in Bear, tab title in Chrome)
        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            let appElement = AXUIElementCreateApplication(pid)
            var focusedWindow: AnyObject?
            if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow) == .success,
               focusedWindow != nil {
                // AXUIElement is a CF type — `as!` is safe here because
                // AXUIElementCopyAttributeValue guarantees the type on .success
                let windowElement: AXUIElement = unsafeBitCast(focusedWindow, to: AXUIElement.self)
                var title: AnyObject?
                if AXUIElementCopyAttributeValue(windowElement, kAXTitleAttribute as CFString, &title) == .success,
                   let titleStr = title as? String, !titleStr.isEmpty {
                    return titleStr
                }
            }
        }

        // Fall back to CGWindowList (works without Accessibility permission but
        // returns internal window names for some apps)
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[CFString: Any]] else { return nil }

        for info in windowList {
            let layer = info[kCGWindowLayer] as? Int ?? 0
            guard layer == 0 else { continue }
            if let name = info[kCGWindowName] as? String, !name.isEmpty {
                return name
            }
        }
        return nil
    }

    /// Returns (documentPath, documentUrl).
    /// If the AX document attribute is an HTTP(S) URL, documentUrl gets the full URL
    /// and documentPath is nil (it's not a real file path).
    /// If it's a file URL or plain path, documentPath gets the path and documentUrl is nil.
    private static func activeDocumentInfo(pid: pid_t?) -> (path: String?, url: String?) {
        guard let pid else { return (nil, nil) }
        let appElement = AXUIElementCreateApplication(pid)
        var focusedWindow: AnyObject?
        guard AXUIElementCopyAttributeValue(
            appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow
        ) == .success else { return (nil, nil) }
        // swiftlint:disable:next force_cast
        let windowElement = focusedWindow as! AXUIElement

        var documentAttr: AnyObject?
        guard AXUIElementCopyAttributeValue(
            windowElement, kAXDocumentAttribute as CFString, &documentAttr
        ) == .success, let rawValue = documentAttr as? String else {
            return (nil, nil)
        }

        // Chrome/browsers return full URLs like "https://big.dk/projects/..."
        if rawValue.hasPrefix("http://") || rawValue.hasPrefix("https://") {
            return (nil, rawValue)
        }

        // File URLs like "file:///Users/..."
        if rawValue.hasPrefix("file://"), let url = URL(string: rawValue) {
            return (url.path, nil)
        }

        // Plain path or unknown format
        return (rawValue, nil)
    }

    // MARK: - Content Analysis

    static func contentHash(for text: String) -> String {
        contentHash(for: Data(text.utf8))
    }

    static func contentHash(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func contentType(for text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return "url"
        }
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~/") {
            let components = trimmed.components(separatedBy: "/")
            if components.count >= 3 {
                return "path"
            }
        }
        if (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) ||
           (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) {
            if (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) != nil {
                return "json"
            }
        }
        let codePatterns = ["func ", "def ", "class ", "import ", "const ", "let ", "var ", "return ", "if (", "for (", "while (", "=> ", "->", "();", "};"]
        let matchCount = codePatterns.filter { trimmed.contains($0) }.count
        if matchCount >= 2 {
            return "code"
        }
        return "prose"
    }
}
