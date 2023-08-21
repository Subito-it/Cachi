import CachiKit
import Foundation
import HTTPKit
import os
import Vaux

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

        let activitySummary = State.shared.testActionSummary(test: test)

        let actions = activitySummary?.activitySummaries ?? []
        var rowsData: [TableRowModel]
        var failureSummaries = activitySummary?.failureSummaries ?? []
        if let firstTimestamp = actions.first(where: { $0.start != nil })?.start?.timeIntervalSince1970 {
            rowsData = TableRowModel.makeModels(from: actions, currentTimestamp: firstTimestamp, failureSummaries: &failureSummaries, userInfo: resultBundle.userInfo)
            for failureSummary in failureSummaries {
                rowsData += TableRowModel.makeFailureModel(failureSummary, currentTimestamp: firstTimestamp, userInfo: resultBundle.userInfo, indentation: 0)
            }
        } else {
            rowsData = []
            
            let firstTimestamp = (failureSummaries.first?.timestamp ?? Date()).timeIntervalSince1970
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
                tableHeadData { "Screenshot" }.alignment(.center).scope(.column).class("row dark-bordered-container")
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
                                        } else if rowData.isScreenshot {
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
                            } else if rowData.isKeyScreenshot || rowData.isScreenshot {
                                if rowData.isKeyScreenshot {
                                    rowClasses.append("screenshot-key")
                                }

                                return row
                                    .class(rowClasses.joined(separator: " "))
                                    .attr("onmouseenter", #"onMouseEnter(this, '\#(result.identifier)', '\#(testSummaryIdentifier)', '\#(rowData.attachmentIdentifier)', '\#(rowData.attachmentContentType)', '\#(rowData.attachmentContentType)')"#)
                                    .attr("onclick", #"onMouseEnter(this, '\#(result.identifier)', '\#(testSummaryIdentifier)', '\#(rowData.attachmentIdentifier)', '\#(rowData.attachmentContentType)')"#)
                            } else {
                                return row
                                    .class(rowClasses.joined(separator: " "))
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

    private func currentUrl(test: ResultBundle.Test, source: String?, backUrl: String) -> String {
        var url = "\(path)?id=\(test.summaryIdentifier!)&back_url=\(backUrl.hexadecimalRepresentation)"
        if let source {
            url += "&source=\(source)"
        }
        return url
    }
}

// MARK: - RowData

private struct TableRowModel {
    let indentation: Int
    let title: String
    let attachmentImage: (url: String, width: Int)?
    let attachmentIdentifier: String
    let attachmentContentType: String
    let hasChildren: Bool
    let isError: Bool
    let isKeyScreenshot: Bool
    let isScreenshot: Bool

    var isExternalLink: Bool { attachmentContentType == "text/html" }

    static func makeModels(from actionSummaries: [ActionTestActivitySummary], currentTimestamp: Double, failureSummaries: inout [ActionTestFailureSummary], userInfo: ResultBundle.UserInfo?, indentation: Int = 1, lastScreenshotIdentifier: String = "", lastScreenshotContentType: String = "") -> [TableRowModel] {
        var data = [TableRowModel]()

        for summary in actionSummaries {
            guard var title = summary.title else {
                continue
            }

            var subRowData = [TableRowModel]()
            for attachment in summary.attachments {
                let attachmentIdentifier = attachment.payloadRef?.id ?? ""
                let attachmentMetadata = attachmentMetadata(from: attachment)

                let isScreenshot = attachment.name == "kXCTAttachmentLegacyScreenImageData"
                subRowData += [TableRowModel(indentation: indentation + 1, title: attachmentMetadata.title, attachmentImage: attachmentMetadata.image, attachmentIdentifier: attachmentIdentifier, attachmentContentType: attachmentMetadata.contentType, hasChildren: false, isError: false, isKeyScreenshot: isScreenshot, isScreenshot: isScreenshot)]
            }

            let lastScreenshotRow = (data + subRowData).reversed().first(where: { $0.isKeyScreenshot })
            let screenshotIdentifier = lastScreenshotRow?.attachmentIdentifier ?? lastScreenshotIdentifier
            let screenshotContentType = lastScreenshotRow?.attachmentContentType ?? lastScreenshotContentType

            let isError = summary.activityType == "com.apple.dt.xctest.activity-type.testAssertionFailure"

            let actionTimestamp = summary.start?.timeIntervalSince1970 ?? currentTimestamp
            subRowData += makeModels(from: summary.subactivities, currentTimestamp: currentTimestamp, failureSummaries: &failureSummaries, userInfo: userInfo, indentation: indentation + 1, lastScreenshotIdentifier: screenshotIdentifier, lastScreenshotContentType: screenshotContentType)

            title += currentTimestamp - actionTimestamp == 0 ? " (Start)" : " (\(String(format: "%.2f", actionTimestamp - currentTimestamp))s)"

            data += [TableRowModel(indentation: indentation, title: title, attachmentImage: nil, attachmentIdentifier: screenshotIdentifier, attachmentContentType: screenshotContentType, hasChildren: subRowData.count > 0, isError: isError, isKeyScreenshot: false, isScreenshot: screenshotIdentifier.count > 0)] + subRowData

            if !summary.failureSummaryIDs.isEmpty {
                for failureSummaryID in summary.failureSummaryIDs {
                    guard let failureIndex = failureSummaries.firstIndex(where: { $0.uuid == failureSummaryID }) else {
                        continue
                    }

                    data += makeFailureModel(failureSummaries[failureIndex], currentTimestamp: currentTimestamp, userInfo: userInfo, indentation: indentation)
                    failureSummaries.remove(at: failureIndex)
                }
            }
        }

        return data
    }

    static func makeFailureModel(_ failure: ActionTestFailureSummary, currentTimestamp: Double, userInfo: ResultBundle.UserInfo?, indentation: Int) -> [TableRowModel] {
        var data = [TableRowModel]()
        
        data.append(TableRowModel(indentation: indentation, title: failure.message ?? "Failure", attachmentImage: nil, attachmentIdentifier: "", attachmentContentType: "", attachmentFilename: "", hasChildren: !failure.attachments.isEmpty, isError: true, isKeyScreenshot: false, isScreenshot: false))
        if var fileName = failure.fileName, let lineNumber = failure.lineNumber {
            fileName = fileName.replacingOccurrences(of: userInfo?.sourceBasePath ?? "", with: "")
            var attachment: (url: String, width: Int)?
            if let githubBaseUrl = userInfo?.githubBaseUrl, let commitHash = userInfo?.commitHash {
                attachment = (url: "\(githubBaseUrl)/blob/\(commitHash)/\(fileName)#L\(lineNumber)", width: 15)
            }
            data.append(TableRowModel(indentation: indentation + 1, title: "\(fileName):\(lineNumber)", attachmentImage: attachment, attachmentIdentifier: "", attachmentContentType: "text/html", attachmentFilename: "", hasChildren: false, isError: false, isKeyScreenshot: false, isScreenshot: false))
        }

        for attachment in failure.attachments {
            let attachmentIdentifier = attachment.payloadRef?.id ?? ""
            let attachmentMetadata = attachmentMetadata(from: attachment)
            
            let isScreenshot = attachment.name == "kXCTAttachmentLegacyScreenImageData"
            
            data.append(TableRowModel(indentation: indentation + 1, title: attachmentMetadata.title, attachmentImage: attachmentMetadata.image, attachmentIdentifier: attachmentIdentifier, attachmentContentType: attachmentMetadata.contentType, attachmentFilename: attachment.filename ?? "", hasChildren: false, isError: false, isKeyScreenshot: isScreenshot, isScreenshot: isScreenshot))
        }

        return data
    }

    private static func attachmentMetadata(from attachment: ActionTestAttachment) -> (title: String, contentType: String, image: (url: String, width: Int)) {
        switch attachment.uniformTypeIdentifier {
        case "public.plain-text", "public.utf8-plain-text":
            return ("User plain text data",
                    "text/plain",
                    ("/image?imageAttachment", 14))
        case "public.jpeg":
            return (attachment.name == "kXCTAttachmentLegacyScreenImageData" ? "Automatic Screenshot" : "User image attachment",
                    "image/jpeg",
                    ("/image?imageView", 18))
        case "public.png":
            return (attachment.name == "kXCTAttachmentLegacyScreenImageData" ? "Automatic Screenshot" : "User image attachment",
                    "image/png",
                    ("/image?imageView", 18))
        case "com.apple.dt.xctest.element-snapshot":
            // This is an unsupported key archived snapshot of the entire view hierarchy of the app
            return ("", "", ("", 0))
        case "public.data":
            return ("Other text data",
                    "text/plain",
                    ("/image?imageAttachment", 14))
        default:
            assertionFailure("Unhandled attachment uniformTypeIdentifier: \(attachment.uniformTypeIdentifier)")
        }

        return ("", "", ("", 0))
    }
}
