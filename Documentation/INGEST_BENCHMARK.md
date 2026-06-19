# Ingest benchmark — xcresult → SQLite + blob store

> Measures the wall-clock cost and resulting storage of ingesting real runs into Cachi's
> persistent store, to validate the SQLite-tier + content-addressed-blob-store design. Unlike the
> earlier study (which used a Python proxy reproducing the `xcresulttool` call chain), **these
> numbers were produced by the current release binary itself** — `swift build -c release` then
> running `cachi --merge <run>` against each sample, polling `/v1/parse` for the structured-parse
> wall, and watching the SQLite tables + blob directory until background ingest quiesced.

See [`ARCHITECTURE.md`](ARCHITECTURE.md) for the ingest pipeline and [`XCRESULTTOOL_DATA_MODEL.md`](XCRESULTTOOL_DATA_MODEL.md) for what is structured vs. heavy.

## Setup

- Machine: local dev Mac (Apple silicon). `xcresulttool version 24514` → legacy command path.
- Binary: `.build/release/cachi`, transcoder = AVFoundation `AVAssetExportPresetMediumQuality` (no external ffmpeg), as shipped in `VideoTranscoder.swift`.
- Samples: `./sample_data`, real E2E runs.
- **These runs are Mendoza-sharded**: each dated folder is *one logical run* (the `--merge` case) made of **one `.xcresult` per test** ("shards ≈ tests"). A passing-test xcresult is ~1 MB; failure xcresults reach 11–48 MB (the screen recording dominates).

| Run folder | Logical run size | xcresults (≈tests) | Failed | Raw video payload |
|------------|------------------|--------------------|--------|-------------------|
| `2026-06-10_172108` | 423 MB | 24 | 0 | — |
| `2026-06-10_174148` | 642 MB | 80 | 2 | 63 MB |
| `2026-06-09_074035` | 2.8 GB | 545 | 7 | 95 MB |
| `2026-06-09_070749` | **7.2 GB** | **1266** (1259 tests) | **70** | **1070 MB** |

## Results — wall-clock & storage

Two phases per run: **(1) structured parse** (lightweight model → `result_bundle` + `test` rows; what `/v1/parse` reports as progress), then **(2) background ingest** (failure-detail extraction + video transcode + log gzip, off the critical path).

| Run | Structured parse | Background ingest | DB size | Blob store | Video blobs |
|-----|------------------|-------------------|---------|-----------|-------------|
| 24-test (0 fail) | **0.4 s** | 0 s (nothing to do) | 128 KB | 0 | 0 |
| 80-test (2 fail) | 2.0 s | 11.8 s | 256 KB | 8.4 MB | 2 |
| 545-test (7 fail) | 11.5 s | 14.5 s | 768 KB | 10.7 MB | 7 |
| **1266-test (70 fail)** | **21.5 s** | **153 s** | **3.1 MB** | **118 MB** | 63 |

## What the numbers say

1. **Structured parse is fast and bounded by `xcresulttool` process spawns.** The whole 7.2 GB / 1259-test run parses in **21.5 s** — one root + tree call per shard. This is the part `/v1/parse` reports progress for and the only part a user waits on before the run appears in the list. The 24- and 80-test runs are sub-second to a couple of seconds.

2. **Background ingest is dominated by video transcode, and scales with failure count — not run size.** The 1266-test run spent ~153 s in the background pass, almost all of it transcoding 63 screen recordings through AVFoundation. The 545-test run, with only 7 failures, finished its background pass in 14.5 s despite being a 2.8 GB run. This is exactly why the work is deferred and overlap-guarded: a failure flood grows the transcode backlog rather than blocking parse or request serving.

