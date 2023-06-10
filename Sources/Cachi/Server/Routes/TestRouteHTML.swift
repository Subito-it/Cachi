import CachiKit
import Foundation
import HTTPKit
import os
import Vaux

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

struct TestRouteHTML: Routable {
    let path: String = "/html/test"
    let description: String = "Test details in html (pass identifier)"

    func respond(to req: HTTPRequest, with promise: EventLoopPromise<HTTPResponse>) {
        os_log("HTML test stats request received", log: .default, type: .info)

        guard let components = URLComponents(url: req.url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems,
              let testSummaryIdentifier = queryItems.first(where: { $0.name == "id" })?.value
        else {
            let res = HTTPResponse(status: .notFound, body: HTTPBody(staticString: "Not found..."))
            return promise.succeed(res)
        }

        let benchId = benchmarkStart()
        defer { os_log("Test with summaryIdentifier '%@' fetched in %fms", log: .default, type: .info, testSummaryIdentifier, benchmarkStop(benchId)) }

        let resultBundles = State.shared.resultBundles

        guard let resultBundle = resultBundles.first(where: { $0.tests.contains(where: { $0.summaryIdentifier == testSummaryIdentifier }) }),
              let test = resultBundle.tests.first(where: { $0.summaryIdentifier == testSummaryIdentifier })
        else {
            let res = HTTPResponse(status: .notFound, body: HTTPBody(staticString: "Not found..."))
            return promise.succeed(res)
        }

        let actions = State.shared.testActionSummaries(summaryIdentifier: test.summaryIdentifier!) ?? []
        let rowsData: [RowData]
        if let firstTimestamp = actions.first(where: { $0.start != nil })?.start?.timeIntervalSince1970 {
            rowsData = self.rowsData(from: actions, currentTimestamp: firstTimestamp)
        } else {
            rowsData = []
        }

        let source = queryItems.first(where: { $0.name == "source" })?.value
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
                    div { floatingHeaderHTML(result: resultBundle, test: test, source: source, backUrl: backUrl) }.class("sticky-top").id("top-bar")
                    div { resultsTableHTML(result: resultBundle, test: test, rowsData: rowsData) }
                }.class("main-container background")
            }
        }

        return promise.succeed(document.httpResponse())
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
                        image(url: "/image?imageArrorLeft")
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

    private func resultsTableHTML(result: ResultBundle, test: ResultBundle.Test, rowsData: [RowData]) -> HTML {
        table {
            tableRow {
                tableHeadData { "Steps" }.alignment(.left).scope(.column).class("row dark-bordered-container indent1")
                tableHeadData { "Screenshot" }.alignment(.center).scope(.column).class("row dark-bordered-container")
            }.id("table-header")

            tableRow {
                tableData {
                    table {
                        forEach(rowsData) { rowData in
                            let row = tableRow {
                                tableData {
                                    if let attachmentImage = rowData.attachmentImage {
                                        if rowData.isScreenshot {
                                            return HTMLBuilder.buildBlock(
                                                div { rowData.title }.class("screenshot color-subtext").attr("attachment_identifier", rowData.attachmentIdentifier).inlineBlock(),
                                                image(url: attachmentImage.url)
                                                    .iconStyleAttributes(width: attachmentImage.width)
                                                    .class("icon color-svg-subtext")
                                            )
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
                                                image(url: "/image?imageArrorDown")
                                                    .iconStyleAttributes(width: 12)
                                                    .class("icon color-svg-subtext")
                                            }

                                            div { rowData.title }.class(rowData.hasChildren ? "bold" : "").inlineBlock()
                                        }.class(rowData.isError ? "color-error" : "")
                                    }
                                }.class("row")
                                    .style([StyleAttribute(key: "padding-left", value: "\(20 * rowData.indentation)px")])
                            }.class("light-bordered-container indent1")
                                .attr("attachment_identifier", rowData.attachmentIdentifier)

                            let testSummaryIdentifier = test.summaryIdentifier ?? ""

                            if rowData.isKeyScreenshot {
                                return row
                                    .class("screenshot-key")
                                    .attr("onmouseenter", #"onMouseEnter(this, '\#(result.identifier)', '\#(testSummaryIdentifier)', '\#(rowData.attachmentIdentifier)', '\#(rowData.attachmentContentType)', '\#(rowData.attachmentContentType)')"#)
                                    .attr("onclick", #"onMouseEnter(this, '\#(result.identifier)', '\#(testSummaryIdentifier)', '\#(rowData.attachmentIdentifier)', '\#(rowData.attachmentContentType)')"#)
                            } else if rowData.isScreenshot {
                                return row
                                    .attr("onmouseenter", #"onMouseEnter(this, '\#(result.identifier)', '\#(testSummaryIdentifier)', '\#(rowData.attachmentIdentifier)', '\#(rowData.attachmentContentType)', '\#(rowData.attachmentContentType)')"#)
                                    .attr("onclick", #"onMouseEnter(this, '\#(result.identifier)', '\#(testSummaryIdentifier)', '\#(rowData.attachmentIdentifier)', '\#(rowData.attachmentContentType)')"#)
                            } else {
                                return row
                            }
                        }
                    }
                }
                tableData {
                    if let rowData = rowsData.first, let testSummaryIdentifier = test.summaryIdentifier {
                        if rowData.isScreenshot {
                            return
                                div {
                                    image(url: "\(AttachmentRoute().path)?result_id=\(result.identifier)&test_id=\(testSummaryIdentifier)&id=\(rowData.attachmentIdentifier)&content_type=\(rowData.attachmentContentType)").id("screenshot-image")
                                }
                        } else {
                            return image(url: "\(ImageRoute().path)?imageEmpty")
                        }
                    } else {
                        return ""
                    }
                }.id("screenshot-column")
            }
        }
    }

    private func rowsData(from actionSummaries: [ActionTestActivitySummary], currentTimestamp: Double, indentation: Int = 1, lastScreenshotIdentifier: String = "", lastScreenshotContentType: String = "") -> [RowData] {
        var data = [RowData]()

        for summary in actionSummaries {
            guard var title = summary.title else {
                continue
            }

            var subRowData = [RowData]()
            for attachment in summary.attachments {
                let attachmentContentType: String
                let attachmentTitle: String
                let attachmentImage: (url: String, width: Int)
                let attachmentIdentifier = attachment.payloadRef?.id ?? ""

                switch attachment.uniformTypeIdentifier {
                case "public.plain-text", "public.utf8-plain-text":
                    attachmentContentType = "text/plain"
                    attachmentTitle = "User plain text data"
                    attachmentImage = ("/image?imageAttachment", 14)
                case "public.jpeg":
                    attachmentContentType = "image/jpeg"
                    attachmentTitle = attachment.name == "kXCTAttachmentLegacyScreenImageData" ? "Automatic Screenshot" : "User image attachment"
                    attachmentImage = ("/image?imageView", 18)
                case "public.png":
                    attachmentContentType = "image/png"
                    attachmentTitle = attachment.name == "kXCTAttachmentLegacyScreenImageData" ? "Automatic Screenshot" : "User image attachment"
                    attachmentImage = ("/image?imageView", 18)
                case "public.data":
                    attachmentContentType = "text/plain"
                    attachmentTitle = "Other text data"
                    attachmentImage = ("/image?imageAttachment", 14)
                default:
                    assertionFailure("Unhandled attachment uniformTypeIdentifier: \(attachment.uniformTypeIdentifier)")
                    continue
                }

                let isScreenshot = attachment.name == "kXCTAttachmentLegacyScreenImageData"
                subRowData += [RowData(indentation: indentation + 1, title: attachmentTitle, attachmentImage: attachmentImage, attachmentIdentifier: attachmentIdentifier, attachmentContentType: attachmentContentType, hasChildren: false, isError: false, isKeyScreenshot: isScreenshot, isScreenshot: isScreenshot)]
            }

            let lastScreenshotRow = (data + subRowData).reversed().first(where: { $0.isKeyScreenshot })
            let screenshotIdentifier = lastScreenshotRow?.attachmentIdentifier ?? lastScreenshotIdentifier
            let screenshotContentType = lastScreenshotRow?.attachmentContentType ?? lastScreenshotContentType

            let isError = summary.activityType == "com.apple.dt.xctest.activity-type.testAssertionFailure"

            let actionTimestamp = summary.start?.timeIntervalSince1970 ?? currentTimestamp
            subRowData += rowsData(from: summary.subactivities, currentTimestamp: currentTimestamp, indentation: indentation + 1, lastScreenshotIdentifier: screenshotIdentifier, lastScreenshotContentType: screenshotContentType)

            title += currentTimestamp - actionTimestamp == 0 ? " (Start)" : " (\(String(format: "%.2f", actionTimestamp - currentTimestamp))s)"

            data += [RowData(indentation: indentation, title: title, attachmentImage: nil, attachmentIdentifier: screenshotIdentifier, attachmentContentType: screenshotContentType, hasChildren: subRowData.count > 0, isError: isError, isKeyScreenshot: false, isScreenshot: screenshotIdentifier.count > 0)] + subRowData
        }

        return data
    }

    private func currentUrl(test: ResultBundle.Test, source: String?, backUrl: String) -> String {
        if let source {
            return "\(path)?id=\(test.summaryIdentifier!)&source=\(source)&back_url=\(backUrl.hexadecimalRepresentation)"
        } else {
            return "\(path)?id=\(test.summaryIdentifier!)&back_url=\(backUrl.hexadecimalRepresentation)"
        }
    }
}
