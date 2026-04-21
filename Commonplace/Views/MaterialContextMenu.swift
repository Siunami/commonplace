import SwiftUI
import AppKit

// Unified right-click menu for any material in the archive.
// Layout: Copy, Open, Reveal in Finder, Share.
// Open/Reveal only appear when the action has a meaningful target for the type.

enum MaterialAction {
    static func copy(_ highlight: Highlight) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if highlight.highlightType == "screenshot",
           let sid = highlight.screenshotId,
           let rec = DatabaseManager.shared.screenshot(byId: sid),
           let img = NSImage(contentsOfFile: rec.filePath) {
            pb.writeObjects([img])
            return
        }
        if let url = localFileURL(for: highlight) {
            pb.writeObjects([url as NSURL])
            return
        }
        pb.setString(highlight.contentText, forType: .string)
    }

    static func open(_ highlight: Highlight) {
        guard let url = openTarget(for: highlight) else { return }
        if highlight.highlightType == "file" {
            openFile(highlight.contentText)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    static func revealInFinder(_ highlight: Highlight) {
        guard let url = localFileURL(for: highlight) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func localFileURL(for highlight: Highlight) -> URL? {
        switch highlight.highlightType {
        case "screenshot":
            guard let sid = highlight.screenshotId,
                  let rec = DatabaseManager.shared.screenshot(byId: sid) else { return nil }
            return URL(fileURLWithPath: rec.filePath)
        case "recording", "file":
            let path = highlight.contentText
            return path.isEmpty ? nil : URL(fileURLWithPath: path)
        default:
            return nil
        }
    }

    static func openTarget(for highlight: Highlight) -> URL? {
        if highlight.isURLCopy {
            let s = highlight.contentText.trimmingCharacters(in: .whitespacesAndNewlines)
            return URL(string: s)
        }
        return localFileURL(for: highlight)
    }

    static func copyLabel(for highlight: Highlight) -> String {
        switch highlight.highlightType {
        case "screenshot": return "Copy Image"
        case "recording", "file": return "Copy File"
        default:
            return highlight.isURLCopy ? "Copy URL" : "Copy Text"
        }
    }

    static func openLabel(for highlight: Highlight) -> String {
        switch highlight.highlightType {
        case "recording": return "Open in QuickTime"
        default:
            return highlight.isURLCopy ? "Open in Browser" : "Open"
        }
    }

    static func shareItems(for highlight: Highlight) -> [Any] {
        if let url = localFileURL(for: highlight) { return [url] }
        if highlight.isURLCopy,
           let url = URL(string: highlight.contentText.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return [url]
        }
        return [highlight.contentText]
    }
}

// MARK: - SwiftUI modifier

struct MaterialContextMenuModifier: ViewModifier {
    let highlight: Highlight

    func body(content: Content) -> some View {
        content.contextMenu {
            Button(MaterialAction.copyLabel(for: highlight)) {
                MaterialAction.copy(highlight)
            }

            if MaterialAction.openTarget(for: highlight) != nil {
                Button(MaterialAction.openLabel(for: highlight)) {
                    MaterialAction.open(highlight)
                }
            }

            if MaterialAction.localFileURL(for: highlight) != nil {
                Button("Reveal in Finder") {
                    MaterialAction.revealInFinder(highlight)
                }
            }

            shareButton
        }
    }

    @ViewBuilder
    private var shareButton: some View {
        if let url = MaterialAction.localFileURL(for: highlight) {
            ShareLink(item: url)
        } else if highlight.isURLCopy,
                  let url = URL(string: highlight.contentText.trimmingCharacters(in: .whitespacesAndNewlines)) {
            ShareLink(item: url)
        } else {
            ShareLink(item: highlight.contentText)
        }
    }
}

extension View {
    func materialContextMenu(for highlight: Highlight) -> some View {
        modifier(MaterialContextMenuModifier(highlight: highlight))
    }
}

// MARK: - NSMenu builder (for the AppKit capture toast)

final class MaterialMenuTarget: NSObject {
    var onCopy: (() -> Void)?
    var onOpen: (() -> Void)?
    var onRevealInFinder: (() -> Void)?
    var onShare: ((NSView) -> Void)?
    var onDismiss: (() -> Void)?

    @objc func copyMaterial() { onCopy?() }
    @objc func openMaterial() { onOpen?() }
    @objc func revealInFinder() { onRevealInFinder?() }
    @objc func share(_ sender: NSMenuItem) {
        guard let view = sender.representedObject as? NSView else { return }
        onShare?(view)
    }
    @objc func dismissToast() { onDismiss?() }
}

func buildMaterialNSMenu(
    for highlight: Highlight,
    target: MaterialMenuTarget,
    anchorView: NSView,
    includeDismiss: Bool
) -> NSMenu {
    let menu = NSMenu()

    let copyItem = NSMenuItem(title: MaterialAction.copyLabel(for: highlight),
                              action: #selector(MaterialMenuTarget.copyMaterial),
                              keyEquivalent: "")
    copyItem.target = target
    menu.addItem(copyItem)

    if MaterialAction.openTarget(for: highlight) != nil {
        let openItem = NSMenuItem(title: MaterialAction.openLabel(for: highlight),
                                  action: #selector(MaterialMenuTarget.openMaterial),
                                  keyEquivalent: "")
        openItem.target = target
        menu.addItem(openItem)
    }

    if MaterialAction.localFileURL(for: highlight) != nil {
        let revealItem = NSMenuItem(title: "Reveal in Finder",
                                    action: #selector(MaterialMenuTarget.revealInFinder),
                                    keyEquivalent: "")
        revealItem.target = target
        menu.addItem(revealItem)
    }

    let shareItem = NSMenuItem(title: "Share…",
                               action: #selector(MaterialMenuTarget.share(_:)),
                               keyEquivalent: "")
    shareItem.target = target
    shareItem.representedObject = anchorView
    menu.addItem(shareItem)

    if includeDismiss {
        menu.addItem(.separator())
        let dismissItem = NSMenuItem(title: "Dismiss",
                                     action: #selector(MaterialMenuTarget.dismissToast),
                                     keyEquivalent: "")
        dismissItem.target = target
        menu.addItem(dismissItem)
    }

    return menu
}

func presentShareMenu(for highlight: Highlight, relativeTo view: NSView) {
    let picker = NSSharingServicePicker(items: MaterialAction.shareItems(for: highlight))
    picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
}
