import CachiKit
import Foundation

extension TestRouteHTML {
    struct TableRowModel {
        let uuid: String
        let title: String
        let timestamp: Double
        let attachment: Attachment?
        let hasChildren: Bool
        let isError: Bool
        let indentation: Int

        static func makeModels(from actionSummaries: [ActionTestActivitySummary], initialTimestamp: Double, failureSummaries: [ActionTestFailureSummary], userInfo: ResultBundle.UserInfo?, indentation: Int = 1) -> [TableRowModel] {
            var data = [TableRowModel]()

            for summary in actionSummaries {
                guard var title = summary.title else {
                    continue
                }

                var subRowData = [TableRowModel]()
                for summaryAttachment in summary.attachments {
                    guard let attachment = Attachment(from: summaryAttachment) else { continue }

                    let timestamp = (attachment.timestamp ?? initialTimestamp) - initialTimestamp

                    subRowData += [TableRowModel(uuid: attachment.identifier, title: attachment.title, timestamp: timestamp, attachment: attachment, hasChildren: false, isError: false, indentation: indentation + 1)]
                }

                subRowData += makeModels(from: summary.subactivities, initialTimestamp: initialTimestamp, failureSummaries: failureSummaries, userInfo: userInfo, indentation: indentation + 1)

                let timestamp = (summary.start?.timeIntervalSince1970 ?? initialTimestamp) - initialTimestamp
                title += timestamp == 0 ? " (Start)" : " (\(String(format: "%.2f", timestamp))s)"

                let isError = summary.activityType == "com.apple.dt.xctest.activity-type.testAssertionFailure"
                data += [TableRowModel(uuid: summary.uuid, title: title, timestamp: timestamp, attachment: nil, hasChildren: subRowData.count > 0, isError: isError, indentation: indentation)] + subRowData

                for failureSummaryID in summary.failureSummaryIDs {
                    guard let failureSummary = failureSummaries.first(where: { $0.uuid == failureSummaryID }) else {
                        continue
                    }

                    data += makeFailureModel(failureSummary, initialTimestamp: initialTimestamp, userInfo: userInfo, indentation: indentation)
                }
            }

            return data
        }

        static func makeFailureModel(_ failure: ActionTestFailureSummary, initialTimestamp: Double, userInfo: ResultBundle.UserInfo?, indentation: Int) -> [TableRowModel] {
            var data = [TableRowModel]()

            data.append(TableRowModel(uuid: failure.uuid, title: failure.message ?? "Failure", timestamp: initialTimestamp, attachment: nil, hasChildren: !failure.attachments.isEmpty, isError: true, indentation: indentation))
            if var fileName = failure.fileName, let lineNumber = failure.lineNumber {
                var attachment: Attachment?
                if let githubBaseUrl = userInfo?.githubBaseUrl, let commitHash = userInfo?.commitHash {
                    fileName = fileName.replacingOccurrences(of: userInfo?.sourceBasePath ?? "", with: "")
                    attachment = Attachment(
                        identifier: "",
                        title: "\(fileName):\(lineNumber)",
                        url: "\(githubBaseUrl)/blob/\(commitHash)/\(fileName)#L\(lineNumber)",
                        width: 15,
                        filename: fileName,
                        contentType: "text/html",
                        captureMedia: .none,
                        timestamp: initialTimestamp
                    )
                }

                data.append(TableRowModel(uuid: failure.uuid, title: "\(fileName):\(lineNumber)", timestamp: initialTimestamp, attachment: attachment, hasChildren: false, isError: false, indentation: indentation + 1))
            }

            for failureAttachment in failure.attachments {
                guard let attachment = Attachment(from: failureAttachment) else { continue }

                let timestamp = (attachment.timestamp ?? initialTimestamp) - initialTimestamp

                data.append(TableRowModel(uuid: attachment.identifier, title: attachment.title, timestamp: timestamp, attachment: attachment, hasChildren: false, isError: false, indentation: indentation + 1))
            }

            return data
        }
    }
}

// MARK: - Attachment

extension TestRouteHTML.TableRowModel {
    struct Attachment {
        enum CaptureMedia {
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

        let identifier: String
        let title: String
        let url: String
        let width: Int
        let filename: String
        let contentType: String
        let captureMedia: CaptureMedia
        let timestamp: Double?

        var isExternalLink: Bool { contentType == "text/html" }

        private static let filenameDateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "y-MM-dd HH.mm.ss"
            return formatter
        }()

        init(identifier: String, title: String, url: String, width: Int, filename: String, contentType: String, captureMedia: CaptureMedia, timestamp: Double?) {
            self.identifier = identifier
            self.title = title
            self.url = url
            self.width = width
            self.filename = filename
            self.contentType = contentType
            self.timestamp = timestamp
            self.captureMedia = captureMedia
        }

        init?(from attachment: ActionTestAttachment) {
            guard let identifier = attachment.payloadRef?.id else { return nil }
            self.identifier = identifier
            captureMedia = ["kXCTAttachmentLegacyScreenImageData", "kXCTAttachmentScreenRecording"].contains(attachment.name) ? .firstInGroup : .none
            timestamp = attachment.timestamp?.timeIntervalSince1970

            var timestampString = ""
            if let timestamp = attachment.timestamp {
                timestampString = " " + Self.filenameDateFormatter.string(from: timestamp)
            }

            switch attachment.uniformTypeIdentifier {
            case "public.plain-text", "public.utf8-plain-text", "public.text":
                filename = attachment.filename ?? "User data\(timestampString).txt"
                title = filename
                contentType = "text/plain"
                url = ImageRoute.attachmentImageUrl()
                width = 14
            case "public.json":
                title = (attachment.name ?? "User data") + ".json"
                filename = attachment.filename ?? "JSON \(timestampString).json"
                contentType = "application/json"
                url = ImageRoute.attachmentImageUrl()
                width = 14
            case "public.jpeg":
                let title = attachment.name == "kXCTAttachmentLegacyScreenImageData" ? "Automatic Screenshot" : (attachment.name ?? "User image attachment")
                self.title = title
                filename = "\(title)\(timestampString).jpg"
                contentType = "image/jpeg"
                url = ImageRoute.placeholderImageUrl()
                width = 18
            case "public.png":
                let title = attachment.name == "kXCTAttachmentLegacyScreenImageData" ? "Automatic Screenshot" : (attachment.name ?? "User image attachment")
                self.title = title
                filename = "\(title)\(timestampString).png"
                contentType = "image/png"
                url = ImageRoute.placeholderImageUrl()
                width = 18
            case "public.data":
                title = attachment.name ?? "Binary data"
                filename = attachment.filename ?? "Data\(timestampString).bin"
                contentType = "text/plain"
                url = ImageRoute.attachmentImageUrl()
                width = 14
            case "public.mpeg-4" where attachment.name == "kXCTAttachmentScreenRecording":
                let title = "Screen recording"
                self.title = "\(title).mp4"
                filename = "\(title)\(timestampString).mp4"
                contentType = "video/mp4"
                url = ImageRoute.attachmentImageUrl()
                width = 14
            case "com.apple.dt.xctest.element-snapshot":
                // This is an unsupported key archived snapshot of the entire view hierarchy of the app
                return nil
            case "com.apple.dt.xctest.synthesized-event-record":
                // This is an unsupported  of the interaction gesture associated to the step
                // The plist should be parsed and could be used to show with an overlay on the
                // screen capture where used did interact with the UI
                return nil
            default:
                return nil
            }
        }
    }
}
