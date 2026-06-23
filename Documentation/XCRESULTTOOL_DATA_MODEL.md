# xcresulttool data model — full inventory (via CachiKit)

> Purpose: a complete, crystal-clear map of **everything** `xcresulttool` exposes through CachiKit, so we know exactly which data is structured (cheap → SQLite) and which is large/binary (blob store). This is the reference behind Cachi's persistence layer; for how the two stores fit together at runtime see [`ARCHITECTURE.md`](ARCHITECTURE.md), and for the measured cost of ingesting it see [`INGEST_BENCHMARK.md`](INGEST_BENCHMARK.md).

CachiKit wraps five `xcresulttool` invocations (`CachiKit.swift`):

| CachiKit method | Underlying command | Returns | Cost |
|-----------------|--------------------|---------|------|
| `actionsInvocationRecord()` | `get --format json` (root) | `ActionsInvocationRecord` | cheap, one per xcresult |
| `actionsInvocationMetadata(id:)` | `get --id` | `ActionsInvocationMetadata` | cheap |
| `actionTestPlanRunSummaries(id:)` | `get --id` | `ActionTestPlanRunSummaries` | medium (whole test tree) |
| `actionTestSummary(id:)` | `get --id` | `ActionTestSummary` | **heavy** (per-test detail, references blobs) |
| `actionInvocationSessionLogs(id:)` | `graph --id` + `get --id` | `[SessionLogs: String]` | **heavy** (raw text logs) |
| `export(id:destinationPath:)` | `export --type file` | writes a file | **heavy** (the actual blob bytes) |

Everything is reached by **`Reference.id`** values that point to other objects inside the `.xcresult`; `export(id:)` is how the raw bytes behind a `payloadRef` come out.

---

## 1. Object graph (how you traverse the bundle)

```
ActionsInvocationRecord                         [get, root]
├─ metadataRef ─────────▶ ActionsInvocationMetadata   (uniqueIdentifier ← the bundle id)
├─ metrics: ResultMetrics                        (testsCount, testsFailedCount, …)
├─ issues: ResultIssueSummaries
│   └─ testFailureSummaries[]: TestFailureIssueSummary  (message ← "crashed in" heuristic)
├─ archive: ArchiveInfo (path?)
└─ actions[]: ActionRecord
    ├─ startedTime / endedTime                   (run timing)
    ├─ runDestination: ActionRunDestinationRecord
    │   └─ targetDeviceRecord: ActionDeviceRecord (modelName, operatingSystemVersion, identifier, …)
    └─ actionResult: ActionResult
        ├─ coverage: CodeCoverageInfo (hasCoverageData, reportRef, archiveRef)
        ├─ testsRef ───────▶ ActionTestPlanRunSummaries   [get]
        ├─ diagnosticsRef ─▶ (session logs graph)         [graph]
        └─ logRef / timelineRef (unused by Cachi)

ActionTestPlanRunSummaries
└─ summaries[]: ActionTestPlanRunSummary
    └─ testableSummaries[]: ActionTestableSummary
        ├─ targetName, projectRelativePath, testKind, testLanguage, testRegion
        ├─ diagnosticsDirectoryName
        └─ tests[]: ActionTestSummaryGroup   (recursive group tree: suite → class → …)
            └─ subtests[]: ActionTestSummaryIdentifiableObject
                ├─ ActionTestSummaryGroup   (nested groups)
                └─ ActionTestMetadata        ← THE LEAF (one per test case)
                    ├─ identifier, name, testStatus, duration
                    ├─ summaryRef ─────────▶ ActionTestSummary   [get, heavy]
                    ├─ performanceMetricsCount / failureSummariesCount / activitySummariesCount
                    └─ (diagnosticsRef comes from the parent ActionRecord)

ActionTestSummary                                [get via summaryRef.id — heavy]
├─ testStatus, duration
├─ performanceMetrics[]: ActionTestPerformanceMetricSummary
├─ failureSummaries[]: ActionTestFailureSummary
│   ├─ message, fileName, lineNumber, issueType, detailedDescription, timestamp
│   ├─ sourceCodeContext: SourceCodeContext (location + callStack[])
│   ├─ associatedError: TestAssociatedError (domain, code)
│   └─ attachments[]: ActionTestAttachment ◀── BLOBS attached to failures
├─ skipNoticeSummary: ActionTestNoticeSummary
└─ activitySummaries[]: ActionTestActivitySummary  (recursive step tree)
    ├─ title, activityType, uuid, start, finish
    ├─ failureSummaryIDs[]
    ├─ subactivities[]: ActionTestActivitySummary   (recursion)
    └─ attachments[]: ActionTestAttachment ◀──────── BLOBS (screenshots, video, …)

ActionTestAttachment                              ← the blob descriptor
├─ uniformTypeIdentifier   (public.jpeg / public.png / public.mpeg-4 / public.plain-text / …)
├─ name                    (kXCTAttachmentLegacyScreenImageData, kXCTAttachmentScreenRecording, …)
├─ filename, timestamp, lifetime, payloadSize
└─ payloadRef ─────────────▶ export(id:) → raw bytes on disk   ◀── THE ACTUAL BLOB
```

