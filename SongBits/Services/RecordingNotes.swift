import AVFoundation

/// Per-recording notes, stored in the `.m4a` itself as the standard iTunes
/// comment atom (`©cmt`) so they travel with the file through renames, moves,
/// sharing, and other apps.
///
/// Writing remuxes the file with a passthrough export: the compressed audio is
/// copied as-is (never re-encoded) and only the container's metadata changes.
enum RecordingNotes {
    enum NotesError: LocalizedError {
        case exportUnavailable
        case exportFailed(String)

        var errorDescription: String? {
            switch self {
            case .exportUnavailable: "Couldn't open the recording to save its notes."
            case .exportFailed(let detail): "Couldn't save the notes: \(detail)"
            }
        }
    }

    /// The recording's notes, empty when it has none or can't be read.
    static func read(_ url: URL) async -> String {
        let asset = AVURLAsset(url: url)
        guard let metadata = try? await asset.load(.metadata) else { return "" }
        let comments = AVMetadataItem.metadataItems(
            from: metadata,
            filteredByIdentifier: .iTunesMetadataUserComment
        )
        guard let item = comments.first else { return "" }
        return (try? await item.load(.stringValue)) ?? ""
    }

    /// Replaces the recording's notes, keeping its other metadata. Blank text
    /// removes the comment. The file is rewritten beside itself and swapped in,
    /// so a failure leaves the original untouched, and the swap keeps the
    /// original's creation date (the app's recording date).
    static func write(_ text: String, to url: URL) async throws {
        let asset = AVURLAsset(url: url)
        var metadata = try await asset.load(.metadata).filter {
            $0.identifier != .iTunesMetadataUserComment
        }
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let comment = AVMutableMetadataItem()
            comment.identifier = .iTunesMetadataUserComment
            comment.value = text as NSString
            metadata.append(comment)
        }

        guard let export = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetPassthrough
        ) else { throw NotesError.exportUnavailable }

        let fm = FileManager.default
        let scratch = try fm.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: url,
            create: true
        )
        defer { try? fm.removeItem(at: scratch) }
        let output = scratch.appendingPathComponent(url.lastPathComponent)

        export.outputURL = output
        export.outputFileType = .m4a
        export.metadata = metadata

        await withCheckedContinuation { continuation in
            export.exportAsynchronously { continuation.resume() }
        }
        guard export.status == .completed else {
            throw NotesError.exportFailed(export.error?.localizedDescription ?? "Unknown error.")
        }
        _ = try fm.replaceItemAt(url, withItemAt: output)
    }
}
