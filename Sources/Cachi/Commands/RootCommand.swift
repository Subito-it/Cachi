import Foundation
import Bariloche

class RootCommand: Command {
    let usage: String? = "Cachi parses Xcode 11's .xcresult bundles making results accessible via a web interface. Check documentation for additional details about the exposed API"
    
    let pathArgument = Argument<String>(name: "path", kind: .positional, optional: false, help: "Path to location containing .xcresult bundles (will search recursively)")
    let parseDepthArgument = Argument<Int>(name: "level", kind: .named(short: "d", long: "search_depth"), optional: true, help: "Location path traversing depth (Default: 2)")
    let port = Argument<Int>(name: "number", kind: .named(short: "p", long: "port"), optional: false, help: "Web interface port")
        
    func run() -> Bool {
        let basePath = NSString(string: pathArgument.value!).expandingTildeInPath // 🤷‍♂️
        var baseUrl: URL
        if basePath.hasPrefix(".") {
            baseUrl = Bundle.main.bundleURL.deletingLastPathComponent()
            baseUrl.appendPathComponent(basePath)
        } else {
            baseUrl = URL(fileURLWithPath: basePath)
        }
        baseUrl.standardize()
        
        let parseDepth = parseDepthArgument.value ?? 2

        guard FileManager.default.fileExists(atPath: baseUrl.path) else {
            print("Path '\(baseUrl.standardized)' does not exist!\n")
            return false
        }
        
        DispatchQueue.global(qos: .userInteractive).async {
            State.shared.parse(baseUrl: baseUrl, depth: parseDepth)
        }
                
        let server = Server(port: port.value!, baseUrl: baseUrl, parseDepth: parseDepth)
        do {
            try server.listen()
        } catch {
            print("Failed listening on port \(port.value!).\n\n\(error)")
        }
        return true
    }
}
