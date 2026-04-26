import AppKit

extension Notification.Name {
    /// Posted after a new highlight (copy, screenshot, recording, etc.) is saved to the database.
    static let highlightDidSave = Notification.Name("highlightDidSave")

    /// Posted after a user-driven edit mutates an existing highlight
    /// (tag add/remove, note add/remove, userNote update). Observers
    /// should refresh their cached state for the affected row.
    /// userInfo:
    ///   - "highlightId": String — the row that changed
    ///   - "change": String — one of "tags", "notes", "userNote"
    static let highlightDataDidChange = Notification.Name("highlightDataDidChange")
}

final class HighlightCapture {
    static let shared = HighlightCapture()

    private let db = DatabaseManager.shared

    // MARK: - Recording Capture

    func captureFromRecording(result: ScreenRecordingCapture.RecordingResult) {
        let entryId = UUID().uuidString
        let fileURL = URL(fileURLWithPath: result.filePath)
        let filename = fileURL.lastPathComponent
        let appName = result.context.sourceAppName ?? "Recording"

        let highlight = Highlight(
            id: entryId,
            timestamp: Date().timeIntervalSince1970,
            contentText: result.filePath,
            sourceApp: appName,
            sourceUrl: result.context.sourceUrl,
            userNote: nil,
            highlightType: "recording",
            screenshotId: nil,
            recordingId: result.recordingId,
            fileId: nil,
            windowTitle: result.context.windowTitle,
            bundleId: result.context.bundleId,
            contentHash: nil,
            documentPath: result.filePath,
            contentType: nil,
            displayName: result.context.displayName,
            displayResolution: result.context.displayResolution,
            appearanceMode: result.context.appearanceMode,
            wifiNetwork: result.context.wifiNetwork,
            sourceContext: result.context.sourceContext
        )
        db.insertHighlight(highlight)
        NotificationCenter.default.post(name: .highlightDidSave, object: nil)

        let entry = AnnotationEntry(
            id: entryId,
            content: result.filePath,
            timestamp: Date().timeIntervalSince1970,
            sourceApp: appName,
            type: "recording",
            annotation: nil
        )
        AnnotationStore.shared.save(entry)

        let durationStr = String(format: "%.0fs", result.duration)
        let sizeStr = RecordingRecord.formatFileSize(result.fileSize)
        let toastContent = "\(filename) · \(durationStr) · \(sizeStr)"

        if let thumbImage = NSImage(contentsOfFile: result.thumbnailPath) {
            CopyToastController.shared.show(
                image: thumbImage,
                content: toastContent,
                filePath: result.filePath,
                badgeLabel: "Recording",
                entryId: entryId,
                sourceUrl: result.context.sourceUrl,
                sourceApp: appName,
                windowTitle: result.context.windowTitle
            ) { [weak self] id, note in
                AnnotationStore.shared.updateAnnotation(id: id, note: note)
                self?.db.addNoteToHighlight(highlightId: entryId, body: note)
            }
        } else {
            CopyToastController.shared.show(
                content: toastContent,
                entryId: entryId,
                sourceUrl: result.context.sourceUrl,
                sourceApp: appName,
                windowTitle: result.context.windowTitle
            ) { [weak self] id, note in
                AnnotationStore.shared.updateAnnotation(id: id, note: note)
                self?.db.addNoteToHighlight(highlightId: entryId, body: note)
            }
        }

        CaptureLog.info("Saved recording: \(result.filePath), duration: \(String(format: "%.1f", result.duration))s")
    }

    // MARK: - Copy Capture

    func captureFromCopy(content: String, sourceApp: String?, entryId: String, context: CaptureContext) {
        captureAndShow(content: content, type: "copy", sourceApp: sourceApp, entryId: entryId, context: context)
    }

