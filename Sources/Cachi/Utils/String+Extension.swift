import Foundation

extension String {
    private static var regexCacheQueue: DispatchQueue = DispatchQueue(label: "com.subito.cachi.regex.queue")
    private static var regexCache = [String: NSRegularExpression]()
    
    func capturedGroups(regex: NSRegularExpression) -> [String] {
        var results = [String]()

        let matches = regex.matches(in: self, options: [], range: NSRange(location: 0, length: count))

        guard let match = matches.first else { return results }

        let lastRangeIndex = match.numberOfRanges - 1
        guard lastRangeIndex >= 1 else { return results }

        for i in 1 ... lastRangeIndex {
            let location = match.range(at: i)
            guard location.location != NSNotFound else {
                results.append("")
                continue
            }

            let sIndex = index(startIndex, offsetBy: location.location)
            let eIndex = index(sIndex, offsetBy: location.length)

            results.append(String(self[sIndex ..< eIndex]))
        }

        return results
    }

    func capturedGroups(withRegexString pattern: String) throws -> [String] {
        if let regex = Self.regexCacheQueue.sync(execute: { Self.regexCache[pattern] }) {
            return capturedGroups(regex: regex)
        } else {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            Self.regexCacheQueue.sync { Self.regexCache[pattern] = regex }
            return capturedGroups(regex: regex)
        }
    }
}
