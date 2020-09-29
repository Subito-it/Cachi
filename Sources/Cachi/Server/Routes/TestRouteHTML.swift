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

struct TestRouteHTML: Routable {
    let path: String = "/html/test"
    let description: String = "Test details in html (pass identifier)"
        
    func respond(to req: HTTPRequest, with promise: EventLoopPromise<HTTPResponse>) {
        os_log("HTML test stats request received", log: .default, type: .info)
        
        guard let components = URLComponents(url: req.url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems,
              let testSummaryIdentifier = queryItems.first(where: { $0.name == "id" })?.value,
              let backShowFilter = queryItems.first(where: { $0.name == "show" }) else {
            let res = HTTPResponse(status: .notFound, body: HTTPBody(staticString: "Not found..."))
            return promise.succeed(res)
        }
                
        let benchId = benchmarkStart()
        defer { os_log("Test with summaryIdentifier '%@' fetched in %fms", log: .default, type: .info, testSummaryIdentifier, benchmarkStop(benchId)) }
              
        let resultBundles = State.shared.resultBundles
        
        guard let resultBundle = resultBundles.first(where: { $0.tests.contains(where: { $0.summaryIdentifier == testSummaryIdentifier })}),
            let test = resultBundle.tests.first(where: { $0.summaryIdentifier == testSummaryIdentifier }) else {
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
                    div { resultsTableHTML(result: resultBundle, rowsData: rowsData) }
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
                    link(url: "/html/result?id=\(result.identifier)\(backParameters)") {
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
    
    private func resultsTableHTML(result: ResultBundle, rowsData: [RowData]) -> HTML {
        return table {
            tableHeadData { "Steps" }.alignment(.left).scope(.column).class("row dark-bordered-container indent1")
            tableHeadData { "Screenshot" }.alignment(.center).scope(.column).class("row dark-bordered-container")

            tableRow {
                tableData {
                    return table {
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
                                            return link(url: "/attachment?result_id=\(result.identifier)&id=\(rowData.attachmentIdentifier)&content_type=\(rowData.attachmentContentType)") {
                                                div { rowData.title }.class("color-subtext").inlineBlock()
                                                image(url: attachmentImage.url)
                                                    .iconStyleAttributes(width: attachmentImage.width)
                                                    .class("icon color-svg-subtext")
                                            }
                                        }
                                    } else {
                                        return div { rowData.title }.class(rowData.isError ? "color-error" : "")
                                    }
                                }.class("row")
                                 .style([StyleAttribute(key: "padding-left", value: "\(20 * rowData.indentation)px")])
                            }.class("light-bordered-container indent1")
                             .attr("attachment_identifier", rowData.attachmentIdentifier)
                            
                            if rowData.isKeyScreenshot {
                                return row
                                    .class("screenshot-key")
                                    .attr("onmouseenter", #"onMouseEnter(this, '\#(result.identifier)', '\#(rowData.attachmentIdentifier)', '\#(rowData.attachmentContentType)', '\#(rowData.attachmentContentType)')"#)
                                    .attr("onclick", #"onMouseEnter(this, '\#(result.identifier)', '\#(rowData.attachmentIdentifier)', '\#(rowData.attachmentContentType)')"#)
                            } else if rowData.isScreenshot {
                                return row
                                    .attr("onmouseenter", #"onMouseEnter(this, '\#(result.identifier)', '\#(rowData.attachmentIdentifier)', '\#(rowData.attachmentContentType)', '\#(rowData.attachmentContentType)')"#)
                                    .attr("onclick", #"onMouseEnter(this, '\#(result.identifier)', '\#(rowData.attachmentIdentifier)', '\#(rowData.attachmentContentType)')"#)
                            } else {
                                return row
                            }
                        }
                    }
                }
                tableData {
                    if let rowData = rowsData.first {
                        if rowData.isScreenshot {
                            return image(url: "\(AttachmentRoute().path)?result_id=\(result.identifier)&id=\(rowData.attachmentIdentifier)&content_type=\(rowData.attachmentContentType)").id("screenshot-image")
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
                
        var screenshotIdentifier = lastScreenshotIdentifier
        var screenshotContentType = lastScreenshotContentType
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
                default:
                    assertionFailure("Unhandled attachment uniformTypeIdentifier: \(attachment.uniformTypeIdentifier)")
                    continue
                }
                
                let isScreenshot = attachment.name == "kXCTAttachmentLegacyScreenImageData"
                if isScreenshot {
                    screenshotIdentifier = attachmentIdentifier
                    screenshotContentType = attachmentContentType
                }
                
                subRowData += [RowData(indentation: indentation + 1, title: attachmentTitle , attachmentImage: attachmentImage, attachmentIdentifier: attachmentIdentifier, attachmentContentType: attachmentContentType, hasChildren: false, isError: false, isKeyScreenshot: isScreenshot, isScreenshot: isScreenshot)]
            }
                        
            let isError = summary.activityType == "com.apple.dt.xctest.activity-type.testAssertionFailure"
            
            let actionTimestamp = summary.start?.timeIntervalSince1970 ?? currentTimestamp
            subRowData = subRowData + rowsData(from: summary.subactivities, currentTimestamp: currentTimestamp, indentation: indentation + 1, lastScreenshotIdentifier: screenshotIdentifier, lastScreenshotContentType: screenshotContentType)

            title += currentTimestamp - actionTimestamp == 0 ? " (Start)" : " (\(String(format: "%.2f", actionTimestamp - currentTimestamp))s)"
            
            data += [RowData(indentation: indentation, title: title, attachmentImage: nil, attachmentIdentifier: screenshotIdentifier, attachmentContentType: screenshotContentType, hasChildren: subRowData.count > 0, isError: isError, isKeyScreenshot: false, isScreenshot: screenshotIdentifier.count > 0)] + subRowData
        }
        
        return data
    }
}
