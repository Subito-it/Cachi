import HTTPKit
import Vaux

extension HTML {
    func httpResponse() -> HTTPResponse {
        var str = ""
        let vaux = Vaux()
        vaux.outputLocation = .string(&str)
        do {
            try vaux.render(self)
            return HTTPResponse(body: HTTPBody(string: str))
        } catch let error {
            print("HTML rendering failed: \(error.localizedDescription)")
            return HTTPResponse(status: .internalServerError, body: HTTPBody(staticString: "Ouch..."))
        }
    }
}
