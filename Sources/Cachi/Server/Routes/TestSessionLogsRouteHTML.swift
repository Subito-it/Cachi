import Foundation
import HTTPKit
import os
import Vaux
import CachiKit

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

struct TestSessionLogsRouteHTML: Routable {
    let path: String = "/html/session_logs"
    let description: String = "Test session logs in html (pass identifier)"
        
    func respond(to req: HTTPRequest, with promise: EventLoopPromise<HTTPResponse>) {
        os_log("HTML test stats request received", log: .default, type: .info)
        
        guard let components = URLComponents(url: req.url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems,
              let testSummaryIdentifier = queryItems.first(where: { $0.name == "id" })?.value,
              let sessionType = queryItems.first(where: { $0.name == "type" })?.value,
              let backShowFilter = queryItems.first(where: { $0.name == "show" }) else {
            let res = HTTPResponse(status: .notFound, body: HTTPBody(staticString: "Not found..."))
            return promise.succeed(res)
        }
                
        let benchId = benchmarkStart()
        defer { os_log("Test session logs with summaryIdentifier '%@' fetched in %fms", log: .default, type: .info, testSummaryIdentifier, benchmarkStop(benchId)) }
              
        let resultBundles = State.shared.resultBundles
        
        guard let resultBundle = resultBundles.first(where: { $0.tests.contains(where: { $0.summaryIdentifier == testSummaryIdentifier })}),
              let test = resultBundle.tests.first(where: { $0.summaryIdentifier == testSummaryIdentifier }) else {
            let res = HTTPResponse(status: .notFound, body: HTTPBody(staticString: "Not found..."))
            return promise.succeed(res)
        }
        
        guard let diagnosticsIdentifier = test.diagnosticsIdentifier,
              let sessionLogs = State.shared.testSessionLogs(diagnosticsIdentifier: diagnosticsIdentifier) else {
            let res = HTTPResponse(status: .notFound, body: HTTPBody(staticString: "Not diagnistics found..."))
            return promise.succeed(res)
        }
                        
        let document = html {
            head {
                title("Cachi - Test result")
                meta().attr("charset", "utf-8")
                linkStylesheet(url: "/css?main")
                script(filepath: Filepath(name: "/script?screenshot", path: ""))
            }
            body {
                div {
                    div { floatingHeaderHTML(result: resultBundle, test: test, backShowFilter: backShowFilter) }
                    switch sessionType {
                    case "stdouts":
                        div { standardOutputsLogsTableHTML(sessionLogs: sessionLogs) }
                    case "session":
                        div { sessionLogsTableHTML(sessionLogs: sessionLogs) }
                    default:
                        div { }
                    }
                }.class("main-container")
            }
        }
        
        return promise.succeed(document.httpResponse())
    }
    
    private func floatingHeaderHTML(result: ResultBundle, test: ResultBundle.Test, backShowFilter: URLQueryItem) -> HTML {
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
        
        var backParameters = ""
        if let value = backShowFilter.value {
            backParameters = "&\(backShowFilter.name)=\(value)"
        }
        
        return div {
            div {
                div {
                    link(url: "/html/test?id=\(test.summaryIdentifier ?? "")\(backParameters)") {
                        image(url: "/image?imageArrorLeft")
                            .iconStyleAttributes(width: 8)
                            .class("icon color-svg-text")
                    }
                    image(url: result.htmlStatusImageUrl(for: test))
                        .attr("title", result.htmlStatusTitle(for: test))
                        .iconStyleAttributes(width: 14)
                        .class("icon")
                    testTitle
                }.class("header")
                div { testSubtitle }.class("color-subtext indent1")
                div { testDetail }.class("color-subtext indent1").floatRight()
                div { testDevice }.class("color-subtext indent1")
            }.class("row light-bordered-container indent1")
        }
    }
    
    private func standardOutputsLogsTableHTML(sessionLogs: ResultBundle.Test.SessionLogs) -> HTML {
        let runnerLogs = sessionLogs.runerAppStandardOutput ?? "No data"
        let appLogs = sessionLogs.appStandardOutput ?? "No data"

        return table {
            tableHeadData { "Runner App" }.alignment(.left).scope(.column).class("row dark-bordered-container indent1")
            tableHeadData { "App" }.alignment(.left).scope(.column).class("row dark-bordered-container")

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
