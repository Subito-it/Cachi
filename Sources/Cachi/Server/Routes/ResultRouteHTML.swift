import Foundation
import HTTPKit
import os
import Vaux

struct ResultRouteHTML: Routable {    
    let path: String = "/html/result"
    let description: String = "Detail of result in html (pass identifier)"
    
    private let baseUrl: URL
    private let depth: Int
    private let mergeResults: Bool
    
    init(baseUrl: URL, depth: Int, mergeResults: Bool) {
        self.baseUrl = baseUrl
        self.depth = depth
        self.mergeResults = mergeResults
    }
        
    func respond(to req: HTTPRequest, with promise: EventLoopPromise<HTTPResponse>) {
        os_log("HTML result request received", log: .default, type: .info)
                
        guard let components = URLComponents(url: req.url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems,
              let resultIdentifier = queryItems.first(where: { $0.name == "id" })?.value else {
            let res = HTTPResponse(status: .notFound, body: HTTPBody(staticString: "Not found..."))
            return promise.succeed(res)
        }
                
        let benchId = benchmarkStart()
        defer { os_log("Result bundle with id '%@' fetched in %fms", log: .default, type: .info, resultIdentifier, benchmarkStop(benchId)) }
                
        guard let result = State.shared.result(identifier: resultIdentifier) else {
            let pendingResultBundles = State.shared.pendingResultBundles(baseUrl: baseUrl, depth: depth, mergeResults: mergeResults)
            if pendingResultBundles.contains(where: { $0.identifier == resultIdentifier }) {
                let res = HTTPResponse(status: .notFound, body: HTTPBody(staticString: "Result is being parsed, please wait..."))
                return promise.succeed(res)
            } else {
                let res = HTTPResponse(status: .notFound, body: HTTPBody(staticString: "Not found..."))
                return promise.succeed(res)
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
                    div { floatingHeaderHTML(result: result, state:state, backUrl: backUrl) }.class("sticky-top").id("top-bar")
                    div { resultsTableHTML(result: result, state:state, backUrl: backUrl) }
                }.class("main-container background")
            }
        }
        
        return promise.succeed(document.httpResponse())
    }
    