    func captureFromUserScreenshot(filePath: String, image: NSImage, screenshotId: Int64?, context: CaptureContext, badgeLabel: String = "Screenshot", sources: [ScreenshotSource] = []) {
        let entryId = UUID().uuidString
        let filename = URL(fileURLWithPath: filePath).lastPathComponent

        // Prefer the largest visible contributor as the primary source
        // attribution when the resolver found something — otherwise
        // fall back to the frontmost-app context (older clipboard /
        // paste paths still call us with sources=[]).
        let primaryName = sources.first?.name ?? context.sourceAppName
        let primaryBundle = sources.first?.bundleId ?? context.bundleId
        let primaryWindowTitle = sources.first?.windowTitle ?? context.windowTitle
        let sourcesJSON = ScreenshotSources.encodeJSON(sources)

        let highlightId = saveHighlight(
            content: filePath, type: "screenshot", sourceApp: primaryName,
            entryId: entryId, screenshotId: screenshotId, context: context,
            primaryBundleId: primaryBundle, primaryWindowTitle: primaryWindowTitle,
            sourcesJSON: sourcesJSON
        )

        let entry = AnnotationEntry(
            id: entryId,
            content: filePath,
            timestamp: Date().timeIntervalSince1970,
            sourceApp: primaryName,
            type: "screenshot",
            annotation: nil
        )
        AnnotationStore.shared.save(entry)

        CopyToastController.shared.show(image: image, content: filename, filePath: filePath, badgeLabel: badgeLabel, entryId: entryId, sourceUrl: context.sourceUrl, sourceApp: primaryName, windowTitle: primaryWindowTitle) { [weak self] id, note in
            AnnotationStore.shared.updateAnnotation(id: id, note: note)
            self?.db.addNoteToHighlight(highlightId: highlightId, body: note)
        }
    }

    private func captureAndShow(content: String, type: String, sourceApp: String?, entryId: String, context: CaptureContext) {
        let highlightId = saveHighlight(
            content: content, type: type, sourceApp: sourceApp,
            entryId: entryId, screenshotId: nil, context: context
        )

        let entry = AnnotationEntry(
            id: entryId,
            content: content,
            timestamp: Date().timeIntervalSince1970,
            sourceApp: sourceApp,
            type: type,
            annotation: nil
        )
        AnnotationStore.shared.save(entry)

        CopyToastController.shared.show(content: content, entryId: entryId, sourceUrl: context.sourceUrl, sourceApp: sourceApp, windowTitle: context.windowTitle) { [weak self] id, note in
            AnnotationStore.shared.updateAnnotation(id: id, note: note)
            self?.db.addNoteToHighlight(highlightId: highlightId, body: note)
        }

        // If the user copied a URL that points to a file (PDF, image, video…),
        // download it in the background and attach it to this highlight. The
        // highlight stays type "copy" — the detail view decides to show a file
        // preview when fileId gets populated.
        if type == "copy" && URLFileDownloader.isLikelyFileURL(content) {
            Task.detached(priority: .utility) {
                await URLFileDownloader.shared.downloadIfFile(
                    urlString: content,
                    attachTo: highlightId
                )
            }
        }
    }

    @discardableResult
    private func saveHighlight(
        content: String,
        type: String,
        sourceApp: String?,
        entryId: String,
        screenshotId: Int64?,
        context: CaptureContext,
        primaryBundleId: String? = nil,
        primaryWindowTitle: String? = nil,
        sourcesJSON: String? = nil
    ) -> String {
        let hash = (type != "screenshot") ? CaptureContext.contentHash(for: content) : nil
        let cType = (type != "screenshot") ? CaptureContext.contentType(for: content) : nil

        // Screenshot captures route the largest visible source through
        // the singular fields (sourceApp / bundleId / windowTitle); all
        // other capture types stick with the frontmost-app context.
        let resolvedBundleId = primaryBundleId ?? context.bundleId
        let resolvedWindowTitle = primaryWindowTitle ?? context.windowTitle

        let highlight = Highlight(
            id: entryId,
            timestamp: Date().timeIntervalSince1970,
            contentText: content,
            sourceApp: sourceApp,
            sourceUrl: context.sourceUrl,
            userNote: nil,
            highlightType: type,
            screenshotId: screenshotId,
            recordingId: nil,
            fileId: nil,
            windowTitle: resolvedWindowTitle,
            bundleId: resolvedBundleId,
            contentHash: hash,
            documentPath: context.documentPath,
            contentType: cType,
            displayName: context.displayName,
            displayResolution: context.displayResolution,
            appearanceMode: context.appearanceMode,
            wifiNetwork: context.wifiNetwork,
            sourceContext: context.sourceContext,
            sources: sourcesJSON
        )
        db.insertHighlight(highlight)

        CaptureLog.info("Saved highlight: \(type), id: \(entryId), window: \(context.windowTitle ?? "nil"), bundle: \(context.bundleId ?? "nil")")

        NotificationCenter.default.post(name: .highlightDidSave, object: nil)
        return entryId
    }

    // MARK: - File Detection

