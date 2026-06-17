import CachiKit
import Foundation
import os

/// Pulls the heavy per-test detail (activity tree, failures, performance metrics, attachment and
/// session-log manifests) out of an `.xcresult` for a single failed test and writes it to SQLite.
/// Blob bytes are materialized separately (video transcode / log gzip); this only records the
/// structured manifest, leaving `blob_hash` NULL.
struct DetailExtractor {
    let store: ResultStore

    /// Extracts and persists structured detail for one failed test. Returns true on success.
    @discardableResult
    func extractDetail(testRowId: Int, test: ResultBundle.Test) -> Bool {
        guard let summaryIdentifier = test.summaryIdentifier else { return false }

        let cachi = CachiKit(url: test.xcresultUrl)
        guard let summary = try? cachi.actionTestSummary(identifier: summaryIdentifier) else {
            return false
        }

        var activities = [ResultStore.ActivityRow]()
        var attachments = [ResultStore.AttachmentRow]()
        flatten(summary.activitySummaries, parentUuid: nil, into: &activities, attachments: &attachments)

        let failures = summary.failureSummaries.map {
            ResultStore.FailureRow(message: $0.message,
                                   file: $0.fileName,
                                   line: $0.lineNumber,
                                   detail: $0.detailedDescription)
        }

        // Session-log channels available for this test (diagnostics present → all four kinds).
        let sessionLogKinds = test.diagnosticsIdentifier != nil
            ? ["app", "runner", "session", "scheduling"]
            : []

        store.writeDetail(testRowId: testRowId,
                          activities: activities,
                          failures: failures,
                          attachments: attachments,
                          sessionLogKinds: sessionLogKinds)
        return true
    }

    private func flatten(_ summaries: [ActionTestActivitySummary],
                         parentUuid: String?,
                         into activities: inout [ResultStore.ActivityRow],
                         attachments: inout [ResultStore.AttachmentRow]) {
        for summary in summaries {
            activities.append(ResultStore.ActivityRow(uuid: summary.uuid,
                                                      parentUuid: parentUuid,
                                                      title: summary.title,
                                                      type: summary.activityType,
                                                      start: summary.start,
                                                      finish: summary.finish))

            for attachment in summary.attachments {
                attachments.append(ResultStore.AttachmentRow(activityUuid: summary.uuid,
                                                             filename: attachment.filename,
                                                             uti: attachment.uniformTypeIdentifier,
                                                             name: attachment.name,
                                                             payloadRef: attachment.payloadRef?.id,
                                                             payloadSize: attachment.payloadSize,
                                                             contentType: nil))
            }

            flatten(summary.subactivities, parentUuid: summary.uuid, into: &activities, attachments: &attachments)
        }
    }
}
