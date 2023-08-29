import Vapor

protocol Routable {
    static var path: String { get }
    var description: String { get }
    var method: HTTPMethod { get }

    func respond(to request: Request) throws -> Response
}
