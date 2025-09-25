import CachiKit
import Foundation
import os
import Vapor
import Vaux

struct TestRouteHTML: Routable {
    static let path: String = "/html/test"

    let method = HTTPMethod.GET
    let description: String = "Test details in html (pass identifier)"

    private let attachmentViewers: [String: AttachmentViewerConfiguration]

    init(attachmentViewers: [String: AttachmentViewerConfiguration] = [:]) {
        self.attachmentViewers = attachmentViewers
    }

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

        var rowsData = [TableRowModel]()
        let actions = activitySummary?.activitySummaries ?? []
        let failureSummaries = activitySummary?.failureSummaries ?? []

        if let initialTimestamp = (actions.compactMap(\.start).first ?? failureSummaries.compactMap(\.timestamp).first)?.timeIntervalSince1970 {
            rowsData = TableRowModel.makeModels(from: actions, initialTimestamp: initialTimestamp, failureSummaries: failureSummaries, userInfo: resultBundle.userInfo)

            let processedUUIDs = rowsData.map(\.uuid)
            for failureSummary in failureSummaries.filter({ !processedUUIDs.contains($0.uuid) }) {
                rowsData += TableRowModel.makeFailureModel(failureSummary, initialTimestamp: initialTimestamp, userInfo: resultBundle.userInfo, indentation: 1)
            }
        }

        let source = queryItems.first(where: { $0.name == "source" })?.value
        let backUrl = queryItems.backUrl

