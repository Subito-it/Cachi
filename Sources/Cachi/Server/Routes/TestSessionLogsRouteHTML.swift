import CachiKit
import Foundation
import os
import Vapor
import Vaux

struct TestSessionLogsRouteHTML: Routable {
    let method = HTTPMethod.GET
    let path: String = "/html/session_logs"
    let description: String = "Test session logs in html (pass identifier)"

    func respond(to req: Request) throws -> Response {
        os_log("HTML test stats request received", log: .default, type: .info)

        guard let components = req.urlComponents(),
              let queryItems = components.queryItems,
              let testSummaryIdentifier = queryItems.first(where: { $0.name == "id" })?.value,
              let sessionType = queryItems.first(where: { $0.name == "type" })?.value
        else {
            return Response(status: .notFound, body: Response.Body(stringLiteral: "Not found..."))
        }

        let benchId = benchmarkStart()
        defer { os_log("Test session logs with summaryIdentifier '%@' fetched in %fms", log: .default, type: .info, testSummaryIdentifier, benchmarkStop(benchId)) }

        let resultBundles = State.shared.resultBundles

        guard let resultBundle = resultBundles.first(where: { $0.tests.contains(where: { $0.summaryIdentifier == testSummaryIdentifier }) }),
              let test = resultBundle.tests.first(where: { $0.summaryIdentifier == testSummaryIdentifier })
        else {
            return Response(status: .notFound, body: Response.Body(stringLiteral: "Not found..."))
        }

        guard let diagnosticsIdentifier = test.diagnosticsIdentifier,
              let sessionLogs = State.shared.testSessionLogs(diagnosticsIdentifier: diagnosticsIdentifier)
        else {
            return Response(status: .notFound, body: Response.Body(stringLiteral: "Not diagnistics found..."))
        }

        let backUrl = queryItems.backUrl

        let document = html {
            head {
                title("Cachi - Test result")
                meta().attr("charset", "utf-8")
                linkStylesheet(url: "/css?main")
                script(filepath: Filepath(name: "/script?type=screenshot", path: ""))
            }
            body {
                div {
                    div { floatingHeaderHTML(result: resultBundle, test: test, backUrl: backUrl) }.class("sticky-top").id("top-bar")
                    switch sessionType {
                    case "stdouts":
                        div { standardOutputsLogsTableHTML(sessionLogs: sessionLogs) }
                    case "session":
                        div { sessionLogsTableHTML(sessionLogs: sessionLogs) }
                    default:
                        div {}
                    }
                }.class("main-container background")
            }
        }

        return document.httpResponse()
    }

    private func floatingHeaderHTML(result _: ResultBundle, test: ResultBundle.Test, backUrl: String) -> HTML {
        let testTitle = test.name
        let testSubtitle = test.groupName

        let testDuration = hoursMinutesSeconds(in: test.duration)
        let testDetail: String
        switch test.status {
        case .success:
            testDetail = "Passed in \(testDuration)"
        case .failure:
            testDetail = "Failed in \(testDuration)"
        }

        let testDevice = "\(test.deviceModel) (\(test.deviceOs))"

        return div {
            div {
                div {
                    link(url: backUrl) {
                        image(url: "/image?imageArrowLeft")
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

    private func standardOutputsLogsTableHTML(sessionLogs: ResultBundle.Test.SessionLogs) -> HTML {
        let runnerLogs = sessionLogs.runerAppStandardOutput ?? "No data"
        let appLogs = sessionLogs.appStandardOutput ?? "No data"

        return table {
            tableRow {
                tableHeadData { "Runner App" }.alignment(.left).scope(.column).class("row dark-bordered-container indent1")
                tableHeadData { "App" }.alignment(.left).scope(.column).class("row dark-bordered-container")
            }.id("table-header")

            tableRow {
                tableData {
                    RawHTML(rawContent: runnerLogs)
                }.class("indent2 log col50")
                tableData {
                    RawHTML(rawContent: appLogs)
                }.class("indent1 log-log col50")
            }
        }
    }

    private func sessionLogsTableHTML(sessionLogs: ResultBundle.Test.SessionLogs) -> HTML {
        let sessionLogs = sessionLogs.sessionLogs ?? "No data"

        return table {
            tableHeadData { "Session Log" }.alignment(.left).scope(.column).class("row dark-bordered-container indent1")

            tableRow {
                tableData {
                    RawHTML(rawContent: sessionLogs)
                }.class("indent2 log")
            }
        }
    }
}

private struct RowData {
    let indentation: Int
    let title: String
    let attachmentImage: (url: String, width: Int)?
    let attachmentIdentifier: String
    let attachmentContentType: String
    let hasChildren: Bool
    let isError: Bool
    let isKeyScreenshot: Bool
    let isScreenshot: Bool
}
