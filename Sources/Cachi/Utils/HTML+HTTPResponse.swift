import Vapor
import Vaux

extension HTML {
    func httpResponse() -> Response {
        var str = ""
        let vaux = Vaux()
        vaux.outputLocation = .string(&str)
        do {
            try vaux.render(self)
            return Response(body: Response.Body(string: str))
        } catch {
            print("HTML rendering failed: \(error.localizedDescription)")
            return Response(status: .internalServerError, body: Response.Body(stringLiteral: "Ouch..."))
        }
    }
}
