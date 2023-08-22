import Vapor

extension Request {
    func urlComponents() -> URLComponents? {
        URLComponents(string: url.string)
    }
}
