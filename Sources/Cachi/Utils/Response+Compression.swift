import Vapor

extension Response {
    /// Marks the response so Vapor's server-side compressor skips it. Use for already-compressed
    /// payloads (mp4, jpeg/png, zipped xcresult) where re-gzipping wastes CPU for no size gain, and
    /// for responses that carry their own `Content-Encoding`.
    ///
    /// Vapor's `responseCompression = .enabled` config has `allowRequestOverrides: true`, so this
    /// per-response marker is honored by NIO's compressor (returns `.doNotCompress`).
    func disableServerCompression() {
        headers.responseCompression = .disable
    }
}