    func captureFromFileDetection(
        fileRecord: FileRecord,
        thumbnailImage: NSImage?,
        tagIds: [String] = [],
        sourceUrl: String? = nil,
        sourceContext: String? = nil
    ) {
        let entryId = UUID().uuidString
        let filePath = fileRecord.filePath
        let fileName = fileRecord.fileName

        let highlight = Highlight(
            id: entryId,
            timestamp: fileRecord.timestamp,
            contentText: filePath,
            sourceApp: nil,
            sourceUrl: sourceUrl,
            userNote: nil,
            highlightType: "file",
            screenshotId: nil,
            recordingId: nil,
            fileId: fileRecord.id,
            windowTitle: fileName,
            bundleId: nil,
            contentHash: nil,
            documentPath: filePath,
            contentType: fileRecord.contentType,
            displayName: nil,
            displayResolution: nil,
            appearanceMode: nil,
            wifiNetwork: nil,
            sourceContext: sourceContext
        )
        db.insertHighlight(highlight)
        for tagId in tagIds {
            db.addTag(tagId, toHighlight: entryId)
        }
        NotificationCenter.default.post(name: .highlightDidSave, object: nil)

        let entry = AnnotationEntry(
            id: entryId,
            content: filePath,
            timestamp: fileRecord.timestamp,
            sourceApp: nil,
            type: "file",
            annotation: nil
        )
        AnnotationStore.shared.save(entry)

        let sizeStr = fileRecord.formattedFileSize
        let typeStr = fileRecord.contentType ?? fileRecord.fileExtension?.uppercased() ?? "File"
        let toastContent = "\(fileName) · \(sizeStr) · \(typeStr)"

        if let thumbImage = thumbnailImage {
            CopyToastController.shared.show(
                image: thumbImage,
                content: toastContent,
                filePath: filePath,
                badgeLabel: "File",
                entryId: entryId
            ) { [weak self] id, note in
                AnnotationStore.shared.updateAnnotation(id: id, note: note)
                self?.db.addNoteToHighlight(highlightId: entryId, body: note)
            }
        } else {
            CopyToastController.shared.show(
                content: toastContent,
                entryId: entryId
            ) { [weak self] id, note in
                AnnotationStore.shared.updateAnnotation(id: id, note: note)
                self?.db.addNoteToHighlight(highlightId: entryId, body: note)
            }
        }

        CaptureLog.info("Captured file: \(fileName) (\(sizeStr)) from \(fileRecord.sourceFolder)")
    }

    // MARK: - Manual Add (+ tile in Browse)

    /// User typed or pasted text into the Browse "+" tile. Saves as a "note"
    /// highlight with minimal context (no source app, no window title — user-
    /// initiated, not observed). `origin` defaults to `.captured` so all
    /// existing callers keep working unchanged; the canvas inline-note path
    /// passes `.workspaceCreated(workspaceId:)` to stamp v26 origin
    /// metadata at write time.
    @discardableResult
    func captureFromUserAdd(text: String, origin: OriginContext = .captured) -> String {
        let highlightId = UUID().uuidString
        let originFields = Self.originFields(for: origin)
        let highlight = Highlight(
            id: highlightId,
            timestamp: Date().timeIntervalSince1970,
            contentText: text,
            sourceApp: nil,
            sourceUrl: nil,
            userNote: nil,
            highlightType: "note",
            screenshotId: nil,
            recordingId: nil,
            fileId: nil,
            windowTitle: nil,
            bundleId: nil,
            contentHash: CaptureContext.contentHash(for: text),
            documentPath: nil,
            contentType: CaptureContext.contentType(for: text),
            displayName: nil,
            displayResolution: nil,
            appearanceMode: nil,
            wifiNetwork: nil,
            sourceContext: nil,
            originType: originFields.type,
            originWorkspaceId: originFields.workspaceId,
            parentCardId: originFields.parentCardId,
            derivationType: originFields.derivationType,
            derivationData: originFields.derivationData,
            inheritedProvenance: originFields.inheritedProvenance
        )
        db.insertHighlight(highlight)
        NotificationCenter.default.post(name: .highlightDidSave, object: nil)
        return highlightId
    }

