import Testing
import AVFoundation
@testable import SongBits

struct RecordingNotesTests {
    @Test func writesAndReadsBackMultilineNotes() async throws {
        let url = try makeTone()
        defer { remove(url) }

        #expect(await RecordingNotes.read(url) == "")
        let notes = "Capo 2\nChorus: G D Em C"
        try await RecordingNotes.write(notes, to: url)
        #expect(await RecordingNotes.read(url) == notes)
    }

    @Test func overwritesExistingNotes() async throws {
        let url = try makeTone()
        defer { remove(url) }

        try await RecordingNotes.write("first", to: url)
        try await RecordingNotes.write("second", to: url)
        #expect(await RecordingNotes.read(url) == "second")
        #expect(try await commentCount(url) == 1)
    }

    @Test func blankTextRemovesTheComment() async throws {
        let url = try makeTone()
        defer { remove(url) }

        try await RecordingNotes.write("idea", to: url)
        try await RecordingNotes.write("  \n", to: url)
        #expect(await RecordingNotes.read(url) == "")
        #expect(try await commentCount(url) == 0)
    }

    @Test func leavesTheAudioUntouched() async throws {
        let url = try makeTone()
        defer { remove(url) }
        let before = try await compressedAudio(url)

        try await RecordingNotes.write("idea", to: url)
        #expect(try await compressedAudio(url) == before)
    }

    @Test func keepsTheCreationDate() async throws {
        let url = try makeTone()
        defer { remove(url) }
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.creationDate: created], ofItemAtPath: url.path)

        try await RecordingNotes.write("idea", to: url)
        let values = try url.resourceValues(forKeys: [.creationDateKey])
        #expect(values.creationDate == created)
    }

    @Test func keepsOtherMetadata() async throws {
        let url = try makeTone()
        defer { remove(url) }
        let others = try await otherIdentifiers(url)

        try await RecordingNotes.write("idea", to: url)
        #expect(try await otherIdentifiers(url) == others)
    }

    // MARK: - Helpers

    private func commentCount(_ url: URL) async throws -> Int {
        let metadata = try await AVURLAsset(url: url).load(.metadata)
        return metadata.filter { $0.identifier == .iTunesMetadataUserComment }.count
    }

    private func otherIdentifiers(_ url: URL) async throws -> Set<String> {
        let metadata = try await AVURLAsset(url: url).load(.metadata)
        return Set(metadata.compactMap(\.identifier?.rawValue))
            .subtracting([AVMetadataIdentifier.iTunesMetadataUserComment.rawValue])
    }

    /// The track's compressed packets, read without decoding.
    private func compressedAudio(_ url: URL) async throws -> Data {
        let asset = AVURLAsset(url: url)
        let track = try #require(try await asset.loadTracks(withMediaType: .audio).first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        reader.startReading()
        var data = Data()
        while let sample = output.copyNextSampleBuffer() {
            if let buffer = sample.dataBuffer { data.append(try buffer.dataBytes()) }
        }
        return data
    }

    /// Writes a one-second mono AAC `.m4a` sine tone to a temp file.
    private func makeTone() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("notes-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        let sampleRate = 44_100.0
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        let frameCount = AVAudioFrameCount(sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let samples = buffer.floatChannelData![0]
        for frame in 0..<Int(frameCount) {
            samples[frame] = 0.5 * Float(sin(2.0 * .pi * 440 * Double(frame) / sampleRate))
        }
        try file.write(from: buffer)
        return url
    }

    private func remove(_ url: URL) { try? FileManager.default.removeItem(at: url) }
}
