import HTTPKit

protocol Routable: CustomStringConvertible {
    var path: String { get }
    
    func respond(to req: HTTPRequest, with promise: EventLoopPromise<HTTPResponse>)
}

struct AnyRoutable: Routable {
    private let box: Routable
    
    var path: String { box.path }
    var description: String { box.description }
    
    init(_ routable: Routable) {
        self.box = routable
    }
    
    func respond(to req: HTTPRequest, with promise: EventLoopPromise<HTTPResponse>) {
        box.respond(to: req, with: promise)
    }
}
