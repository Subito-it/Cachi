import CachiKit
import Foundation
import os
import Vapor
import Vaux

struct TestStatRouteHTML: Routable {
    static let path = "/html/teststats"

    let method = HTTPMethod.GET
    let description: String = "Test execution statistics (pass identifier)"

    private let baseUrl: URL
    private let depth: Int

    init(baseUrl: URL, depth: Int) {
        self.baseUrl = baseUrl
        self.depth = depth
    }

    func respond(to req: Request) throws -> Response {
        os_log("HTML test stat request received", log: .default, type: .info)

        guard let components = req.urlComponents(),
              let queryItems = components.queryItems,
              let testSummaryIdentifier = queryItems.first(where: { $0.name == "id" })?.value
        else {
            return Response(status: .notFound, body: Response.Body(stringLiteral: "Not found..."))
        }

        let benchId = benchmarkStart()
        defer { os_log("Test with summaryIdentifier '%@' fetched in %fms", log: .default, type: .info, testSummaryIdentifier, benchmarkStop(benchId)) }

        let resultBundles = State.shared.resultBundles

        guard let resultBundle = resultBundles.first(where: { $0.tests.contains(where: { $0.summaryIdentifier == testSummaryIdentifier }) }),
              let test = resultBundle.tests.first(where: { $0.summaryIdentifier == testSummaryIdentifier })
        else {
            return Response(status: .notFound, body: Response.Body(stringLiteral: "Not found..."))
        }

        var matchingResults = [(resultBundle: ResultBundle, tests: [ResultBundle.Test])]()
        for resultBundle in resultBundles {
            if matchingResults.count > 50 { break }

            let tests = resultBundle.tests.filter { $0.targetIdentifier == test.targetIdentifier }
            if tests.count > 0 {
                matchingResults.append((resultBundle: resultBundle, tests: tests))
            }
        }

        guard matchingResults.count > 0 else {
            return Response(status: .notFound, body: Response.Body(stringLiteral: "Something went really wrong..."))
        }

        matchingResults = matchingResults.sorted(by: { $0.resultBundle.testStartDate > $1.resultBundle.testStartDate })

        let allTests = matchingResults.map(\.tests).flatMap { $0 }
        let allTestsAverageDuration = allTests.reduce(0) { $0 + $1.duration } / Double(max(1, allTests.count))

        let successfulTests = allTests.filter { $0.status == .success }
        let successfulTestsAverageDuration = successfulTests.reduce(0) { $0 + $1.duration } / Double(max(1, successfulTests.count))
        let failedTests = allTests.filter { $0.status == .failure }
        let failedTestsAverageDuration = failedTests.reduce(0) { $0 + $1.duration } / Double(max(1, failedTests.count))

        let successRatio = 100 * Double(successfulTests.count) / Double(matchingResults.count)
        let testDetail = "Success ratio \(String(format: "%.1f", successRatio))% (\(successfulTests.count) passed, \(failedTests.count) failed)"

        let source = queryItems.first(where: { $0.name == "source" })?.value

        let backUrl = queryItems.backUrl

        let document = html {
            head {
                title("Cachi - Test stats")
                meta().attr("charset", "utf-8")
                linkStylesheet(url: "/css?main")
            }
            body {
                div {
                    div { floatingHeaderHTML(test: test, testDetail: testDetail, source: source, backUrl: backUrl) }.class("sticky-top").id("top-bar")
                    div { resultsTableHTML(results: matchingResults, source: source, backUrl: backUrl) }

                    div { "&nbsp;" }
                    div { "Average execution" }.class("header indent2")
                    if successfulTests.count > 0 {
                        div {
                            image(url: ImageRoute.passedTestImageUrl())
                                .attr("title", "Passed tests average")
                                .iconStyleAttributes(width: 14)
                                .class("icon")

                            hoursMinutesSeconds(in: successfulTestsAverageDuration)
                        }.class("row indent3")
                    }
                    if failedTests.count > 0 {
                        div {
                            image(url: ImageRoute.failedTestImageUrl())
                                .attr("title", "Failed tests average")
                                .iconStyleAttributes(width: 14)
                                .class("icon")

                            hoursMinutesSeconds(in: failedTestsAverageDuration)
                        }.class("row indent3")
                    }
                    if successfulTests.count > 0, failedTests.count > 0 {
                        div {
                            image(url: ImageRoute.grayTestImageUrl())
                                .attr("title", "All tests average")
                                .iconStyleAttributes(width: 14)
                                .class("icon")

                            hoursMinutesSeconds(in: allTestsAverageDuration)
                        }.class("row indent3")
                    }
                }.class("main-container background")
            }
        }

        return document.httpResponse()
    }

