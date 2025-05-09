import Foundation
import os
import Vapor
import Vaux
import ZippyJSON

struct ResultRouteHTML: Routable {
    static let path: String = "/html/result"

    let method = HTTPMethod.GET
    let description: String = "Detail of result in html (pass identifier)"

    private let baseUrl: URL
    private let depth: Int
    private let mergeResults: Bool

    init(baseUrl: URL, depth: Int, mergeResults: Bool) {
        self.baseUrl = baseUrl
        self.depth = depth
        self.mergeResults = mergeResults
    }

    func respond(to req: Request) throws -> Response {
        os_log("HTML result request received", log: .default, type: .info)

        guard let components = req.urlComponents(),
              let queryItems = components.queryItems,
              let resultIdentifier = queryItems.first(where: { $0.name == "id" })?.value
        else {
            return Response(status: .notFound, body: Response.Body(stringLiteral: "Not found..."))
        }

        let benchId = benchmarkStart()
        defer { os_log("Result bundle with id '%@' fetched in %fms", log: .default, type: .info, resultIdentifier, benchmarkStop(benchId)) }

        guard let result = State.shared.result(identifier: resultIdentifier) else {
            let pendingResultBundles = State.shared.pendingResultBundles(baseUrl: baseUrl, depth: depth, mergeResults: mergeResults)
            if pendingResultBundles.contains(where: { $0.identifier == resultIdentifier }) {
                return Response(status: .notFound, body: Response.Body(stringLiteral: "Result is being parsed, please wait..."))
            } else {
                return Response(status: .notFound, body: Response.Body(stringLiteral: "Not found..."))
            }
        }

        let state = RouteState(queryItems: queryItems)
        let backUrl = queryItems.backUrl

        let document = html {
            head {
                title("Cachi - Result \(result.identifier)")
                meta().attr("charset", "utf-8")
                linkStylesheet(url: "/css?main")
            }
            body {
                div {
                    div { floatingHeaderHTML(result: result, state: state, backUrl: backUrl) }.class("sticky-top").id("top-bar")
                    div { resultsTableHTML(result: result, state: state, backUrl: backUrl) }
                }.class("main-container background")
            }
        }

        return document.httpResponse()
    }

    static func urlString(resultIdentifier: String, backUrl: String) -> String {
        var components = URLComponents(string: path)!
        components.queryItems = [
            .init(name: "id", value: resultIdentifier),
            .init(name: "back_url", value: backUrl.hexadecimalRepresentation)
        ]

        components.queryItems = components.queryItems?.filter { !($0.value?.isEmpty ?? true) }

        return components.url!.absoluteString
    }

