import AVFoundation
import CachiKit
import Foundation
import os
import Vapor

struct VideoCaptureRoute: Routable {
    static let path = "/video_capture"
    
    let method = HTTPMethod.GET
    let description = "Download video capture (Xcode 15 and newer)"

    func respond(to req: Request) throws -> Response {
        os_log("Video Capture request received", log: .default, type: .info)

        guard let components = req.urlComponents(),
              let queryItems = components.queryItems,
              let resultIdentifier = queryItems.first(where: { $0.name == "result_id" })?.value,
              let testSummaryIdentifier = queryItems.first(where: { $0.name == "test_id" })?.value,
              let attachmentIdentifier = queryItems.first(where: { $0.name == "id" })?.value,
              let contentType = queryItems.first(where: { $0.name == "content_type" })?.value,
              resultIdentifier.count > 0, attachmentIdentifier.count > 0
        else {
            return Response(status: .notFound, body: Response.Body(stringLiteral: "Not found..."))
        }

        let benchId = benchmarkStart()
        defer { os_log("Video Capture with id '%@' in result bundle '%@' fetched in %fms", log: .default, type: .info, attachmentIdentifier, resultIdentifier, benchmarkStop(benchId)) }

        guard let test = State.shared.test(summaryIdentifier: testSummaryIdentifier) else {
            return Response(status: .notFound, body: Response.Body(stringLiteral: "Not found..."))
        }

        let videoCaptureUrl = Cachi.temporaryFolderUrl.appendingPathComponent(resultIdentifier).appendingPathComponent("vc-\(attachmentIdentifier.md5Value).mp4")

        let filemanager = FileManager.default
        try? filemanager.createDirectory(at: videoCaptureUrl.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)

        if !filemanager.fileExists(atPath: videoCaptureUrl.path) {
            let videoUrl = Cachi.temporaryFolderUrl.appendingPathComponent(resultIdentifier).appendingPathComponent("\(attachmentIdentifier.md5Value).mp4")
            if !filemanager.fileExists(atPath: videoUrl.path) {
                let cachi = CachiKit(url: test.xcresultUrl)
                try? cachi.export(identifier: attachmentIdentifier, destinationPath: videoUrl.path)
            }

            let activitySummary = State.shared.testActionSummary(test: test)

            let steps = testSteps(for: activitySummary?.activitySummaries ?? [])
            aggregateSteps(steps, depth: 2)

            let vttUrl = Cachi.temporaryFolderUrl.appendingPathComponent(resultIdentifier).appendingPathComponent("\(attachmentIdentifier.md5Value).vtt")
            makeVttFile(for: steps, destinationUrl: vttUrl)
            guard filemanager.fileExists(atPath: vttUrl.path) else {
                return Response(status: .notFound, body: Response.Body(stringLiteral: "Failed generating video capture subtitles..."))
            }

            makeVideoCaptureWithSubtitles(destinationUrl: videoCaptureUrl, videoUrl: videoUrl, subtitleUrl: vttUrl)
        }

        var headers = [
            ("Content-Type", contentType),
            ("Accept-Ranges", "bytes"),
        ]
        if let filename = queryItems.first(where: { $0.name == "filename" })?.value?.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
            headers.append(("Content-Disposition", value: "attachment; filename=\(filename)"))
        }

        let response = req.fileio.streamFile(at: videoCaptureUrl.path(percentEncoded: false))
        for header in headers {
            response.headers.add(name: header.0, value: header.1)
        }

        return response
    }
    
    static func urlString(identifier: String, resultIdentifier: String, testSummaryIdentifier: String, filename: String, contentType: String) -> String {
        var components = URLComponents(string: path)!
        components.queryItems = [
            .init(name: "result_id", value: resultIdentifier),
            .init(name: "id", value: identifier),
            .init(name: "test_id", value: testSummaryIdentifier),
            .init(name: "filename", value: filename),
            .init(name: "content_type", value: contentType),
        ]
        
        components.queryItems = components.queryItems?.filter { !($0.value?.isEmpty ?? true) }
        
        return components.url!.absoluteString
    }
}

private class TestSteps {
    var title: String
    var start: Double
    var finish: Double

    init(title: String, start: Double, finish: Double) {
        self.title = title
        self.start = start
        self.finish = finish
    }
}