---

## 2. Where the volume is — blob inventory

The **only** things that carry real bytes are `ActionTestAttachment.payloadRef` payloads and the session-log text. Everything else is small structured metadata. The attachment kinds Cachi recognizes (from `TestRouteHTML+Model.swift`, switch on `uniformTypeIdentifier` + `name`):

| `uniformTypeIdentifier` | `name` | Meaning | Typical size | Stored when |
|--------------------------|--------|---------|--------------|-------------|
| `public.png` | `kXCTAttachmentLegacyScreenImageData` | **Automatic per-step screenshot** | 50 KB – 1 MB each, **many per test** | mostly on failure paths |
| `public.jpeg` | `kXCTAttachmentLegacyScreenImageData` | Automatic screenshot (jpeg) | 20–300 KB each, many | mostly on failure |
| `public.png` / `public.jpeg` | (custom) | User-added screenshot | varies | any |
| `public.mpeg-4` | `kXCTAttachmentScreenRecording` | **Full screen recording** | **1 MB – 100s of MB**, 1 per test | Xcode 15+, on capture |
| `public.plain-text` | (custom / `kXCTAttachment...`) | User text / logs | small–medium | any |
| `public.json` | (custom) | User JSON payload | small–medium | any |
| `public.data` / other | (custom) | Arbitrary binary | varies | any |
| `text/html` (synthesized) | — | Source-location link, **not a real payload** | n/a | derived in UI |

**Key facts for sizing:**
- `ActionTestAttachment.payloadSize` gives the **exact byte size up front** — we can budget/sum before exporting anything.
- Screenshots dominate by *count*; the screen recording dominates by *size per test*.
- Attachments hang off **both** `activitySummaries[].attachments` (the step-by-step screenshots / the recording) **and** `failureSummaries[].attachments` (failure-specific captures).
- The same logical screenshot (e.g. "app launch" frame, or a failure frame repeated across retries) recurs across tests/runs → strong case for **content-addressed dedup**, which `BlobStore` implements by keying on the SHA-256 of the exported bytes. `payloadRef.id` is per-bundle, **not** a content hash, so dedup must hash the exported bytes (which is exactly what `BlobStore.hash(ofFileAt:)` does).

### Session logs (separate heavy text channel)
Reached via `ActionResult.diagnosticsRef` → `actionInvocationSessionLogs`, returning up to four text strings keyed by `SessionLogs`:
- `.appStdOutErr` — app stdout/stderr
- `.runnerAppStdOutErr` — UI-test runner stdout/stderr
- `.session` — the test session log
- `.scheduling` — scheduling.log

