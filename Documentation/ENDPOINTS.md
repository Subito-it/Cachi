# Cachi Endpoints

All endpoints are `GET`. A live, reflected listing is always available at `/v1/help`.
Endpoints fall into four groups: **JSON API**, **HTML pages**, **asset/binary**, and **control**.

Legend for the "Data source" column:
- **SQLite** — served from the persistent store (`result_bundle` / `test` rows and the precomputed per-run rollups). Survives `.xcresult` pruning.
- **read-through** — per-test detail served from SQLite/blob store when materialized; otherwise fetched live from the `.xcresult` via `xcresulttool` and persisted for next time (and the export cached under `/tmp/Cachi`).
- **computed** — derived on the fly from indexed SQLite reads.
- **static** — fixed asset or constant.

> See [`ARCHITECTURE.md`](ARCHITECTURE.md) for how the store and the read-through path work.

## JSON API

| Path | Params | Returns | Data source |
|------|--------|---------|-------------|
| `/v1/help` | — | `{path: description}` map of all routes | static (reflected) |
| `/v1/version` | — | Cachi version string | static |
| `/v1/results` | — | List of runs (`ResultInfo`: counts, branch, commit, destinations, links). Built from per-run rollups | SQLite (rollups) |
| `/v1/result` | `?<identifier>` (raw query) | Full `ResultBundle` for one run | SQLite |
| `/v1/results_identifiers` | — | Run identifiers, available even before parse completes | SQLite + quick partial parse |
| `/v1/test` | `?<summaryIdentifier>` (raw query) | Per-test **activity summaries** (steps, attachment metadata) | read-through |
| `/v1/teststats` | `?<md5>` where md5 = `MD5(target-suite-name-model-os)` | Per-test execution history/averages | computed |
| `/v2/teststats` | `?id=<test_summary_identifier>` | Same as v1 but keyed by summary id (resolves the route id internally) | computed |
| `/v1/results_stat` | `?target=&device_model=&device_os=&type=[flaky\|slowest\|fastest\|slowest_flaky]&window_size=` | Ranked stats across runs | computed |

Notes:
- `/v1/test`, `/v1/teststats`, `/v1/result` use the **raw URL query** (`req.url.query`) as the identifier, not a named parameter. `/v2/teststats` uses a named `id=`.
- `/v1/teststats` caps history at ~50 matching runs (indexed by `route_identifier`) and averages over the most recent few; `/v1/results_stat` uses a sliding window (default 20).

## HTML pages (server-rendered with Vaux)

| Path | Params | Page | Data source |
|------|--------|------|-------------|
| `/` | — | Home / landing | SQLite |
| `/html/results` | — | List of runs | SQLite (rollups) |
| `/html/result` | `?id=` | Run detail (passed/failed/retried/crashes) | SQLite |
| `/html/test` | `?id=` | Single test detail: steps, screenshots, attachments | read-through |
| `/html/session_logs` | `?id=` (diagnostics id) | App / runner / session stdout logs | read-through (blob store → live `xcresulttool graph`) |
| `/html/teststats` | `?id=` | Per-test stats page | computed |
| `/html/results_stat` | target/device/type | Stats overview page | computed |
| `/html/coverage` | `?id=` | Coverage summary for a run | live (coverage json) |
| `/html/coverage-file` | `?id=` | Per-file coverage detail | live (split coverage html) |

## Asset / binary routes

| Path | Params | Serves | Data source |
|------|--------|--------|-------------|
| `/css` | — | Stylesheet for HTML pages | static |
| `/script` | — | JS for HTML pages | static |
| `/image` | — | UI images for HTML rendering | static |
| `/attachment` | `result_id=&test_id=&id=&content_type=&filename=` | A single attachment (screenshot/file). Exports from `.xcresult` to `/tmp/Cachi/<result>/...` on first access | read-through → cached file |
| `/video_capture` | `result_id=&test_id=&id=&content_type=&filename=` | MP4 screen recording with generated WebVTT step subtitles muxed in. Prefers the original high-quality recording from the `.xcresult`, falls back to the stored transcoded blob if the bundle was pruned | read-through → cached file |
| `/attachment-viewer` | `viewer=&attachment_filename=` + `attachmentPath` | Auto-generated HTML wrapper that embeds a custom JS viewer | static wrapper |
| `/attachment-viewer/script` | `viewer=&attachment_filename=` | Proxies the configured viewer JS bundle from disk | file |
| `/v1/xcresult` | result/test params | Downloads the original `.xcresult` | filesystem |

## Control routes

| Path | Effect |
|------|--------|
| `/v1/parse` | Triggers a background parse of new bundles. Returns `{status: "parsing N% done"}` if already running, else `{status: "ready"}` and kicks off a parse |
| `/v1/kill` | Quits the Cachi process |

> `/v1/reset` was removed: with the persistent SQLite store it would destroy history that can't be
> regenerated once run folders are pruned. Use `/v1/parse` to ingest new results (non-destructive);
> to wipe everything, stop the server and delete `.cachi-data/`.

## How identifiers relate

- **Bundle identifier** (`result_bundle.identifier`) — from `actionsInvocationMetadata.uniqueIdentifier`. Keys `/v1/result`, links in `/v1/results`.
- **Test `identifier`** (`test.test_identifier`) — `MD5(test.identifier)` from the xcresult; unique per test execution.
- **`routeIdentifier`** (`test.route_identifier`) — `MD5(target-group-name-model-os)`; stable across runs, indexed, used to aggregate history in `/v1/teststats` and `/v2/teststats`.
- **`summaryIdentifier`** (`test.summary_identifier`, **unique** index) — points at the heavy `ActionTestSummary`; used by `/v1/test`, `/html/test`, `/v2/teststats`, attachment/video export, and read-through reconstruction.
- **`diagnosticsIdentifier`** (`test.diagnostics_identifier`) — points at session logs; used by `/html/session_logs` and session-log materialization.

## Performance model

The list/stat/detail-metadata endpoints are fast because they are **indexed SQLite reads**, independent of how many `.xcresult` bundles still exist on disk:

- The results list reads precomputed per-run rollups (`passed_count`, `uniquely_failed_count`, …) straight from `result_bundle`, so its cost scales with the **number of runs**, not the total test count across all history.
- Single-run/single-test/stats lookups use dedicated indexes (`summary_identifier`, `route_identifier`, `(target,device_model,device_os)`) — no full-corpus scan.

The **detail** endpoints (`/v1/test`, `/html/test`, `/html/session_logs`, `/attachment`, `/video_capture`) are read-through: once a failed test's detail has been materialized by background ingest, they serve it from SQLite + the blob store with no `.xcresult` needed. On a miss (e.g. a passing test's step tree, never eagerly stored) they fall back to a live `xcresulttool` call against the bundle and persist the result — so the bundle on disk acts as a self-healing cache, not a hard dependency.
