import Foundation
import zlib

extension Data {
    /// Gzip-compresses the data (zlib with gzip header). Session logs compress ~10x. Returns nil
    /// on failure. The result is suitable for serving with `Content-Encoding: gzip`.
    func cachiGzipped(level: Int32 = Z_DEFAULT_COMPRESSION) -> Data? {
        guard !isEmpty else { return self }

        var stream = z_stream()
        // 15 + 16 selects the gzip wrapper (vs zlib's default 15).
        guard deflateInit2_(&stream, level, Z_DEFLATED, 15 + 16, 8, Z_DEFAULT_STRATEGY,
                            ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            return nil
        }
        defer { deflateEnd(&stream) }

        var output = Data()
        let chunkSize = 64 * 1_024
        var chunk = [UInt8](repeating: 0, count: chunkSize)

        return withUnsafeBytes { (rawBuffer: UnsafeRawBufferPointer) -> Data? in
            guard let base = rawBuffer.baseAddress else { return nil }
            stream.next_in = UnsafeMutablePointer(mutating: base.assumingMemoryBound(to: UInt8.self))
            stream.avail_in = uInt(count)

            var status: Int32 = Z_OK
            repeat {
                let result: Int32 = chunk.withUnsafeMutableBufferPointer { outBuffer in
                    stream.next_out = outBuffer.baseAddress
                    stream.avail_out = uInt(chunkSize)
                    let deflateResult = deflate(&stream, Z_FINISH)
                    let produced = chunkSize - Int(stream.avail_out)
                    if produced > 0 {
                        output.append(outBuffer.baseAddress!, count: produced)
                    }
                    return deflateResult
                }
                status = result
            } while status == Z_OK

            return status == Z_STREAM_END ? output : nil
        }
    }

    /// Decompresses gzip-wrapped data produced by `cachiGzipped()`. Returns nil on failure.
    func cachiGunzipped() -> Data? {
        guard !isEmpty else { return self }

        var stream = z_stream()
        // 15 + 32 enables automatic gzip/zlib header detection.
        guard inflateInit2_(&stream, 15 + 32, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            return nil
        }
        defer { inflateEnd(&stream) }

        var output = Data()
        let chunkSize = 64 * 1_024
        var chunk = [UInt8](repeating: 0, count: chunkSize)

        return withUnsafeBytes { (rawBuffer: UnsafeRawBufferPointer) -> Data? in
            guard let base = rawBuffer.baseAddress else { return nil }
            stream.next_in = UnsafeMutablePointer(mutating: base.assumingMemoryBound(to: UInt8.self))
            stream.avail_in = uInt(count)

            var status: Int32 = Z_OK
            repeat {
                status = chunk.withUnsafeMutableBufferPointer { outBuffer in
                    stream.next_out = outBuffer.baseAddress
                    stream.avail_out = uInt(chunkSize)
                    let inflateResult = inflate(&stream, Z_NO_FLUSH)
                    let produced = chunkSize - Int(stream.avail_out)
                    if produced > 0 {
                        output.append(outBuffer.baseAddress!, count: produced)
                    }
                    return inflateResult
                }
            } while status == Z_OK

            return status == Z_STREAM_END ? output : nil
        }
    }
}