    static func urlString(testSummaryIdentifier: String?, source: String?, backUrl: String) -> String {
        var components = URLComponents(string: path)!
        components.queryItems = [
            .init(name: "id", value: testSummaryIdentifier),
            .init(name: "source", value: source),
            .init(name: "back_url", value: backUrl.hexadecimalRepresentation)
        ]

        components.queryItems = components.queryItems?.filter { !($0.value?.isEmpty ?? true) }

        return components.url!.absoluteString
    }

    private func floatingHeaderHTML(test: ResultBundle.Test, testDetail: String, source _: String?, backUrl: String) -> HTML {
        let testTitle = test.name
        let testSubtitle = test.groupName

        let testDevice = "\(test.deviceModel) (\(test.deviceOs))"

        return div {
            div {
                div {
                    link(url: backUrl) {
                        image(url: ImageRoute.arrowLeftImageUrl())
                            .iconStyleAttributes(width: 8)
                            .class("icon color-svg-text")
                    }
                    testTitle
                }.class("header")
                div { testSubtitle }.class("color-subtext subheader")
                div { testDetail }.class("color-subtext indent1").floatRight()
                div { testDevice }.class("color-subtext subheader")
            }.class("row light-bordered-container indent1")
        }
    }

    private func resultsTableHTML(results: [(resultBundle: ResultBundle, tests: [ResultBundle.Test])], source: String?, backUrl: String) -> HTML {
        let allTests = results.flatMap(\.tests)
        let testFailureMessages = allTests.failureMessages()

        return table {
            columnGroup(styles: [TableColumnStyle(span: 1, styles: [StyleAttribute(key: "wrap-word", value: "break-word")]),
                                 TableColumnStyle(span: 1, styles: [StyleAttribute(key: "width", value: "100px")])])

            tableRow {
                tableHeadData { "Test" }.alignment(.left).scope(.column).class("row dark-bordered-container indent1")
                tableHeadData { "Duration" }.alignment(.left).scope(.column).class("row dark-bordered-container")
            }.id("table-header")

            forEach(results) { matching in
                forEach(matching.tests) { test in
                    HTMLBuilder.buildBlock(
                        tableRow {
                            tableData {
                                link(url: TestRouteHTML.urlString(testSummaryIdentifier: test.summaryIdentifier, source: source, backUrl: backUrl)) {
                                    div {
                                        image(url: matching.resultBundle.htmlStatusImageUrl(for: test))
                                            .attr("title", matching.resultBundle.htmlStatusTitle(for: test))
                                            .iconStyleAttributes(width: 14)
                                            .class("icon")
                                        matching.resultBundle.htmlTitle()
                                    }.class("row indent2 background")
                                }

                                if test.status == .failure {
                                    if let failureMessage = testFailureMessages[test.identifier] {
                                        div { failureMessage }.class("row indent3 background color-error")
                                    } else if test.status == .failure {
                                        div { "No failure message found" }.class("row indent3 background color-error")
                                    }
                                }
                            }.class("row indent1")
                            tableData {
                                div { hoursMinutesSeconds(in: test.duration) }
                            }.alignment(.left).class("row indent1")
                        }.class("light-bordered-container")
                    )
                }
            }
        }.style([StyleAttribute(key: "table-layout", value: "fixed")])
    }
}