// MARK: - Step subtitles

private extension VideoCaptureRoute {
    static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        formatter.timeZone = TimeZone(abbreviation: "UTC")

        return formatter
    }()

    func testSteps(for activitySummaries: [ActionTestActivitySummary]) -> [TestSteps] {
        var result = [TestSteps]()

        for summary in activitySummaries {
            if let title = summary.title, let start = summary.start?.timeIntervalSince1970, let finish = summary.finish?.timeIntervalSince1970 {
                result.append(TestSteps(title: title, start: start, finish: finish))
            }

            result += testSteps(for: summary.subactivities)
        }

        return result
    }

    func aggregateSteps(_ steps: [TestSteps], depth: Int) {
        for (index, step) in steps.enumerated().reversed() {
            var aggregateCandidates = [TestSteps]()
            for aggregateIndex in 0 ..< index {
                if steps[aggregateIndex].start <= step.start, steps[aggregateIndex].finish >= step.finish {
                    aggregateCandidates.append(steps[aggregateIndex])
                }
            }

            let aggregatedSteps = aggregateCandidates.suffix(depth) + [step]
            step.title = aggregatedSteps.enumerated().map { index, step in
                switch index {
                case 0:
                    return step.title
                default:
                    return String(repeating: " ", count: index) + "· \(step.title)"
                }

            }.joined(separator: "\n")
        }
    }

    func makeVttFile(for steps: [TestSteps], destinationUrl: URL) {
        guard let initialStart = steps.first?.start else {
            return
        }

        var lines = [
            "WEBVTT",
            "",
            "STYLE",
            "::cue {",
            "  font-size: 80%",
            "}",
            "",
        ]

        let addStep: (String, Double, Double) -> Void = { title, startTime, stopTime in
            let startString = Self.formatter.string(from: Date(timeIntervalSinceReferenceDate: startTime - initialStart))
            let finishString = Self.formatter.string(from: Date(timeIntervalSinceReferenceDate: stopTime - initialStart))

            lines.append("\(startString) --> \(finishString) align:left")
            lines += title.components(separatedBy: "\n")
            lines.append("")
        }

        for index in 0 ..< steps.count - 1 {
            addStep(steps[index].title, steps[index].start, steps[index + 1].start)
        }

        let lastStepIndex = steps.count - 1
        addStep(steps[lastStepIndex].title, steps[lastStepIndex].start, steps[lastStepIndex].finish)

        let data = Data(lines.joined(separator: "\n").utf8)

        do {
            try data.write(to: destinationUrl)
        } catch {
            os_log("Failed generating capture subtitles with error %@", log: .default, type: .error, error.localizedDescription)
        }
    }

    func makeVideoCaptureWithSubtitles(destinationUrl: URL, videoUrl: URL, subtitleUrl: URL) {
        let videoAsset = AVURLAsset(url: videoUrl)
        let subtitleAsset = AVURLAsset(url: subtitleUrl)

        let composition = AVMutableComposition()

        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let subtitleTrack = composition.addMutableTrack(withMediaType: .text, preferredTrackID: kCMPersistentTrackID_Invalid)
        else {
            return
        }

        let semaphore = DispatchSemaphore(value: 0)
        Task.detached(priority: .userInitiated) {
            defer { semaphore.signal() }

            do {
                let videoAssetDuration = try await videoAsset.load(.duration)
                let timeRange = CMTimeRangeMake(start: .zero, duration: videoAssetDuration)

                guard let videoAssetTrack = try await videoAsset.loadTracks(withMediaType: .video).first,
                      let subtitleAssetTrack = try await subtitleAsset.loadTracks(withMediaType: .text).first
                else {
                    return
                }

                try videoTrack.insertTimeRange(timeRange, of: videoAssetTrack, at: CMTime.zero)
                try subtitleTrack.insertTimeRange(timeRange, of: subtitleAssetTrack, at: CMTime.zero)

                guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
                    return
                }

                exportSession.outputURL = destinationUrl
                exportSession.outputFileType = .mp4

                await exportSession.export()
            } catch {
                os_log("Failed exporting video with error %@", log: .default, type: .error, error.localizedDescription)
            }
        }

        semaphore.wait()
    }
}