    private func floatingHeaderHTML(result: ResultBundle, state: RouteState, backUrl: String) -> HTML {
        let resultTitle = result.htmlTitle()
        let resultSubtitle = result.htmlSubtitle()
        let resultDate = DateFormatter.fullDateFormatter.string(from: result.testStartDate)

        let resultDevice = "\(result.tests.first!.deviceModel) (\(result.tests.first!.deviceOs))"

        return div {
            div {
                div {
                    link(url: backUrl) {
                        image(url: ImageRoute.arrowLeftImageUrl())
                            .iconStyleAttributes(width: 8)
                            .class("icon color-svg-text")
                    }
                    resultTitle
                }.class("header")
                div { resultSubtitle }.class("color-subtext subheader")
                div { resultDate }.class("color-subtext indent1").floatRight()
                div { resultDevice }.class("color-subtext subheader")
            }.class("row light-bordered-container indent1")
            div {
                div {
                    switch state.showFilter {
                    case .all:
                        var testsCount = result.testsPassed.count + result.testsUniquelyFailed.count
                        var testsFailedCount = result.testsFailed.count

                        if state.showSystemFailures {
                            testsCount += result.testsFailedBySystem.count
                            testsFailedCount += result.testsFailedBySystem.count
                        }

                        var blocks = [HTML]()

                        blocks.append(div { "\(testsCount) tests" }.inlineBlock())
                        if testsFailedCount > 0 {
                            blocks += [div { " with \(testsFailedCount) failures" }.inlineBlock(),
                                       div { " (\(testsFailedCount.percentageString(total: testsCount, decimalDigits: 1)))" }.inlineBlock()]
                        }
                        blocks.append(div { "in \(hoursMinutesSeconds(in: result.totalExecutionTime))" }.inlineBlock())

                        return HTMLBuilder.buildBlocks(blocks)
                    case .passed:
                        return div { "\(result.testsPassed.count) tests" }.inlineBlock()
                    case .failed:
                        var testsFailedCount = result.testsFailedExcludingRetries().count
                        if state.showSystemFailures {
                            testsFailedCount += result.testsFailedBySystem.count
                        }

                        return div { "\(testsFailedCount) tests" }.inlineBlock()
                    case .retried:
                        return div { "\(result.testsFailedRetring.count) tests" }.inlineBlock()
                    }
                }.class("button-padded color-subtext").floatRight()

                div {
                    var blocks = [HTML]()

                    var mState = state
                    let linkForState: (RouteState) -> HTML = { linkState in
                        link(url: Self.urlString(result: result, state: linkState, backUrl: backUrl)) { linkState.showFilter.rawValue.capitalized }.class(state.showFilter == linkState.showFilter ? "button-selected" : "button")
                    }

                    mState.showFilter = .all
                    blocks.append(linkForState(mState))
                    if result.testsPassed.count > 0 {
                        mState.showFilter = .passed
                        blocks.append(linkForState(mState))
                    }
                    if result.testsUniquelyFailed.count > 0 {
                        mState.showFilter = .failed
                        blocks.append(linkForState(mState))
                    }
                    if result.testsRepeated.count > 0 {
                        mState.showFilter = .retried
                        blocks.append(linkForState(mState))
                    }

                    if result.testsFailed.count > 0 {
                        if state.showFilter != .passed {
                            var mState = state
                            mState.showFailureMessage.toggle()
                            blocks.append("&nbsp;&nbsp;&nbsp;&nbsp;")
                            blocks.append(link(url: Self.urlString(result: result, state: mState, backUrl: backUrl)) { "Show failure message" }.class(state.showFailureMessage ? "button-selected" : "button"))
                        }
                    }

                    if result.testsFailedBySystem.count > 0 {
                        if state.showFilter == .all || state.showFilter == .failed {
                            var mState = state
                            mState.showSystemFailures.toggle()
                            blocks.append(link(url: Self.urlString(result: result, state: mState, backUrl: backUrl)) { "Show system failures" }.class(state.showSystemFailures ? "button-selected" : "button"))
                        }
                    }

                    if result.codeCoverageSplittedHtmlBaseUrl != nil {
                        blocks.append("&nbsp;&nbsp;&nbsp;&nbsp;")
                        blocks.append(link(url: CoverageRouteHTML.urlString(resultIdentifier: result.identifier, backUrl: Self.urlString(result: result, state: state, backUrl: backUrl))) { "Coverage" }.class("button"))
                    }

                    return HTMLBuilder.buildBlocks(blocks)
                }
            }.class("row light-bordered-container indent2")
        }
    }