3. **The structured DB is tiny — and its size is entirely the failure step trees.** The worst run's database is **3.1 MB for 1259 tests** because only the 70 **failed** tests get their activity trees extracted (`testsNeedingDetailExtraction()` filters on `status='failure'`). That produced exactly **5,684 activity rows** (≈81 steps per failed test). Passing tests keep metadata only. Projection at this ratio:

   | Strategy | per 1266-test run | 1,000 runs | 10,000 runs |
   |----------|-------------------|------------|-------------|
   | Full step tree, **all** tests (hypothetical) | ~84 MB | ~82 GB | ~820 GB |
   | **Failure-only step tree** (what Cachi does) | ~3 MB | ~3 GB | ~30 GB |

   Storing passing-test step trees would inflate the DB ~30×, for data nobody debugs. The rare "show me a passing test's steps" case is served by reading that test's summary live from the `.xcresult` on demand (read-through), so it costs no steady-state storage.

4. **Transcode gives ~9–12× with no external dependency.** The shipped AVFoundation transcoder shrank the raw recordings substantially — measured per run:

   | Run | Raw video | Stored (transcoded) | Reduction |
   |-----|-----------|---------------------|-----------|
   | 80-test | 62.9 MB | 6.9 MB | **9.1×** |
   | 545-test | 95.2 MB | 7.9 MB | **12.1×** |
   | 1266-test | **1070 MB** | **90.8 MB** | **11.8×** |

   So the worst run's ~1.1 GB of screen recordings becomes **~91 MB** in the blob store. Session logs add ~18 MB (gzipped) for that run. Total blob store: ~118 MB.

5. **All blob volume is in failures — confirmed.** The blob store only ever holds failed-test artifacts (detail extraction is failure-only). For the 1266-test run that is 63 video blobs + 278 gzipped session-log channels = 341 distinct blobs, with content-addressing already collapsing duplicates (342 references → 341 stored blobs; identical content stored once).

6. **The whole store fits next to the data it came from.** Worst run end-state: a 7.2 GB bundle tree produces a **3.1 MB SQLite DB + ~118 MB of blobs** = ~121 MB of `.cachi-data/`. That store survives the bundle being pruned, so history (run list, stats, failure detail, video) outlives the `.xcresult`.

## Disk footprint — steady state

The store is the union of all ingested runs. Driven entirely by **video blobs** (the structured DB is negligible by comparison):

| Tier | per 1266-test run | dominated by |
|------|-------------------|--------------|
| SQLite | ~3 MB | failure step trees (~81 rows/failed test) |
| Blob store | ~118 MB | transcoded screen recordings (~91 MB) |

For deployments that prune old run folders, `--max_disk_size <MB>` bounds the blob store: when the per-run `blob_byte_size` rollup sum exceeds the cap, whole already-pruned sessions are evicted oldest-first (a run whose `.xcresult` is still on disk is never evicted — its blobs self-heal via read-through, and its row must survive the next parse's skip-check). See `BlobStore.enforceDiskLimit` and [`ARCHITECTURE.md`](ARCHITECTURE.md).

## Methodology notes / caveats

- Wall-clock for phase 1 was measured by polling `GET /v1/parse` until it returned `{"status":"ready"}`; phase 2 by polling the SQLite tables (`activity` rows, `attachment.blob_hash`, `session_log.blob_hash`) and the blob directory until counts stabilized. There is some sampling slack (±~1 s) in the reported background-ingest walls.
- Transcode time depends on machine core count (AVFoundation uses all cores per export; the background queue caps concurrency at `cores/2`). The ~153 s background wall for 70 failures is ~2.2 s/failure on this hardware — re-measure on the production host before committing to absolute numbers; the order of magnitude (tens of seconds parse, low single-digit minutes background for a 70-failure run) should hold.
- Coverage extraction/splitting runs async after each bundle and is not included in these walls.
- Numbers are local-SSD/dev-Mac. The structured DB sizes and transcode ratios are properties of the data, not the machine, so they transfer; the wall-clock figures do not.

## Recommendation

The design holds up on the real binary: structured parse is fast (tens of seconds even for the worst run) and is all the user waits on; the heavy work (failure detail + video transcode) is deferred, idempotent, and resumable, costing low single-digit minutes for a 70-failure run. Keep structured data in SQLite (tiny — failure-only detail) and the heavy artifacts in the content-addressed, transcoded, failure-only blob store, bounded by `--max_disk_size` where bundles are pruned.