    /// Write a derived highlight extracted from `parent.contentText` over
    /// `range` (UTF-16 char offsets, the same units NSTextView reports).
    /// The parent's provenance is snapshotted into `inheritedProvenance`
    /// at this moment so the derived card stays self-contained even if
    /// the parent is later deleted. When `inWorkspaceId` is non-nil and
    /// the parent has a placement in that workspace, the new card is
    /// auto-placed directly below the parent at the parent's width.
    /// Returns the new highlight id, or nil if `range` is outside
    /// `parent.contentText`.
    @discardableResult
    func deriveFromSelection(parent: Highlight, range: NSRange, inWorkspaceId: String?) -> String? {
        let content = parent.contentText as NSString
        guard range.location >= 0,
              range.length > 0,
              range.location + range.length <= content.length else {
            return nil
        }
        let excerpt = content.substring(with: range) as String

        let highlightId = UUID().uuidString
        let originFields = Self.originFields(for: .derived(parentCardId: parent.id, range: range))
        let highlight = Highlight(
            id: highlightId,
            timestamp: Date().timeIntervalSince1970,
            contentText: excerpt,
            sourceApp: nil,
            sourceUrl: nil,
            userNote: nil,
            highlightType: "note",
            screenshotId: nil,
            recordingId: nil,
            fileId: nil,
            windowTitle: nil,
            bundleId: nil,
            contentHash: CaptureContext.contentHash(for: excerpt),
            documentPath: nil,
            contentType: CaptureContext.contentType(for: excerpt),
            displayName: nil,
            displayResolution: nil,
            appearanceMode: nil,
            wifiNetwork: nil,
            sourceContext: nil,
            originType: originFields.type,
            originWorkspaceId: originFields.workspaceId,
            parentCardId: originFields.parentCardId,
            derivationType: originFields.derivationType,
            derivationData: originFields.derivationData,
            inheritedProvenance: originFields.inheritedProvenance
        )
        db.insertHighlight(highlight)
        NotificationCenter.default.post(name: .highlightDidSave, object: nil)

        if let workspaceId = inWorkspaceId,
           let parentPlacement = db.placement(workspaceId: workspaceId, cardId: parent.id) {
            // 24pt gap below the parent — one gridStep / 5 — close enough
            // to read as "child of" without overlapping the parent's chrome.
            db.createPlacement(
                workspaceId: workspaceId,
                cardId: highlightId,
                x: parentPlacement.x,
                y: parentPlacement.y + parentPlacement.height + 24,
                width: parentPlacement.width,
                height: 240
            )
        }
        return highlightId
    }

    /// Resolve an `OriginContext` to the v26 column values written into
    /// `highlight`. Pulled out so future capture entry points (image
    /// crop, derived note, multi-parent synthesis) can reuse the same
    /// mapping without duplicating the JSON-encoding ceremony.
    private static func originFields(for origin: OriginContext) -> (
        type: String,
        workspaceId: String?,
        parentCardId: String?,
        derivationType: String?,
        derivationData: String?,
        inheritedProvenance: String?
    ) {
        switch origin {
        case .captured:
            return ("captured", nil, nil, nil, nil, nil)
        case .workspaceCreated(let workspaceId):
            return ("workspace_created", workspaceId, nil, nil, nil, nil)
        case .derived(let parentCardId, let range):
            // derivation_data: { "start": Int, "end": Int } — character
            // offsets into the parent's contentText, frozen at derive time.
            let derivationDict: [String: Int] = [
                "start": range.location,
                "end": range.location + range.length
            ]
            let derivationJSON = (try? JSONSerialization.data(withJSONObject: derivationDict))
                .flatMap { String(data: $0, encoding: .utf8) }

            // inherited_provenance: snapshot of the parent's provenance
            // fields at derive time. Self-contained so deletes of the
            // parent don't strand the child's source attribution.
            var inherited: String? = nil
            if let parent = DatabaseManager.shared.highlight(byId: parentCardId) {
                var provenance: [String: String] = [:]
                if let v = parent.sourceApp { provenance["sourceApp"] = v }
                if let v = parent.sourceUrl { provenance["sourceUrl"] = v }
                if let v = parent.windowTitle { provenance["windowTitle"] = v }
                if let v = parent.documentPath { provenance["documentPath"] = v }
                if let v = parent.bundleId { provenance["bundleId"] = v }
                if let v = parent.sourceContext { provenance["sourceContext"] = v }
                if !provenance.isEmpty,
                   let data = try? JSONSerialization.data(withJSONObject: provenance) {
                    inherited = String(data: data, encoding: .utf8)
                }
            }
            return ("derived", nil, parentCardId, "text_excerpt", derivationJSON, inherited)
        }
    }
}
