import Foundation
import os
import Vapor
import Vaux
import ZippyJSON

struct ResultsRouteHTML: Routable {
    static let path: String = "/html/results"

    let method = HTTPMethod.GET
    let description: String = "List of results in html"

    func respond(to req: Request) throws -> Response {
        os_log("HTML results request received", log: .default, type: .info)

        let results = State.shared.resultBundles

        guard let components = req.urlComponents() else {
            return Response(status: .notFound, body: Response.Body(stringLiteral: "Not found..."))
        }

        let state = RouteState(queryItems: components.queryItems)

        let document = html {
            head {
                title("Cachi - Results")
                meta().attr("charset", "utf-8")
                linkStylesheet(url: "/css?main")
            }
            body {
                div {
                    div { floatingHeaderHTML(results: results, state: state) }.class("sticky-top").id("top-bar")
                    div { resultsTableHTML(results: results, state: state) }
                }.class("main-container background")
            }
        }

        return document.httpResponse()
    }

    private func floatingHeaderHTML(results: [ResultBundle], state: RouteState) -> HTML {
        var blocks = [HTML]()

        switch State.shared.state {
        case let .parsing(progress):
            blocks.append(div { "Parsing \(Int(progress * 100))% done" }.alignment(.center).class("warning-container bold"))
        default:
            break
        }

        blocks.append(div { "Results" }.class("header row light-bordered-container indent1"))

        if results.count > 0 {
            var buttonBlocks = [HTML]()

            buttonBlocks.append(link(url: ResultsStatRouteHTML.urlString(backUrl: currentUrl(state: state))) { "Stats" }.class("button"))

            var mState = state
            mState.showSystemFailures.toggle()

            buttonBlocks.append(link(url: currentUrl(state: mState)) { "Show system failures" }.class(state.showSystemFailures ? "button-selected" : "button"))

            blocks.append(div { HTMLBuilder.buildBlocks(buttonBlocks) }.class("row indent2 background"))
        }

        return HTMLBuilder.buildBlocks(blocks)
    }

    private func resultsTableHTML(results: [ResultBundle], state: RouteState) -> HTML {
        let days = results.map { DateFormatter.dayMonthFormatter.string(from: $0.testStartDate) }.uniques

        if days.count == 0 {
            return table {
                tableRow {
                    tableData {
                        div { "No results found" }.class("bold").inlineBlock()
                    }.class("row indent2")
                    tableData { "&nbsp;" }
                }.class("dark-bordered-container")
            }
        } else {
            return table {
                forEach(days) { day in
                    let dayResults = results.filter { DateFormatter.dayMonthFormatter.string(from: $0.testStartDate) == day }

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
                                let testsFailedBySystem = state.showSystemFailures ? result.testsFailedBySystem : []
                                let testsRetried = result.testsFailedRetring
                                let testsCount = testsPassed.count + testsFailed.count
                                let testCrashCount = result.testsCrashCount

                                let testPassedString = testsPassed.count > 0 ? "\(testsPassed.count) passed (\(testsPassed.count.percentageString(total: testsCount, decimalDigits: 1)))" : ""
                                let testFailedString = testsFailed.count > 0 ? "\(testsFailed.count) failed (\(testsFailed.count.percentageString(total: testsCount, decimalDigits: 1)))" : ""
                                let testFailedBySystemString = testsFailedBySystem.count > 0 ? "\(testsFailedBySystem.count) system failures (\(testsFailedBySystem.count.percentageString(total: testsCount, decimalDigits: 1)))" : ""
                                let testRetriedString = testsRetried.count > 0 ? "\(testsRetried.count) retries (\(testsRetried.count.percentageString(total: testsCount + testsRetried.count, decimalDigits: 1)))" : ""
                                let testCrashCountString = testCrashCount > 0 ? "\(testCrashCount) crashes (\(testCrashCount.percentageString(total: testsCount, decimalDigits: 1)))" : ""

                                return HTMLBuilder.buildBlock(
                                    tableData {
                                        linkToResultDetail(result: result, state: state) {
                                            image(url: result.htmlStatusImageUrl(includeSystemFailures: state.showSystemFailures))
                                                .attr("title", result.htmlStatusTitle())
                                                .iconStyleAttributes(width: 14)
                                                .class("icon")
                                            resultTitle
                                            div { resultSubtitle }.class("color-subtext indent2")
                                            div { resultDevice }.class("color-subtext indent2")
                                        }.class(result.htmlTextColor())
                                    }.class("row indent3"),
                                    tableData {
                                        linkToResultDetail(result: result, state: state) {
                                            div { testPassedString }.class("color-subtext")
                                            div { testFailedString }.class("color-subtext").inlineBlock()
                                            div { testRetriedString }.class("color-subtext").inlineBlock()
                                            div { testFailedBySystemString }.class("color-subtext")
                                            div { testCrashCountString }.class("color-subtext")
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

    private func currentUrl(state: RouteState) -> String {
        "/?\(state)"
    }

    private func linkToResultDetail(result: ResultBundle, state: RouteState, @HTMLBuilder child: () -> HTML) -> HTML {
        link(url: ResultRouteHTML.urlString(resultIdentifier: result.identifier, backUrl: currentUrl(state: state))) {
            child()
        }
    }
}

private extension ResultsRouteHTML {
    struct RouteState: Codable, CustomStringConvertible {
        static let key = "state"

        var showSystemFailures: Bool

        init(queryItems: [URLQueryItem]?) {
            self.init(hexadecimalRepresentation: queryItems?.first(where: { $0.name == Self.key })?.value)
        }

        init(hexadecimalRepresentation: String?) {
            if let hexadecimalRepresentation,
               let data = Data(hexadecimalRepresentation: hexadecimalRepresentation),
               let state = try? ZippyJSONDecoder().decode(RouteState.self, from: data) {
                self.showSystemFailures = state.showSystemFailures
            } else {
                self.showSystemFailures = false
            }
        }

        var description: String {
            guard let data = try? JSONEncoder().encode(self),
                  let hexRepresentation = data.hexadecimalRepresentation
            else {
                return ""
            }

            return "&\(Self.key)=" + hexRepresentation
        }
    }
}
