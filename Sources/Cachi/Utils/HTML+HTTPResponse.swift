import Vapor
import Vaux

private final class HTMLResponseOutputStream: TextOutputStream {
    private var chunks = [String]()

    func write(_ string: String) {
        chunks.append(string)
    }

    var value: String {
        chunks.joined()
    }
}

extension HTML {
    func httpResponse() -> Response {
        let output = HTMLResponseOutputStream()
        let vaux = Vaux(output: .custom(output))
        do {
            try vaux.render(self)
            return Response(body: Response.Body(string: output.value))
        } catch {
            print("HTML rendering failed: \(error.localizedDescription)")
            return Response(status: .internalServerError, body: Response.Body(stringLiteral: "Ouch..."))
        }
    }
}