    private func resultsTableHTML(result: ResultBundle, state: RouteState, backUrl: String) -> HTML {
        var tests: [ResultBundle.Test] = switch state.showFilter {
        case .failed:
            result.testsFailedExcludingRetries()
        case .passed:
            result.testsPassed
        case .retried:
            result.testsFailedRetring
        default:
            result.tests
        }

        if state.showSystemFailures, state.showFilter != .retried {
            tests += result.testsFailedBySystem
        }

        let groupNames = Set(tests.map(\.groupName)).sorted()

        let testFailureMessages = state.showFailureMessage ? tests.failureMessages() : [:]

        return table {
            columnGroup(styles: [TableColumnStyle(span: 1, styles: [StyleAttribute(key: "wrap-word", value: "break-word")]),
                                 TableColumnStyle(span: 1, styles: [StyleAttribute(key: "width", value: "100px")])])

            tableRow {
                tableHeadData { "Test" }.alignment(.left).scope(.column).class("row dark-bordered-container indent1")
                tableHeadData { "Duration" }.alignment(.left).scope(.column).class("row dark-bordered-container")
                tableHeadData { "&nbsp;" }.scope(.column).class("row dark-bordered-container")
            }.id("table-header")

            forEach(groupNames) { group in
                let tests = tests.filter { $0.groupName == group }.sorted(by: { "\($0.name)-\($0.testStartDate.timeIntervalSince1970)" < "\($1.name)-\($1.testStartDate.timeIntervalSince1970)" })
                let testsCount = tests.count
                let testsFailedCount = tests.filter { $0.status == .failure }.count
                let testsPassedCount = testsCount - testsFailedCount

                let testPassedString = testsPassedCount > 0 ? "\(testsPassedCount) passed (\(testsPassedCount.percentageString(total: testsCount, decimalDigits: 1)))" : ""
                let testFailedString = testsFailedCount > 0 ? "\(testsFailedCount) failed (\(testsFailedCount.percentageString(total: testsCount, decimalDigits: 1)))" : ""

                let testDuration = hoursMinutesSeconds(in: tests.reduce(0) { $0 + $1.duration })
                let testDurationString = "in \(testDuration)"

                return HTMLBuilder.buildBlock(
                    tableRow {
                        tableData {
                            div { group }.class("bold").inlineBlock()
                            div { testPassedString }.class("color-subtext").inlineBlock()
                            div { testFailedString }.class("color-subtext").inlineBlock()
                            div { testDurationString }.class("color-subtext").inlineBlock()
                        }.class("row indent2")
                        tableData { "&nbsp;" }
                        tableData { "&nbsp;" }
                    }.class("dark-bordered-container"),
                    forEach(tests) { test in
                        tableRow {
                            let backUrl = Self.urlString(result: result, state: state, backUrl: backUrl)
                            let testRouteUrlString = TestRouteHTML.urlString(testSummaryIdentifier: test.summaryIdentifier, source: nil, backUrl: backUrl)
                            tableData {
                                link(url: testRouteUrlString) {
                                    image(url: result.htmlStatusImageUrl(for: test))
                                        .attr("title", result.htmlStatusTitle(for: test))
                                        .iconStyleAttributes(width: 14)
                                        .class("icon")
                                    test.name
                                    if test.status == .failure, state.showFailureMessage, let failureMessage = testFailureMessages[test.identifier] {
                                        div { failureMessage }.class("row indent3 background color-error")
                                    }
                                }.class(result.htmlTextColor(for: test))
                            }.class("row indent3")
                            tableData {
                                link(url: testRouteUrlString) {
                                    hoursMinutesSeconds(in: test.duration)
                                }.class("color-text")
                            }.alignment(.left).class("row indent1")
                            tableData { "&nbsp;" }
                        }.class("light-bordered-container")
                    }
                )
            }
        }.style([StyleAttribute(key: "table-layout", value: "fixed")])
    }

    private static func urlString(result: ResultBundle, state: RouteState, backUrl: String) -> String {
        var components = URLComponents(string: path)!
        components.queryItems = [
            .init(name: "id", value: result.identifier),
            .init(name: "back_url", value: backUrl.hexadecimalRepresentation)
        ]

        components.queryItems = components.queryItems?.filter { !($0.value?.isEmpty ?? true) }

        return components.url!.absoluteString + state.description
    }
}

private extension ResultBundle {
    func testsFailedExcludingRetries() -> [ResultBundle.Test] {
        testsFailed.filter { test in testsUniquelyFailed.contains(where: { test.matches($0) }) }
    }
}

private extension ResultRouteHTML {
    struct RouteState: Codable, CustomStringConvertible {
        static let key = "state"

        enum ShowFilter: String, Codable { case all, passed, failed, retried }

        var showFilter: ShowFilter
        var showFailureMessage: Bool
        var showSystemFailures: Bool

        init(queryItems: [URLQueryItem]?) {
            self.init(hexadecimalRepresentation: queryItems?.first(where: { $0.name == Self.key })?.value)
        }

        init(hexadecimalRepresentation: String?) {
            if let hexadecimalRepresentation,
               let data = Data(hexadecimalRepresentation: hexadecimalRepresentation),
               let state = try? ZippyJSONDecoder().decode(RouteState.self, from: data) {
                self.showFilter = state.showFilter
                self.showFailureMessage = state.showFailureMessage
                self.showSystemFailures = state.showSystemFailures
            } else {
                self.showFilter = .all
                self.showFailureMessage = false
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
