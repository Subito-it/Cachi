import Foundation

public struct AttachmentViewerConfiguration: Hashable {
    public enum Error: Swift.Error, LocalizedError {
        case invalidFormat(String)
        case missingExtension(String)
        case missingScriptPath(String)
        case scriptNotFound(String)
        case scriptIsDirectory(String)
        case duplicateExtension(String)

        public var errorDescription: String? {
            switch self {
            case let .invalidFormat(value):
                "Invalid attachment viewer mapping '\(value)'. Expected syntax 'extension:javascript_file'."
            case let .missingExtension(value):
                "Missing file extension in attachment viewer mapping '\(value)'."
            case let .missingScriptPath(value):
                "Missing JavaScript file path in attachment viewer mapping '\(value)'."
            case let .scriptNotFound(path):
                "Attachment viewer script not found at path '\(path)'."
            case let .scriptIsDirectory(path):
                "Attachment viewer script path '\(path)' is a directory. Please provide a file."
            case let .duplicateExtension(ext):
                "Multiple attachment viewers configured for extension '\(ext)'. Each extension can be mapped only once."
            }
        }
    }

    public let fileExtension: String
    public let scriptUrl: URL

    public init(argumentValue: String, fileManager: FileManager = .default) throws {
        let components = argumentValue.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard components.count == 2 else {
            throw Error.invalidFormat(argumentValue)
        }

        let rawExtension = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let rawScriptPath = components[1].trimmingCharacters(in: .whitespacesAndNewlines)

        guard !rawExtension.isEmpty else {
            throw Error.missingExtension(argumentValue)
        }
        guard !rawScriptPath.isEmpty else {
            throw Error.missingScriptPath(argumentValue)
        }

        let normalizedExtension = rawExtension.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        guard !normalizedExtension.isEmpty else {
            throw Error.missingExtension(argumentValue)
        }

        let expandedPath = NSString(string: rawScriptPath).expandingTildeInPath
        let scriptUrl = URL(fileURLWithPath: expandedPath)

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: scriptUrl.path, isDirectory: &isDirectory) else {
            throw Error.scriptNotFound(scriptUrl.path)
        }
        guard !isDirectory.boolValue else {
            throw Error.scriptIsDirectory(scriptUrl.path)
        }

        self.fileExtension = normalizedExtension
        self.scriptUrl = scriptUrl.standardizedFileURL
    }
}
