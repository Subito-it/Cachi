import Vapor

protocol Routable {
    var path: String { get }
    var description: String { get }
    var method: HTTPMethod { get }

    func respond(to request: Request) throws -> Response
}
