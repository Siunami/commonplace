import Foundation
import AppKit

/// One "destination" for a stack: picks its packaging (Textbundle / flat
/// folder / clipboard markdown), does the post-export action (reveal in
/// Finder, open a browser, etc.), and optionally returns a toast
/// message for the header's inline confirmation banner.
protocol StackExportTarget {
    var id: String { get }
    var displayName: String { get }
    var iconSystemName: String { get }
    var help: String { get }

    /// Returns a short confirmation message to surface as a toast, or
    /// `nil` to stay silent. Throws to surface an error alert.
    func perform(stack: Stack) throws -> String?
}

// MARK: - Bear / Textbundle

/// The "archival" export — preserves media in the Textbundle convention
/// (Bear, iA Writer, Ulysses import it natively; Obsidian opens it as a
/// plain folder with working media). Uses a directory picker because
/// users typically know where they want the file to land.
struct BearTextbundleTarget: StackExportTarget {
    let id = "bear-textbundle"
    let displayName = "Export as Textbundle (Bear, Obsidian)"
    let iconSystemName = "square.and.arrow.up"
    let help = "Standards-compliant markdown + media package"

    func perform(stack: Stack) throws -> String? {
        let panel = NSOpenPanel()
        panel.title = "Export Stack"
        panel.message = "Choose a location to save the Textbundle."
        panel.prompt = "Export Here"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            panel.directoryURL = downloads
        }

        guard panel.runModal() == .OK, let parent = panel.url else {
            return nil
        }

        let result = try StackExporter.exportTextbundle(stack: stack, into: parent)
        if let folderURL = result.folderURL {
            NSWorkspace.shared.activateFileViewerSelecting([folderURL])
        }
        return nil
    }
}

// MARK: - Browser LLM (ChatGPT, Claude, …)

/// Writes a flat folder (prompt.md + media as siblings) to a known
/// location, reveals it in Finder, and opens the LLM's web UI. The user
/// drags the individual files into the chat input. Skips the picker on
/// purpose — this flow is about speed, and users can move the folder
/// afterward if they want to keep it.
struct BrowserLLMTarget: StackExportTarget {
    let llmName: String
    let llmURL: URL

    var id: String { "llm-" + llmName.lowercased() }
    var displayName: String { "Send to \(llmName)" }
    var iconSystemName: String { "paperplane" }
    var help: String { "Create a folder and open \(llmName) in your browser" }

    func perform(stack: Stack) throws -> String? {
        let parent = try StackExportLocations.llmExportsDirectory()
        let result = try StackExporter.exportFolder(
            stack: stack,
            into: parent,
            seed: StackPromptSeed.seed(for: stack)
        )
        if let folderURL = result.folderURL {
            NSWorkspace.shared.activateFileViewerSelecting([folderURL])
        }
        NSWorkspace.shared.open(llmURL)
        return "Drag the files into \(llmName)"
    }
}

// MARK: - Copy markdown

/// Clipboard only. Media items become text placeholders so the paste
/// doesn't produce broken image links. Good for conversational tools
/// that only accept text, or for pasting into notes/documents.
struct CopyMarkdownTarget: StackExportTarget {
    let id = "copy-markdown"
    let displayName = "Copy as Markdown"
    let iconSystemName = "doc.on.doc"
    let help = "Copy a text-only markdown version to the clipboard"

    func perform(stack: Stack) throws -> String? {
        let md = StackExporter.renderMarkdown(
            stack: stack,
            seed: StackPromptSeed.seed(for: stack)
        )
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(md, forType: .string)
        return "Copied markdown to clipboard"
    }
}

// MARK: - Helpers

/// The handful of sentences we prepend to LLM-bound exports. Kept
/// short and neutral so the user isn't fighting a predetermined frame
/// when they land in the chat.
enum StackPromptSeed {
    static func seed(for stack: Stack) -> String {
        let name = stack.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = name.isEmpty ? "my archive" : "\"\(name)\""
        return """
        Here's material I've gathered in \(title). \
        Help me notice patterns, connections, or themes.
        """
    }
}

enum StackExportLocations {
    /// `~/Downloads/Commonplace Exports/`. Created on demand. Single
    /// predictable bucket for automatic exports (LLM targets) so we
    /// don't scatter timestamped folders across the user's Downloads
    /// root.
    static func llmExportsDirectory() throws -> URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        let dir = downloads.appendingPathComponent("Commonplace Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

// MARK: - Default target set

enum StackExportTargets {
    /// The full menu shown in the stack header. Bear sits alone in the
    /// top group because it's the archival / portable format; the LLM
    /// + clipboard targets share the "send to another tool" group.
    static let all: [StackExportTarget] = [
        BearTextbundleTarget(),
        BrowserLLMTarget(
            llmName: "ChatGPT",
            llmURL: URL(string: "https://chatgpt.com/")!
        ),
        BrowserLLMTarget(
            llmName: "Claude",
            llmURL: URL(string: "https://claude.ai/new")!
        ),
        CopyMarkdownTarget()
    ]
}
