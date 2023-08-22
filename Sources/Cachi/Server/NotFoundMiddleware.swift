import Vapor

struct NotFoundMiddleware: Middleware {
    func respond(to request: Request, chainingTo next: Responder) -> EventLoopFuture<Response> {
        next.respond(to: request).flatMap { response in
            if response.status == .notFound {
                return request.eventLoop.makeSucceededFuture(
                    Response(status: .notFound, body: ":-( nothing here")
                )
            }
            return request.eventLoop.makeSucceededFuture(response)
        }
    }
}
