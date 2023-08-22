import CachiKit
import Foundation
import os
import Vapor
import Vaux

struct TestRouteHTML: Routable {
    let method = HTTPMethod.GET
    let path: String = "/html/test"
    let description: String = "Test details in html (pass identifier)"

    func respond(to req: Request) throws -> Response {
        os_log("HTML test stats request received", log: .default, type: .info)

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

        let activitySummary = State.shared.testActionSummary(test: test)

        let actions = activitySummary?.activitySummaries ?? []
        var rowsData = [TableRowModel]()
        var failureSummaries = activitySummary?.failureSummaries ?? []
        if let firstTimestamp = (actions.first(where: { $0.start != nil })?.start ?? failureSummaries.first(where: { $0.timestamp != nil })?.timestamp)?.timeIntervalSince1970 {
            rowsData = TableRowModel.makeModels(from: actions, currentTimestamp: firstTimestamp, failureSummaries: &failureSummaries, userInfo: resultBundle.userInfo)
            for failureSummary in failureSummaries {
                rowsData += TableRowModel.makeFailureModel(failureSummary, currentTimestamp: firstTimestamp, userInfo: resultBundle.userInfo, indentation: 0)
            }
        }

        let source = queryItems.first(where: { $0.name == "source" })?.value
        let backUrl = queryItems.backUrl

        let document = html {
            head {
                title("Cachi - Test result")
                meta().attr("charset", "utf-8")
                linkStylesheet(url: "/css?main")
                script(filepath: Filepath(name: "/script?type=capture", path: ""))
            }
            body {
                div {
                    div { floatingHeaderHTML(result: resultBundle, test: test, source: source, backUrl: backUrl) }.class("sticky-top").id("top-bar")
                    div { resultsTableHTML(result: resultBundle, test: test, rowsData: rowsData) }
                }.class("main-container background")
            }
        }

        return document.httpResponse()
    }

