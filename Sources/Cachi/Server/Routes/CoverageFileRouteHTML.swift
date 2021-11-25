import Foundation
import HTTPKit
import os
import Vaux
import CachiKit


struct CoverageFileRouteHTML: Routable {
    let path: String = "/html/coverage-file"
    let description: String = "Coverage file details in html (pass identifier)"
        
    func respond(to req: HTTPRequest, with promise: EventLoopPromise<HTTPResponse>) {
        os_log("HTML coverage request received", log: .default, type: .info)

        let resultBundles = State.shared.resultBundles

        guard let components = URLComponents(url: req.url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems,
              let resultIdentifier = queryItems.first(where: { $0.name == "id" })?.value,
              let path = queryItems.first(where: { $0.name == "path" })?.value,
              let resultBundle = resultBundles.first(where: { $0.identifier == resultIdentifier }),
              let fileCoverageHtmlUrl = resultBundle.codeCoverageSplittedHtmlBaseUrl?.appendingPathComponent(path + ".html"),
              let fileCoverageHtml = try? String(contentsOf: fileCoverageHtmlUrl) else {
            let res = HTTPResponse(status: .notFound, body: HTTPBody(staticString: "Not found..."))
            return promise.succeed(res)
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
        
        return promise.succeed(document.httpResponse())
    }
    
    private func floatingHeaderHTML(result: ResultBundle, path: String) -> HTML {
        let resultTitle = result.htmlTitle()
        let resultSubtitle = result.htmlSubtitle()
        let resultDate = DateFormatter.fullDateFormatter.string(from: result.testStartDate)
        
        let resultDevice = "\(result.tests.first!.deviceModel) (\(result.tests.first!.deviceOs))"
                
        return div {
            div {
                div {
                    link(url: "javascript:history.back()") {
                        image(url: "/image?imageArrorLeft")
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
