import CachiKit
import Foundation
import os

/// Deferred, low-priority work that runs after the high-priority structured dump completes.
/// For each failed test it: (1) extracts structured detail (activity tree, failures, manifests)
/// from the `.xcresult`, then (2) materializes the heavy blobs — transcodes the screen recording
/// and gzips the session logs into the content-addressed blob store.
///
/// Everything is idempotent and resumable: a test with detail already present is skipped, and a
/// blob whose hash column is already set is not re-materialized. A failure flood only grows the
/// backlog; it never blocks parse or request serving (the raw artifact stays servable from the
/// bundle via the read-through fallback in the routes).
final class BackgroundIngest {
    private let store: ResultStore
    private let blobStore: BlobStore
    private let extractor: DetailExtractor

    /// Cap on concurrent heavy work so transcoding doesn't starve request serving.
    private let maxConcurrent = max(1, ProcessInfo.processInfo.activeProcessorCount / 2)

    private let workQueue = OperationQueue()

    /// Guards against overlapping passes: repeated `/v1/parse` (or a parse during an in-flight
    /// background pass) would otherwise launch a second `run()` over the same pending set and
    /// redo the same transcodes/extractions concurrently. Work is idempotent, so this only avoids
    /// wasted CPU, not corruption.
    private let runLock = NSLock()
    private var isRunning = false

    init(store: ResultStore, blobStore: BlobStore) {
        self.store = store
        self.blobStore = blobStore
        self.extractor = DetailExtractor(store: store)
        workQueue.maxConcurrentOperationCount = maxConcurrent
    }

    /// Processes all failed tests still needing detail/blobs. Safe to call repeatedly: concurrent
    /// invocations after the first return immediately (see `runLock`/`isRunning`).
    func run() {
        runLock.lock()
        guard !isRunning else {
            runLock.unlock()
            os_log("Background ingest already running; skipping overlapping pass", log: .default, type: .info)
            return
        }
        isRunning = true
        runLock.unlock()
        defer {
            runLock.lock()
            isRunning = false
            runLock.unlock()
        }

        let pending = store.testsNeedingDetailExtraction()
        guard !pending.isEmpty else { return }

        let benchId = benchmarkStart()
        os_log("Background ingest: %ld failed tests need detail extraction", log: .default, type: .info, pending.count)

        for item in pending {
            workQueue.addOperation { [weak self] in
                self?.process(testRowId: item.rowId, test: item.test)
            }
        }
        workQueue.waitUntilAllOperationsAreFinished()

        os_log("Background ingest completed in %fms", log: .default, type: .info, benchmarkStop(benchId))
    }

    /// Runs `run()` off the calling thread, invoking `completion` once all work has finished
    /// (blobs are then fully materialized on disk).
    func runAsync(completion: (() -> Void)? = nil) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.run()
            completion?()
        }
    }

    private func process(testRowId: Int, test: ResultBundle.Test) {
        // 1. Structured detail (also records attachment + session-log manifests).
        guard extractor.extractDetail(testRowId: testRowId, test: test) else { return }

        // 2. Heavy blobs.
        materializeVideos(testRowId: testRowId, test: test)
        materializeSessionLogs(testRowId: testRowId, test: test)
    }

    private func materializeVideos(testRowId: Int, test: ResultBundle.Test) {
        let pending = store.videoAttachmentsNeedingBlob(testRowId: testRowId)
        guard !pending.isEmpty else { return }

        let cachi = CachiKit(url: test.xcresultUrl)
        for video in pending {
            autoreleasepool {
                let scratch = Cachi.temporaryFolderUrl.appendingPathComponent("ingest-\(UUID().uuidString)")
                let rawUrl = scratch.appendingPathComponent("raw.mp4")
                let outUrl = scratch.appendingPathComponent("out.mp4")
                try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: scratch) }

                do {
                    try cachi.export(identifier: video.payloadRef, destinationPath: rawUrl.path)
                    try VideoTranscoder.transcode(sourceUrl: rawUrl, destinationUrl: outUrl)
                    let hash = try blobStore.store(fileAt: outUrl, kind: .video)
                    store.setAttachmentBlobHash(attachmentId: video.attachmentId, hash: hash, contentType: "video/mp4")
                } catch {
                    os_log("Background video transcode failed for test row %ld: %@", log: .default, type: .error, testRowId, "\(error)")
                }
            }
        }
    }

    private func materializeSessionLogs(testRowId: Int, test: ResultBundle.Test) {
        let pending = store.sessionLogsNeedingBlob(testRowId: testRowId)
        guard !pending.isEmpty, let diagnosticsIdentifier = test.diagnosticsIdentifier else { return }

        let cachi = CachiKit(url: test.xcresultUrl)
        guard let logs = try? cachi.actionInvocationSessionLogs(identifier: diagnosticsIdentifier, sessionLogs: .all) else {
            return
        }

        for log in pending {
            guard let text = sessionLogText(logs, kind: log.kind), !text.isEmpty else { continue }
            let data = Data(text.utf8)
            guard let gzipped = data.cachiGzipped() else { continue }
            do {
                let hash = try blobStore.store(gzipped, kind: .sessionLog)
                store.setSessionLogBlobHash(logId: log.logId, hash: hash)
            } catch {
                os_log("Background session log store failed for test row %ld: %@", log: .default, type: .error, testRowId, "\(error)")
            }
        }
    }

    private func sessionLogText(_ logs: [CachiKit.SessionLogs: String], kind: String) -> String? {
        switch kind {
        case "app": logs[.appStdOutErr]
        case "runner": logs[.runnerAppStdOutErr]
        case "session": logs[.session]
        case "scheduling": logs[.scheduling]
        default: nil
        }
    }
}
