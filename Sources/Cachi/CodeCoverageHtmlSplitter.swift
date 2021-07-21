import Foundation

class CodeCoverageHtmlSplitter {
    enum Error: Swift.Error {
        case fileHandle
        case unexpectedFormat
    }
    
    private let url: URL
    private let lineDelimiter = "\n".data(using: .utf8)
    
    init(url: URL) {
        self.url = url
    }
    
    func split(destinationUrl: URL, basePath: String) throws {
        let reader = StreamReader(url: url)
        
        var pendingRows = [String]()
        while let line = reader?.nextLine() {
            if pendingRows.count > 0, line.contains("<!doctype html>") {
                let marker = "<!doctype html>"
                let components = line.components(separatedBy: marker)
                guard components.count == 2 else {
                    throw Error.unexpectedFormat
                }
                pendingRows.append(components[0])
                
                let filename = try extractFilename(line: components[0]).replacingOccurrences(of: basePath, with: "") + ".html"
                let fileUrl = destinationUrl.appendingPathComponent(filename)
                
                try FileManager.default.createDirectory(at: fileUrl.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
                FileManager.default.createFile(atPath: fileUrl.path, contents: nil, attributes: nil)
                
                try writeCoverageFile(url: fileUrl, lines: pendingRows)
                
                pendingRows = [marker + components[1]]
            } else {
                pendingRows.append(line)
            }
        }
    }
    
    private func extractFilename(line: String) throws -> String {
        let head = String(line.prefix(300))
        let groups = try head.capturedGroups(withRegexString: #"<div class='source-name-title'><pre>(.*?)<\/pre>"#)
        guard groups.count == 1 else {
            throw Error.unexpectedFormat
        }
        
        return groups[0]
    }
    
    private func writeCoverageFile(url: URL, lines: [String]) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        
        for line in lines {
            handle.write(Data(line.utf8))
        }
    }
}
