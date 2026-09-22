# Repository instructions

## Swift formatting and linting

The pull-request lint job runs SwiftFormat against the entire repository, not
only the files changed by the current commit. Before committing any Swift
change:

1. From the repository root, run `swiftformat .`. This applies the rules from
   `.swiftformat` and the Swift language version from `.swift-version`.
2. Review `git diff --check` and `git diff` to confirm that the formatter made
   only mechanical formatting changes and did not disturb unrelated work.
3. Run the exact CI gate:

   ```sh
   swiftformat --lint . --reporter github-actions-log
   ```

   It must exit successfully and report that zero files require formatting.
   If it reports warnings, run the formatter again instead of fixing only the
   annotated lines: a newly enabled rule can affect pre-existing files across
   the repository.
4. When Swift source changed, also run `swift build -c release` and
   `swift test` before pushing.

Do not override the repository's SwiftFormat options with command-line rules.
