import CachiKit
import Foundation
import os
import Vapor
import Vaux

struct CoverageFileRouteHTML: Routable {
    static let path: String = "/html/coverage-file"

    let method = HTTPMethod.GET
    let description: String = "Coverage file details in html (pass identifier)"

    func respond(to req: Request) throws -> Response {
        os_log("HTML coverage request received", log: .default, type: .info)

        let resultBundles = State.shared.resultBundles

        guard let components = req.urlComponents(),
              let queryItems = components.queryItems,
              let resultIdentifier = queryItems.first(where: { $0.name == "id" })?.value,
              let path = queryItems.first(where: { $0.name == "path" })?.value,
              let resultBundle = resultBundles.first(where: { $0.identifier == resultIdentifier }),
              let fileCoverageHtmlUrl = resultBundle.codeCoverageSplittedHtmlBaseUrl?.appendingPathComponent(path + ".html"),
              let fileCoverageHtml = try? String(contentsOf: fileCoverageHtmlUrl)
        else {
            return Response(status: .notFound, body: Response.Body(stringLiteral: "Not found..."))
        }

        let document = html {
            head {
                title("Cachi - Test result")
                meta().attr("charset", "utf-8")
                linkStylesheet(url: "/css?main")
            }
            body {
                div {
                    div { floatingHeaderHTML(result: resultBundle, path: path) }.class("sticky-top").id("top-bar")

                    div { RawHTML(rawContent: fileCoverageHtml) }
                }.class("main-container background")
            }
        }

        return document.httpResponse()
    }

    static func urlString(resultIdentifier: String, path: String) -> String {
        var components = URLComponents(string: path)!
        components.queryItems = [
            .init(name: "id", value: resultIdentifier),
            .init(name: "path", value: path),
        ]

        components.queryItems = components.queryItems?.filter { !($0.value?.isEmpty ?? true) }

        return components.url!.absoluteString
    }

    private func floatingHeaderHTML(result: ResultBundle, path _: String) -> HTML {
        let resultTitle = result.htmlTitle()
        let resultSubtitle = result.htmlSubtitle()
        let resultDate = DateFormatter.fullDateFormatter.string(from: result.testStartDate)

        let resultDevice = "\(result.tests.first!.deviceModel) (\(result.tests.first!.deviceOs))"

        return div {
            div {
                div {
                    link(url: "javascript:history.back()") {
                        image(url: ImageRoute.arrowLeftImageUrl())
                            .iconStyleAttributes(width: 8)
                            .class("icon color-svg-text")
                    }
                    resultTitle
                }.class("header")
                div { resultSubtitle }.class("color-subtext subheader")
                div { resultDate }.class("color-subtext subheader").floatRight()
                div { resultDevice }.class("color-subtext subheader")
            }.class("row light-bordered-container indent1")
        }
    }
}