These are **plain text, can be large, and compress extremely well** (gzip) → blob store with compression, not SQLite TEXT columns. Note CachiKit's 4 KB head-handler hack exists precisely because these graphs/logs can be huge.

---

## 3. Structured data (cheap → SQLite columns)

Everything below is small and queryable. It is the "store forever for history" tier.

### Run-level (`ActionsInvocationRecord` + `ActionRecord` + metadata)
- `uniqueIdentifier` (bundle PK), `creatingWorkspaceFilePath`, scheme info
- `startedTime`, `endedTime`, `schemeCommandName`, `schemeTaskName`, `title`
- `ResultMetrics`: `testsCount`, `testsFailedCount`, `testsSkippedCount`, `errorCount`, `warningCount`, `analyzerWarningCount`
- `CodeCoverageInfo.hasCoverageData` (+ refs to the coverage report blob)
- `ArchiveInfo.path`

### Device / destination (`ActionRunDestinationRecord` → `ActionDeviceRecord`, `ActionSDKRecord`, `ActionPlatformRecord`)
- `modelName`, `modelCode`, `modelUTI`, `identifier`, `name`
- `operatingSystemVersion`, `operatingSystemVersionWithBuildNumber`, `nativeArchitecture`
- SDK: `name`, `identifier`, `operatingSystemVersion`
- platform: `identifier`, `userDescription`
- (hardware fields: cpuKind/cpuCount/ramSizeInMegabytes/… — available, mostly unused by Cachi today)

### Test tree (`ActionTestableSummary` → `ActionTestSummaryGroup` → `ActionTestMetadata`)
- target: `targetName`, `projectRelativePath`, `testKind`, `testLanguage`, `testRegion`, `diagnosticsDirectoryName`
- group: `identifier`, `name`, `duration` (recursive)
- **test leaf** (`ActionTestMetadata`): `identifier`, `name`, `testStatus`, `duration`, `summaryRef.id`, and the `*Count` hints (`performanceMetricsCount`, `failureSummariesCount`, `activitySummariesCount`) — these counts let us know whether detail/blobs exist **without fetching the heavy summary**.

### Per-test detail structure (`ActionTestSummary`, excluding blob bytes)
- `testStatus`, `duration`
- `performanceMetrics[]`: `displayName`, `unitOfMeasurement`, `measurements[]`, baseline/regression stats — all small numeric.
- `failureSummaries[]`: `message`, `fileName`, `lineNumber`, `issueType`, `detailedDescription`, `timestamp`, `isTopLevelFailure`, `sourceCodeContext` (location + `callStack[]` of `SourceCodeFrame`), `associatedError` (domain/code).
- `activitySummaries[]` (the step tree): `title`, `activityType`, `uuid`, `start`, `finish`, `failureSummaryIDs[]`, nested `subactivities[]`. **The tree shape + titles + timings are structured/cheap**; only the `attachments[]` payloads under it are blobs.
- `skipNoticeSummary`: `message`, `fileName`, `lineNumber`.

### Issues (run-level, `ResultIssueSummaries`)
- `testFailureSummaries[]`: `testCaseName`, `issueType`, `message`, `producingTarget`, `documentLocationInCreatingWorkspace` — Cachi already uses these `message`s for the optimistic crash count.
- `errorSummaries` / `warningSummaries` / `analyzerWarningSummaries[]`: `issueType`, `message`, `producingTarget`, location.

### Build-log section types (`ActivityLog*`)
Defined in CachiKit but **not currently fetched** by Cachi (no `logRef` traversal). Structured (titles, durations, results, messages, emitted output). Relevant only if we ever want build-log history. The `emittedOutput`/`commandDetails` fields can be large text → blob if ever used.

---

## 4. Notes / gotchas discovered in the types

