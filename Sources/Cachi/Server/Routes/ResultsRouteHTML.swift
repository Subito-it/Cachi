import Foundation
import HTTPKit
import os
import Vaux

struct ResultsRouteHTML: Routable {    
    let path: String = "/html/results"
    let description: String = "List of results in html"
        
    func respond(to req: HTTPRequest, with promise: EventLoopPromise<HTTPResponse>) {
        os_log("HTML results request received", log: .default, type: .info)
        
        let results = State.shared.resultBundles
        
        guard let components = URLComponents(url: req.url, resolvingAgainstBaseURL: false) else {
            let res = HTTPResponse(status: .notFound, body: HTTPBody(staticString: "Not found..."))
            return promise.succeed(res)
        }

        let backUrl = components.queryItems?.backUrl ?? ""
        
        let document = html {
            head {
                title("Cachi - Results")
                meta().attr("charset", "utf-8")
                linkStylesheet(url: "/css?main")
            }
            body {
                div {
                    div { floatingHeaderHTML(results: results, backUrl: backUrl) }.class("sticky-top").id("top-bar")
                    div { resultsTableHTML(results: results, backUrl: backUrl) }
                }.class("main-container background")
            }
        }
        
        return promise.succeed(document.httpResponse())
    }
    
    private func floatingHeaderHTML(results: [ResultBundle], backUrl: String) -> HTML {
        let params = "back_url=\(currentUrl(backUrl: backUrl).hexadecimalRepresentation)"
        switch State.shared.state {
        case let .parsing(progress):
            return div {
                div { "Parsing \(Int(progress * 100))% done" }.alignment(.center).class("warning-container bold")
                div { "Results" }.class("header row light-bordered-container indent1")
                if results.count > 0 {
                    div { link(url: "/html/results_stat?\(params)") { "Stats" }.class("button") }.class("row indent2 background")
                }
            }
        default:
            return div {
                div { "Results" }.class("header row light-bordered-container indent1")
                if results.count > 0 {
                    div { link(url: "/html/results_stat?\(params)") { "Stats" }.class("button") }.class("row indent2 background")
                }
            }
        }
    }
    
    private func resultsTableHTML(results: [ResultBundle], backUrl: String) -> HTML {
        let days = results.map { DateFormatter.dayMonthFormatter.string(from: $0.date) }.uniques
        
        if days.count == 0 {
            return table {
                return tableRow {
                      tableData {
                        div { "No results found" }.class("bold").inlineBlock()
                      }.class("row indent2")
                      tableData { "&nbsp;" }
                  }.class("dark-bordered-container")
            }
        } else {
            return table {
                forEach(days) { day in
                    let dayResults = results.filter { DateFormatter.dayMonthFormatter.string(from: $0.date) == day }
                    
                    return HTMLBuilder.buildBlock(
                        tableRow {
                            tableData {
                                div { day }.class("bold").inlineBlock()
                            }.class("row indent2")
                            tableData { "&nbsp;" }
                        }.class("dark-bordered-container"),
                        forEach(dayResults) { result in
                            tableRow {
                                let resultTitle = result.htmlTitle()
                                let resultSubtitle = result.htmlSubtitle()
                                let resultDevice = "\(result.tests.first!.deviceModel) (\(result.tests.first!.deviceOs))"
                                
                                let testsPassed = result.testsPassed
                                let testsFailed = result.testsUniquelyFailed
                                let testsRetried = result.testsFailedRetring
                                let testsCount = testsPassed.count + testsFailed.count
                                
                                let testPassedString = testsPassed.count > 0 ? "\(testsPassed.count) passed (\(testsPassed.count.percentageString(total: testsCount, decimalDigits: 1)))" : ""
                                let testFailedString = testsFailed.count > 0 ? "\(testsFailed.count) failed (\(testsFailed.count.percentageString(total: testsCount, decimalDigits: 1)))" : ""
                                let testRetriedString = testsRetried.count > 0 ? "\(testsRetried.count) retries (\(testsRetried.count.percentageString(total: testsCount + testsRetried.count, decimalDigits: 1)))" : ""
                                
                                return HTMLBuilder.buildBlock(
                                    tableData {
                                        self.linkToResultDetail(result: result, backUrl: backUrl) {
                                            image(url: result.htmlStatusImageUrl())
                                                .attr("title", result.htmlStatusTitle())
                                                .iconStyleAttributes(width: 14)
                                                .class("icon")
                                            resultTitle
                                            div { resultSubtitle }.class("color-subtext indent2")
                                            div { resultDevice }.class("color-subtext indent2")
                                        }.class(result.htmlTextColor())
                                    }.class("row indent3"),
                                    tableData {
                                        self.linkToResultDetail(result: result, backUrl: backUrl) {
                                            div { testPassedString }.class("color-subtext").inlineBlock()
                                            div { testFailedString }.class("color-subtext").inlineBlock()
                                            div { testRetriedString }.class("color-subtext").inlineBlock()
                                        }
                                    }.alignment(.left).class("row indent1")
                                )
                            }.class("light-bordered-container")
                        }
                    )
                }
            }
        }
    }
    
    private func currentUrl(backUrl: String) -> String {
        return "/"
    }
    
    private func linkToResultDetail(result: ResultBundle, backUrl: String, @HTMLBuilder child: () -> HTML) -> HTML {
        return link(url: "/html/result?id=\(result.identifier)&back_url=\(currentUrl(backUrl: backUrl).hexadecimalRepresentation)") {
            child()
        }
    }
}
