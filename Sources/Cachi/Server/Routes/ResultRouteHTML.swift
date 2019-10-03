import Foundation
import HTTPKit
import os
import Vaux

private enum ShowFilter: String, CaseIterable {
    case all, passed, failed, retried
    
    func params() -> String {
        return "&show=\(self.rawValue)"
    }
}

struct ResultRouteHTML: Routable {    
    let path: String = "/html/result"
    let description: String = "Detail of result in html (pass identifier)"
        
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
              let res = HTTPResponse(status: .notFound, body: HTTPBody(staticString: "Not found..."))
            return promise.succeed(res)
        }
        
        let showFilter = ShowFilter(rawValue: queryItems.first(where: { $0.name == "show" })?.value ?? "") ?? .all
        
        let document = html {
            head {
                title("Cachi - Result \(result.identifier)")
                meta().attr("charset", "utf-8")
                linkStylesheet(url: "/css?main")
            }
            body {
                div {
                    div { floatingHeaderHTML(result: result, showFilter: showFilter) }
                    div { resultsTableHTML(result: result, showFilter: showFilter) }
                }.class("main-container")
            }
        }
        
        return promise.succeed(document.httpResponse())
    }
    
    private func floatingHeaderHTML(result: ResultBundle, showFilter: ShowFilter) -> HTML {
        let resultTitle = result.htmlTitle()
        let resultSubtitle = result.htmlSubtitle()
        let resultDate = DateFormatter.fullDateFormatter.string(from: result.date)
        
        let resultDevice = "\(result.tests.first!.deviceModel) (\(result.tests.first!.deviceOs))"
                
        return div {
            div {
                div {
                    link(url: "/html/results") {
                        image(url: "/image?imageArrorLeft")
                            .iconStyleAttributes(width: 8)
                            .class("icon color-svg-text")
                    }
                    resultTitle
                }.class("header")
                div { resultSubtitle }.class("color-subtext indent1")
                div { resultDate }.class("color-subtext indent1").floatRight()
                div { resultDevice }.class("color-subtext indent1")
            }.class("row light-bordered-container indent1")
            div {
                div {
                    switch showFilter {
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

                    blocks.append(link(url: "\(self.path)?id=\(result.identifier)\(ShowFilter.all.params())") { ShowFilter.all.rawValue.capitalized }.class(showFilter == ShowFilter.all ? "button-selected" : "button"))
                    if result.testsPassed.count > 0 {
                        blocks.append(link(url: "\(self.path)?id=\(result.identifier)\(ShowFilter.passed.params())") { ShowFilter.passed.rawValue.capitalized }.class(showFilter == ShowFilter.passed ? "button-selected" : "button"))
                    }
                    if result.testsUniquelyFailed.count > 0 {
                        blocks.append(link(url: "\(self.path)?id=\(result.identifier)\(ShowFilter.failed.params())") { ShowFilter.failed.rawValue.capitalized }.class(showFilter == ShowFilter.failed ? "button-selected" : "button"))
                    }
                    if result.testsRepeated.count > 0 {
                        blocks.append(link(url: "\(self.path)?id=\(result.identifier)\(ShowFilter.retried.params())") { ShowFilter.retried.rawValue.capitalized }.class(showFilter == ShowFilter.retried ? "button-selected" : "button"))
                    }

                    return HTMLBuilder.buildBlocks(blocks)
                }
            }.class("row light-bordered-container indent2")
        }
    }
    
    private func resultsTableHTML(result: ResultBundle, showFilter: ShowFilter) -> HTML {
        let tests: [ResultBundle.Test]
        switch showFilter {
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
                
        return table {
            tableHeadData { "Test" }.alignment(.left).scope(.column).class("row dark-bordered-container indent1")
            tableHeadData { "Duration" }.alignment(.center).scope(.column).class("row dark-bordered-container")
            tableHeadData { "&nbsp;" }.scope(.column).class("row dark-bordered-container")
            
            forEach(groupNames) { group in
                let tests = tests.filter { $0.groupName == group }.sorted(by: { $0.name < $1.name })
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
                                self.linkToResultDetail(test: test, showFilter: showFilter) {
                                    image(url: result.htmlStatusImageUrl(for: test))
                                        .attr("title", result.htmlStatusTitle(for: test))
                                        .iconStyleAttributes(width: 14)
                                        .class("icon")
                                    test.name
                                }.class(result.htmlTextColor(for: test))
                            }.class("row indent3")
                            tableData {
                                self.linkToResultDetail(test: test, showFilter: showFilter) {
                                    hoursMinutesSeconds(in: test.duration)
                                }.class("color-text")
                            }.alignment(.center).class("row indent3")
                            tableData { "&nbsp;" }
                        }.class("light-bordered-container")
                    }
                )
            }
        }
    }
    
    private func linkToResultDetail(test: ResultBundle.Test, showFilter: ShowFilter, @HTMLBuilder child: () -> HTML) -> HTML {
        return link(url: "/html/test?id=\(test.summaryIdentifier!)\(showFilter.params())") {
            child()
        }
    }
}

private extension ResultBundle {
    func testsFailedExcludingRetries() -> [ResultBundle.Test] {
        return testsFailed.filter { test in testsUniquelyFailed.contains(where: { test.matches($0) }) }
    }
}