    private func floatingHeaderHTML(result: ResultBundle, test: ResultBundle.Test, source: String?, backUrl: String) -> HTML {
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

        var previousTest: ResultBundle.Test?
        var nextTest: ResultBundle.Test?

        if test.status == .failure {
            let sortedTests = result.testsFailed.sorted(by: { "\($0.groupName)-\($0.name)-\($0.testStartDate.timeIntervalSince1970)" < "\($1.groupName)-\($1.name)-\($1.testStartDate.timeIntervalSince1970)" })

            if let index = sortedTests.firstIndex(of: test) {
                if index > 0 {
                    previousTest = sortedTests[index - 1]
                }
                if index < sortedTests.count - 1 {
                    nextTest = sortedTests[index + 1]
                }
            }
        }

        let fromTestStats = source == "test_stats"

        let sourceParam = source == nil ? "" : "&source=\(source!)"

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
            div {
                div {
                    if let previousTest {
                        link(url: "/html/test?id=\(previousTest.summaryIdentifier ?? "")\(sourceParam)&type=stdouts&back_url=\(backUrl.hexadecimalRepresentation)") { "←" }.class("button")
                    }
                    if let nextTest {
                        link(url: "/html/test?id=\(nextTest.summaryIdentifier ?? "")\(sourceParam)&type=stdouts&back_url=\(backUrl.hexadecimalRepresentation)") { "→" }.class("button")
                    }
                }.floatRight()
                div {
                    if !fromTestStats {
                        link(url: "/html/teststats?id=\(test.summaryIdentifier ?? "")&source=test_route&back_url=\(currentUrl(test: test, source: source, backUrl: backUrl).hexadecimalRepresentation)") { "Test stats" }.class("button")
                    }
                    link(url: "/html/session_logs?id=\(test.summaryIdentifier ?? "")&type=stdouts&back_url=\(currentUrl(test: test, source: source, backUrl: backUrl).hexadecimalRepresentation)") { "Standard outputs" }.class("button")
                    link(url: "/html/session_logs?id=\(test.summaryIdentifier ?? "")&type=session&back_url=\(currentUrl(test: test, source: source, backUrl: backUrl).hexadecimalRepresentation)") { "Session logs" }.class("button")
                }
            }.class("row indent2 background")
        }
    }

    private func resultsTableHTML(result: ResultBundle, test: ResultBundle.Test, rowsData: [TableRowModel]) -> HTML {
        table {
            tableRow {
                tableHeadData { "Steps" }.alignment(.left).scope(.column).class("row dark-bordered-container indent1")
                tableHeadData { "&nbsp;" }.alignment(.center).scope(.column).class("row dark-bordered-container")
            }.id("table-header")

            tableRow {
                tableData {
                    table {
                        forEach(rowsData) { rowData in
                            var rowClasses = ["light-bordered-container", "indent1"]
                            let row = tableRow {
                                tableData {
                                    if let attachmentImage = rowData.attachmentImage {
                                        if rowData.isExternalLink {
                                            return link(url: attachmentImage.url) {
                                                div { rowData.title }.class("color-subtext").inlineBlock()
                                                image(url: "/image?imageLink")
                                                    .iconStyleAttributes(width: attachmentImage.width)
                                                    .class("icon color-svg-subtext")
                                            }
                                        } else if rowData.captureMedia.available, !rowData.isVideo {
                                            return HTMLBuilder.buildBlock(
                                                div { rowData.title }.class("capture color-subtext").attr("attachment_identifier", rowData.attachmentIdentifier).inlineBlock(),
                                                image(url: attachmentImage.url)
                                                    .iconStyleAttributes(width: attachmentImage.width)
                                                    .class("icon color-svg-subtext")
                                            )
                                        } else if rowData.captureMedia.available, rowData.isVideo {
                                            return link(url: "/video_capture?result_id=\(result.identifier)&id=\(rowData.attachmentIdentifier)&test_id=\(test.summaryIdentifier ?? "")&content_type=\(rowData.attachmentContentType)&filename=\(rowData.attachmentFilename)") {
                                                div { rowData.title }.class("color-subtext").inlineBlock()
                                                image(url: attachmentImage.url)
                                                    .iconStyleAttributes(width: attachmentImage.width)
                                                    .class("icon color-svg-subtext")
                                            }
                                        } else {
                                            return link(url: "/attachment?result_id=\(result.identifier)&id=\(rowData.attachmentIdentifier)&test_id=\(test.summaryIdentifier ?? "")&content_type=\(rowData.attachmentContentType)") {
                                                div { rowData.title }.class("color-subtext").inlineBlock()
                                                image(url: attachmentImage.url)
                                                    .iconStyleAttributes(width: attachmentImage.width)
                                                    .class("icon color-svg-subtext")
                                            }
                                        }
                                    } else {
                                        return div {
                                            if rowData.hasChildren {
                                                image(url: "/image?imageArrowDown")
                                                    .iconStyleAttributes(width: 12)
                                                    .class("icon color-svg-subtext")
                                            }

                                            div { rowData.title }.class(rowData.hasChildren ? "bold" : "").inlineBlock()
                                        }
                                    }
                                }.class(rowData.isError ? "row background-error" : "row")
                                    .style([StyleAttribute(key: "padding-left", value: "\(20 * rowData.indentation)px")])
                            }
                            .attr("attachment_identifier", rowData.attachmentIdentifier)

                            let testSummaryIdentifier = test.summaryIdentifier ?? ""

                            if rowData.title.isEmpty {
                                return row
                                    .style([.init(key: "visibility", value: "collapse")])
                            } else if rowData.captureMedia.available || rowData.isVideo { // When a video capture is available we want all rows to have set the timestamp position
                                if rowData.captureMedia == .firstInGroup {
                                    rowClasses.append("capture-key")
                                }

                                return row
                                    .class(rowClasses.joined(separator: " "))
                                    .attr("onmouseenter", #"onMouseEnter(this, '\#(result.identifier)', '\#(testSummaryIdentifier)', '\#(rowData.attachmentIdentifier)', '\#(rowData.attachmentContentType)', { position: \#(rowData.timestamp) })"#)
                                    .attr("onclick", #"onMouseEnter(this, '\#(result.identifier)', '\#(testSummaryIdentifier)', '\#(rowData.attachmentIdentifier)', '\#(rowData.attachmentContentType)', { position: \#(rowData.timestamp) })"#)
                            } else {
                                return row
                                    .class(rowClasses.joined(separator: " "))
                            }
                        }
                    }
                }
                tableData {
                    if let rowData = rowsData.first, let testSummaryIdentifier = test.summaryIdentifier {
                        if rowData.isVideo {
                            return
                                video {
                                    source(mediaURL: "\(AttachmentRoute().path)?result_id=\(result.identifier)&test_id=\(testSummaryIdentifier)&id=\(rowData.attachmentIdentifier)&content_type=\(rowData.attachmentContentType)")
                                }.id("screen-capture")
                        } else if rowData.captureMedia.available {
                            return
                                div {
                                    image(url: "\(AttachmentRoute().path)?result_id=\(result.identifier)&test_id=\(testSummaryIdentifier)&id=\(rowData.attachmentIdentifier)&content_type=\(rowData.attachmentContentType)").id("screen-capture")
                                }
                        } else {
                            return image(url: "\(ImageRoute().path)?imageEmpty")
                        }
                    } else {
                        return ""
                    }
                }.id("capture-column")
            }
        }
    }

    private func currentUrl(test: ResultBundle.Test, source: String?, backUrl: String) -> String {
        var url = "\(path)?id=\(test.summaryIdentifier!)&back_url=\(backUrl.hexadecimalRepresentation)"
        if let source {
            url += "&source=\(source)"
        }
        return url
    }
}