        let document = html {
            head {
                title("Cachi - Test result")
                meta().attr("charset", "utf-8")
                linkStylesheet(url: "/css?main")
                script(filepath: Filepath(name: ScriptRoute.captureUrlString(), path: ""))
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

    private func floatingHeaderHTML(result: ResultBundle, test: ResultBundle.Test, source: String?, backUrl: String) -> HTML {
        let testTitle = test.name
        let testSubtitle = test.groupName

        let testDuration = hoursMinutesSeconds(in: test.duration)
        let testDetail = switch test.status {
        case .success:
            "Passed in \(testDuration)"
        case .failure:
            "Failed in \(testDuration)"
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
            div {
                div {
                    if let previousTest {
                        link(url: Self.urlString(testSummaryIdentifier: previousTest.summaryIdentifier, source: source, backUrl: backUrl)) { "←" }.class("button")
                    }
                    if let nextTest {
                        link(url: Self.urlString(testSummaryIdentifier: nextTest.summaryIdentifier, source: source, backUrl: backUrl)) { "→" }.class("button")
                    }
                }.floatRight()
                div {
                    if !fromTestStats {
                        link(url: TestStatRouteHTML.urlString(testSummaryIdentifier: test.summaryIdentifier, source: "test_route", backUrl: currentUrl(test: test, source: source, backUrl: backUrl))) { "Test stats" }.class("button")
                    }

                    let sessionBackUrl = currentUrl(test: test, source: source, backUrl: backUrl)
                    link(url: TestSessionLogsRouteHTML.stdoutUrlString(testSummaryIdentifier: test.summaryIdentifier, backUrl: sessionBackUrl)) { "Standard output" }.class("button")
                    link(url: TestSessionLogsRouteHTML.sessionUrlString(testSummaryIdentifier: test.summaryIdentifier, backUrl: sessionBackUrl)) { "Session logs" }.class("button")

                    link(url: XcResultDownloadRoute.urlString(testSummaryIdentifier: test.summaryIdentifier)) { "Download .xcresult" }.class("button").style([.init(key: "margin-left", value: "20px")])
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

            let testSummaryIdentifier = test.summaryIdentifier ?? ""
            let videoCapture = rowsData.first(where: { $0.attachment?.captureMedia != TableRowModel.Attachment.CaptureMedia.none && $0.attachment?.contentType == "video/mp4" })
            var lastCaptureMediaAttachment: TableRowModel.Attachment?

            tableRow {
                tableData {
                    table {
                        forEach(rowsData) { rowData in
                            var rowClasses = ["light-bordered-container", "indent1"]
                            let row = tableRow {
                                tableData {
                                    if let attachment = rowData.attachment {
                                        if attachment.isExternalLink {
                                            return link(url: attachment.url) {
                                                div { rowData.title }.class("color-subtext").inlineBlock()
                                                image(url: ImageRoute.linkImageUrl())
                                                    .iconStyleAttributes(width: attachment.width)
                                                    .class("icon color-svg-subtext")
                                            }
                                        } else if attachment.captureMedia.available {
                                            lastCaptureMediaAttachment = attachment

                                            if videoCapture == nil {
                                                return HTMLBuilder.buildBlock(
                                                    div { rowData.title }.class("capture color-subtext").attr("attachment_identifier", attachment.identifier).inlineBlock(),
                                                    image(url: attachment.url)
                                                        .iconStyleAttributes(width: attachment.width)
                                                        .class("icon color-svg-subtext")
                                                )
                                            } else {
                                                return link(url: VideoCaptureRoute.urlString(identifier: attachment.identifier, resultIdentifier: result.identifier, testSummaryIdentifier: testSummaryIdentifier, filename: attachment.filename, contentType: attachment.contentType)) {
                                                    div { rowData.title }.class("color-subtext").inlineBlock()
                                                    image(url: attachment.url)
                                                        .iconStyleAttributes(width: attachment.width)
                                                        .class("icon color-svg-subtext")
                                                }
                                            }
                                        } else {
                                            let destinationUrl = attachmentDestinationUrl(for: attachment,
                                                                                          resultIdentifier: result.identifier,
                                                                                          testSummaryIdentifier: testSummaryIdentifier)
                                            return link(url: destinationUrl) {
                                                div { rowData.title }.class("color-subtext").inlineBlock()
                                                image(url: attachment.url)
                                                    .iconStyleAttributes(width: attachment.width)
                                                    .class("icon color-svg-subtext")
                                            }
                                        }
                                    } else {
                                        return div {
                                            if rowData.hasChildren {
                                                image(url: ImageRoute.arrowDownImageUrl())
                                                    .iconStyleAttributes(width: 12)
                                                    .class("icon color-svg-subtext")
                                            }

                                            if rowData.title.contains("\n") {
                                                div { rowData.title }
                                                    .class(rowData.hasChildren ? "bold" : "")
                                                    .style([
                                                        StyleAttribute(key: "white-space", value: "pre-line"),
                                                        StyleAttribute(key: "margin-bottom", value: "15px")
                                                    ])
                                            } else {
                                                div { rowData.title }
                                                    .class(rowData.hasChildren ? "bold" : "")
                                                    .inlineBlock()
                                            }
                                        }
                                    }
                                }.class(rowData.isError ? "row background-error" : "row")
                                    .style([StyleAttribute(key: "padding-left", value: "\(20 * rowData.indentation)px")])
                            }
                            .attr("attachment_identifier", rowData.attachment?.identifier ?? "")

                            if videoCapture != nil {
                                return row
                                    .class(rowClasses.joined(separator: " "))
                                    .attr("onmouseenter", #"updateScreenCapturePosition(this, \#(rowData.timestamp))"#)
                                    .attr("onclick", #"updateScreenCapturePosition(this, \#(rowData.timestamp))"#)
                            } else if let attachment = rowData.attachment ?? lastCaptureMediaAttachment, attachment.captureMedia.available {
                                if attachment.captureMedia == .firstInGroup {
                                    rowClasses.append("capture-key")
                                }

                                return row
                                    .class(rowClasses.joined(separator: " "))
                                    .attr("onmouseenter", #"updateScreenCapture(this, '\#(result.identifier)', '\#(testSummaryIdentifier)', '\#(attachment.identifier)', '\#(attachment.contentType)')"#)
                                    .attr("onclick", #"updateScreenCapture(this, '\#(result.identifier)', '\#(testSummaryIdentifier)', '\#(attachment.identifier)', '\#(attachment.contentType)')"#)

                            } else if rowData.title.isEmpty {
                                return row
                                    .style([.init(key: "visibility", value: "collapse")])
                            } else {
                                return row
                                    .class(rowClasses.joined(separator: " "))
                            }
                        }
                    }
                }
                tableData {
                    if let testSummaryIdentifier = test.summaryIdentifier {
                        if let videoCaptureAttachment = videoCapture?.attachment {
                            video {
                                source(mediaURL: VideoCaptureRoute.urlString(identifier: videoCaptureAttachment.identifier, resultIdentifier: result.identifier, testSummaryIdentifier: testSummaryIdentifier, filename: videoCaptureAttachment.filename, contentType: videoCaptureAttachment.contentType))
                            }.id("screen-capture")
                        } else if let attachment = rowsData.compactMap(\.attachment).first(where: { $0.captureMedia.available }) {
                            div {
                                image(url: AttachmentRoute.urlString(identifier: attachment.identifier, resultIdentifier: result.identifier, testSummaryIdentifier: testSummaryIdentifier, filename: attachment.filename, contentType: attachment.contentType)).id("screen-capture")
                            }
                        } else {
                            image(url: ImageRoute.emptyImageUrl())
                        }
                    } else {
                        ""
                    }
                }.id("capture-column")
            }
        }
    }

    private func currentUrl(test: ResultBundle.Test, source: String?, backUrl: String) -> String {
        var components = URLComponents(string: Self.path)!
        components.queryItems = [
            .init(name: "id", value: test.summaryIdentifier),
            .init(name: "source", value: source),
            .init(name: "back_url", value: backUrl.hexadecimalRepresentation)
        ]

        components.queryItems = components.queryItems?.filter { !($0.value?.isEmpty ?? true) }

        return components.url!.absoluteString
    }

    private func attachmentDestinationUrl(for attachment: TableRowModel.Attachment,
                                          resultIdentifier: String,
                                          testSummaryIdentifier: String) -> String {
        guard !attachmentViewers.isEmpty,
              let filenameExtension = attachment.filename.split(separator: ".").last?.lowercased() else {
            return AttachmentRoute.urlString(identifier: attachment.identifier,
                                             resultIdentifier: resultIdentifier,
                                             testSummaryIdentifier: testSummaryIdentifier,
                                             filename: attachment.filename,
                                             contentType: attachment.contentType)
        }

        let normalizedExtension = String(filenameExtension)
        guard let viewer = attachmentViewers[normalizedExtension] else {
            return AttachmentRoute.urlString(identifier: attachment.identifier,
                                             resultIdentifier: resultIdentifier,
                                             testSummaryIdentifier: testSummaryIdentifier,
                                             filename: attachment.filename,
                                             contentType: attachment.contentType)
        }

        return AttachmentViewerRoute.urlString(viewerExtension: viewer.fileExtension,
                                               resultIdentifier: resultIdentifier,
                                               testSummaryIdentifier: testSummaryIdentifier,
                                               attachmentIdentifier: attachment.identifier,
                                               filename: attachment.filename,
                                               title: attachment.title,
                                               contentType: attachment.contentType)
    }
}