- **`SortedKeyValueArrayPair` only decodes `key`** — the value is dropped (CachiKit TODO comment). So `ActionTestAttachment.userInfo` and `TestAssociatedError.userInfo` values are **not available** today. If we want them, CachiKit needs fixing first.
- **`ActionRunDestinationRecord` bug**: `targetSDKRecord` is decoded from the `localComputerRecord` key (copy-paste error). Worth noting if SDK data matters.
- **Crash detection is heuristic**: derived from issue-summary messages containing `" crashed in "`, not from authoritative per-test data (the accurate path would open every `ActionTestSummary`, which is the heavy call we're trying to avoid).
- **`payloadSize` is authoritative and free** — use it to compute storage budgets and to drive retention decisions before exporting bytes.
- **Attachment `lifetime`** field (`keepAlways` vs `deleteOnSuccess`) signals Xcode's own intent: success-path attachments are often marked deletable. This aligns with the "failure-only blob retention" strategy.
- Activities and attachments live **only** inside the heavy `ActionTestSummary` (reached per-test via `summaryRef`). To persist them for history we must fetch+store at ingest for the tests we care about (failures), shifting that cost from request-time to ingest-time.

---

## 5. Mapping to the implemented persistence layer

This is how the inventory above lands in Cachi's actual SQLite schema (`Database.swift`, schema v1) and blob store (`BlobStore.swift`). Each xcresult concept maps to a concrete table/column:

| xcresult data | Character | Where it lands today |
|---------------|-----------|----------------------|
| Run / device / metrics / coverage flags | small, structured | `result_bundle` row (+ derived rollups: `passed_count`, `uniquely_failed_count`, `crash_count`, `has_coverage`, `first_*`) |
| Test tree + leaf metadata (status, duration, ids) | small, structured, high-value for stats | `test` rows (flattened; `summary_identifier` UNIQUE, `route_identifier` indexed for stats) |
| Activity step tree (titles, timing, uuids, hierarchy) | small, structured | `activity` rows (self-referential `parent_id` tree; `failure_summary_ids` as JSON) |
| Failure summaries (message, file, line, detailedDescription) | small–medium text | `failure` rows (`detail` column holds `detailedDescription`) |
| Performance metrics | small numeric | `performance_metric` rows (`measurements_json`) |
| Attachment **descriptors** (UTI, name, filename, payloadSize, timestamp) | small, structured | `attachment` rows (`blob_hash` references the `blob` manifest; NULL until materialized) |
| Session-log channels (which of the 4 exist) | small, structured | `session_log` rows (`kind` ∈ app/runner/session/scheduling; `blob_hash` NULL until gzipped) |
| Attachment **payload bytes** (video; screenshots if ever captured) | **large binary** | `BlobStore` (`.cachi-data/blobs/`), content-addressed, **failure-only** (only failed tests get detail extraction) |
| Session-log **text** | **large text** | `BlobStore`, **gzipped**, content-addressed |
| Coverage report (html/json/archive) | large | filesystem (split per-file/per-folder), not in SQLite |

**What is and isn't eagerly stored.** Only **failed** tests get detail extraction (`testsNeedingDetailExtraction()` filters on `status='failure'`), so passing tests keep just their `test`-row metadata — their step trees, attachments, and logs are read live from the `.xcresult` on demand (read-through) for as long as the bundle survives external pruning. This is the single biggest lever on DB size (see [`INGEST_BENCHMARK.md`](INGEST_BENCHMARK.md) §disk footprint).

**Blob `kind`s actually emitted today:** `video` (transcoded mpeg-4) and `sessionLog` (gzipped text). `screenshot`/`attachment` kinds exist in the `BlobStore.Kind` enum but the current capture style is video-only, so no screenshot bytes are written.

Bottom line: of everything `xcresulttool` exposes, only **attachment payloads** and **session-log text** are heavy. They are cleanly separable behind `payloadRef`/`diagnosticsRef`, sized in advance via `payloadSize`, dominated by failure-path screen recordings, and Cachi keeps them out of SQLite — in a deduplicated, compressed, failure-only blob store with an optional disk cap (`--max_disk_size`).
</content>