    private func floatingHeaderHTML(result: ResultBundle, state: RouteState, backUrl: String) -> HTML {
        let resultTitle = result.htmlTitle()
        let resultSubtitle = result.htmlSubtitle()
        let resultDate = DateFormatter.fullDateFormatter.string(from: result.date)
        
        let resultDevice = "\(result.tests.first!.deviceModel) (\(result.tests.first!.deviceOs))"
                
        return div {
            div {
                div {
                    link(url: backUrl) {
                        image(url: "/image?imageArrorLeft")
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
                        let testsCount = result.testsPassed.count + result.testsUniquelyFailed.count
                        let testsFailedCount = result.testsFailed.count
                        
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
                        return div { "\(result.testsFailedExcludingRetries().count) tests" }.inlineBlock()
                    case .retried:
                        return div { "\(result.testsFailedRetring.count) tests" }.inlineBlock()
                    }
                }.class("button-padded color-subtext").floatRight()
                
                div {
                    var blocks = [HTML]()
                    
                    var mState = state
                    let linkForState: (RouteState) -> HTML = { linkState in
                        return link(url: currentUrl(result: result, state: linkState, backUrl: backUrl)) { linkState.showFilter.rawValue.capitalized }.class(state.showFilter == linkState.showFilter ? "button-selected" : "button")
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
                    
                    mState = state
                    if result.testsFailed.count > 0 {
                        mState.showFailureMessage.toggle()
                        blocks.append("&nbsp;&nbsp;&nbsp;&nbsp;")
                        blocks.append(link(url: currentUrl(result: result, state: mState, backUrl: backUrl)) { "Show failures" }.class(state.showFailureMessage ? "button-selected" : "button"))
                    }

                    if result.codeCoverageSplittedHtmlBaseUrl != nil {
                        blocks.append("&nbsp;&nbsp;&nbsp;&nbsp;")
                        blocks.append(link(url: "coverage?id=\(result.identifier)&back_url=\(currentUrl(result: result, state: state, backUrl: backUrl).hexadecimalRepresentation)") { "Coverage" }.class("button"))
                    }

                    return HTMLBuilder.buildBlocks(blocks)
                }
            }.class("row light-bordered-container indent2")
        }
    }
    
    private func resultsTableHTML(result: ResultBundle, state: RouteState, backUrl: String) -> HTML {
        let tests: [ResultBundle.Test]
        switch state.showFilter {
        case .failed:
            tests = result.testsFailedExcludingRetries()
        case .passed:
            tests = result.testsPassed
        case .retried:
            tests = result.testsFailedRetring
        default:
            tests = result.tests
        }
            
        let groupNames = Set(tests.map({ $0.groupName })).sorted()
        
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
                let tests = tests.filter { $0.groupName == group }.sorted(by: { "\($0.name)-\($0.startDate.timeIntervalSince1970)" < "\($1.name)-\($1.startDate.timeIntervalSince1970)" })
                let testsCount = tests.count
                let testsFailedCount = tests.filter({ $0.status == .failure }).count
                let testsPassedCount = testsCount - testsFailedCount
                
                let testPassedString = testsPassedCount > 0 ? "\(testsPassedCount) passed (\(testsPassedCount.percentageString(total: testsCount, decimalDigits: 1)))" : ""
                let testFailedString = testsFailedCount > 0 ? "\(testsFailedCount) failed (\(testsFailedCount.percentageString(total: testsCount, decimalDigits: 1)))" : ""
                
                let testDuration = hoursMinutesSeconds(in: tests.reduce(0, { $0 + $1.duration }))
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
                        return tableRow {
                            tableData {
                                link(url: resultDetailUrlString(result: result, test: test, state: state, backUrl: backUrl)) {
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
                                link(url: resultDetailUrlString(result: result, test: test, state: state, backUrl: backUrl)) {
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
    
    private func currentUrl(result: ResultBundle, state: RouteState, backUrl: String) -> String {
        "\(self.path)?id=\(result.identifier)\(state)&back_url=\(backUrl.hexadecimalRepresentation)"
    }
    
    private func resultDetailUrlString(result: ResultBundle, test: ResultBundle.Test, state: RouteState, backUrl: String) -> String {
        "/html/test?id=\(test.summaryIdentifier!)&back_url=\(currentUrl(result: result, state: state, backUrl: backUrl).hexadecimalRepresentation)"
    }
}

private extension ResultBundle {
    func testsFailedExcludingRetries() -> [ResultBundle.Test] {
        return testsFailed.filter { test in testsUniquelyFailed.contains(where: { test.matches($0) }) }
    }
}

private extension ResultRouteHTML {
    struct RouteState: Codable, CustomStringConvertible {
        static let key = "state"
        
        enum ShowFilter: String, Codable { case all, passed, failed, retried }
        
        var showFilter: ShowFilter
        var showFailureMessage: Bool
        
        init(queryItems: [URLQueryItem]?) {
            self.init(hexadecimalRepresentation: queryItems?.first(where: { $0.name == Self.key})?.value)
        }

        init(hexadecimalRepresentation: String?) {
            if let hexadecimalRepresentation = hexadecimalRepresentation,
               let data = Data(hexadecimalRepresentation: hexadecimalRepresentation),
               let state = try? JSONDecoder().decode(RouteState.self, from: data) {
                showFilter = state.showFilter
                showFailureMessage = state.showFailureMessage
            } else {
                showFilter = .all
                showFailureMessage = false
            }
        }
        
        var description: String {
            guard let data = try? JSONEncoder().encode(self),
                  let hexRepresentation = data.hexadecimalRepresentation else {
                return ""
            }
                        
            return "&\(Self.key)=" + hexRepresentation
        }
    }
}
