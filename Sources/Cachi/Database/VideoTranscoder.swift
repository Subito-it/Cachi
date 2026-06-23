import AVFoundation
import Foundation
import os

/// Re-encodes the barely-compressed xcresult screen recordings (captured at up to 600 fps) into
/// a much smaller mp4 for permanent storage. Uses AVFoundation only (no external binary), so it
/// works on a stock macOS install.
///
/// Measured on a real 48 MB / 1640x2360 failure recording: `mediumQuality` → ~5 MB (~9x) in ~5s.
/// The preset is the size/legibility knob — `mediumQuality` favors size (downscales to ~332x480);
/// step `960x540` keeps more on-screen text legible at ~2.7x. Change `Self.preset` to retune.
enum VideoTranscoder {
    /// Compression preset. `mediumQuality` gives ~9x at low resolution; bump to a fixed-size
    /// preset (e.g. `AVAssetExportPreset960x540`) if UI text legibility matters more than size.
    static let preset = AVAssetExportPresetMediumQuality

    enum TranscodeError: Error { case noSession, exportFailed(String) }

    /// Transcodes `sourceUrl` to an mp4 at `destinationUrl`. Blocks until done.
    static func transcode(sourceUrl: URL, destinationUrl: URL) throws {
        try? FileManager.default.removeItem(at: destinationUrl)

        let asset = AVURLAsset(url: sourceUrl)
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw TranscodeError.noSession
        }
        session.outputURL = destinationUrl
        session.outputFileType = .mp4

        var exportError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached(priority: .userInitiated) {
            await session.export()
            if session.status != .completed {
                exportError = TranscodeError.exportFailed(session.error?.localizedDescription ?? "status \(session.status.rawValue)")
            }
            semaphore.signal()
        }
        semaphore.wait()

        if let exportError { throw exportError }
    }
}
