import CachiKit
import Foundation

extension TestRouteHTML {
    struct TableRowModel {
        enum Media {
            case none
            case child
            case firstInGroup
            
            var available: Bool {
                switch self {
                case .none: return false
                case .child, .firstInGroup: return true
                }
            }
        }
        
        let indentation: Int
        let title: String
        let timestamp: Double
        let attachmentImage: (url: String, width: Int)?
        let attachmentIdentifier: String
        let attachmentContentType: String
        let attachmentFilename: String
        let hasChildren: Bool
        let isError: Bool
        let media: Media

        var isExternalLink: Bool { attachmentContentType == "text/html" }
        var isVideo: Bool { attachmentContentType == "video/mp4" }

        static func makeModels(from actionSummaries: [ActionTestActivitySummary], currentTimestamp: Double, failureSummaries: inout [ActionTestFailureSummary], userInfo: ResultBundle.UserInfo?, indentation: Int = 1, lastCaptureIdentifier: String = "", lastCaptureContentType: String = "", lastAttachmentFilename: String = "") -> [TableRowModel] {
            var data = [TableRowModel]()

            let attachmentDateFormatter = DateFormatter()
            attachmentDateFormatter.dateFormat = "y-MM-dd HH.mm.ss"

            for summary in actionSummaries {
                guard var title = summary.title else {
                    continue
                }

                var subRowData = [TableRowModel]()
                for attachment in summary.attachments {
                    let attachmentIdentifier = attachment.payloadRef?.id ?? ""
                    let attachmentMetadata = attachmentMetadata(from: attachment)

                    let attachmentStartDate = attachment.timestamp ?? summary.start ?? Date()
                    var filename = attachment.filename ?? ""
                    if attachment.name == "kXCTAttachmentScreenRecording" {
                        let filenameDate = attachmentDateFormatter.string(from: attachmentStartDate)
                        filename = "Screen Recording \(filenameDate).mp4"
                    }
                    
                    let hasMedia = ["kXCTAttachmentLegacyScreenImageData", "kXCTAttachmentScreenRecording"].contains(attachment.name)

                    let timestamp = (attachment.timestamp?.timeIntervalSince1970 ?? currentTimestamp) - currentTimestamp

                    subRowData += [TableRowModel(indentation: indentation + 1, title: attachmentMetadata.title, timestamp: timestamp, attachmentImage: attachmentMetadata.image, attachmentIdentifier: attachmentIdentifier, attachmentContentType: attachmentMetadata.contentType, attachmentFilename: filename, hasChildren: false, isError: false, media: hasMedia ? .firstInGroup : .none)]
                }

                let lastCaptureRow = (data + subRowData).reversed().first(where: { $0.media == .firstInGroup })
                let captureIdentifier = lastCaptureRow?.attachmentIdentifier ?? lastCaptureIdentifier
                let captureContentType = lastCaptureRow?.attachmentContentType ?? lastCaptureContentType
                let attachmentFilename = lastCaptureRow?.attachmentFilename ?? lastAttachmentFilename

                let isError = summary.activityType == "com.apple.dt.xctest.activity-type.testAssertionFailure"

                subRowData += makeModels(from: summary.subactivities, currentTimestamp: currentTimestamp, failureSummaries: &failureSummaries, userInfo: userInfo, indentation: indentation + 1, lastCaptureIdentifier: captureIdentifier, lastCaptureContentType: captureContentType, lastAttachmentFilename: attachmentFilename)

                let timestamp = (summary.start?.timeIntervalSince1970 ?? currentTimestamp) - currentTimestamp
                title += timestamp == 0 ? " (Start)" : " (\(String(format: "%.2f", timestamp))s)"

                data += [TableRowModel(indentation: indentation, title: title, timestamp: timestamp, attachmentImage: nil, attachmentIdentifier: captureIdentifier, attachmentContentType: captureContentType, attachmentFilename: attachmentFilename, hasChildren: subRowData.count > 0, isError: isError, media: captureIdentifier.count > 0 ? .child : .none)] + subRowData

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

            data.append(TableRowModel(indentation: indentation, title: failure.message ?? "Failure", timestamp: currentTimestamp, attachmentImage: nil, attachmentIdentifier: "", attachmentContentType: "", attachmentFilename: "", hasChildren: !failure.attachments.isEmpty, isError: true, media: .none))
            if var fileName = failure.fileName, let lineNumber = failure.lineNumber {
                fileName = fileName.replacingOccurrences(of: userInfo?.sourceBasePath ?? "", with: "")
                var attachment: (url: String, width: Int)?
                if let githubBaseUrl = userInfo?.githubBaseUrl, let commitHash = userInfo?.commitHash {
                    attachment = (url: "\(githubBaseUrl)/blob/\(commitHash)/\(fileName)#L\(lineNumber)", width: 15)
                }
                data.append(TableRowModel(indentation: indentation + 1, title: "\(fileName):\(lineNumber)", timestamp: currentTimestamp, attachmentImage: attachment, attachmentIdentifier: "", attachmentContentType: "text/html", attachmentFilename: "", hasChildren: false, isError: false, media: .none))
            }

            for attachment in failure.attachments {
                let attachmentIdentifier = attachment.payloadRef?.id ?? ""
                let attachmentMetadata = attachmentMetadata(from: attachment)

                let hasMedia = ["kXCTAttachmentLegacyScreenImageData", "kXCTAttachmentScreenRecording"].contains(attachment.name)

                let timestamp = (attachment.timestamp?.timeIntervalSince1970 ?? currentTimestamp) - currentTimestamp

                data.append(TableRowModel(indentation: indentation + 1, title: attachmentMetadata.title, timestamp: timestamp, attachmentImage: attachmentMetadata.image, attachmentIdentifier: attachmentIdentifier, attachmentContentType: attachmentMetadata.contentType, attachmentFilename: attachment.filename ?? "", hasChildren: false, isError: false, media: hasMedia ? .firstInGroup : .none))
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
            case "public.mpeg-4" where attachment.timestamp != nil:
                return ("Screen recording.mp4",
                        "video/mp4",
                        ("/image?imageAttachment", 14))
            default:
                assertionFailure("Unhandled attachment uniformTypeIdentifier: \(attachment.uniformTypeIdentifier)")
            }

            return ("", "", ("", 0))
        }
    }
}
