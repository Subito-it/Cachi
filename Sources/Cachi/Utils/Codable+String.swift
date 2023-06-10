import Foundation

extension String {
    /// Create `Data` from hexadecimal string representation
    ///
    /// This creates a `Data` object from hex string. Note, if the string has any spaces or non-hex characters (e.g. starts with '<' and with a '>'), those are ignored and only hex characters are processed.
    ///
    /// - returns: Data represented by this hexadecimal string.
    var hexadecimalRepresentation: String {
        Data(utf8).map { String(format: "%02x", $0) }.joined()
    }

    init?(hexadecimalRepresentation: String) {
        guard let data = Data(hexadecimalRepresentation: hexadecimalRepresentation) else {
            return nil
        }

        self = String(decoding: data, as: UTF8.self)
    }
}

extension Data {
    var hexadecimalRepresentation: String? {
        map { String(format: "%02x", $0) }.joined()
    }

    init?(hexadecimalRepresentation: String) {
        var data = Data(capacity: hexadecimalRepresentation.count / 2)

        let regex = try! NSRegularExpression(pattern: "[0-9a-f]{1,2}", options: .caseInsensitive)
        regex.enumerateMatches(in: hexadecimalRepresentation, range: NSRange(hexadecimalRepresentation.startIndex..., in: hexadecimalRepresentation)) { match, _, _ in
            let byteString = (hexadecimalRepresentation as NSString).substring(with: match!.range)
            let num = UInt8(byteString, radix: 16)!
            data.append(num)
        }

        guard data.count > 0 else { return nil }

        self = data
    }
}
