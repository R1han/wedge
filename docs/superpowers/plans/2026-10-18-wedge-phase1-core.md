# Wedge Phase 1 (Core + CLI) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A headless, tested Swift package that converts image and archive files through a pluggable converter registry and job engine, usable from a `wedge` CLI.

**Architecture:** `WedgeCore` SwiftPM library exposes a `Converter` protocol, a `ConverterRegistry`, and a `ConversionService` (single + batch, with cancellation/progress/concurrency). Converters either use native frameworks (ImageIO) or run vetted system tools through a `ProcessRunner` (ditto/tar). A `wedge` executable wraps the core with swift-argument-parser.

**Tech Stack:** Swift 6.3 toolchain, SwiftPM (no Xcode needed), ImageIO/CoreGraphics, system `ditto`/`tar`, swift-argument-parser.

**Spec:** `docs/superpowers/specs/2026-10-18-wedge-design.md`

## Global Constraints
- macOS 13+; SwiftPM `platforms: [.macOS(.v13)]`; builds with Command Line Tools (no Xcode).
- Clean-room: no Tangerine code, assets, or the name "Tangerine" anywhere.
- Product name **Wedge**; CLI command **wedge**.
- Offline only: no network calls in any converter.
- **Never overwrite an existing file silently** — collision policy produces a new name unless `--force`.
- No AI attribution in any commit message or repo file (no "Claude"/"Anthropic"); `git grep -i -E "claude|anthropic"` must be empty before any commit.
- Only dependency: `apple/swift-argument-parser` (pinned, in the `wedge`/`WedgeCLI` targets only).
- External tools invoked only via `ProcessRunner` with an argument array (never a shell string).

## Review Focus
- **Missing/unreadable input file** -> `ConversionService`/CLI returns `WedgeError.inputNotFound`, nonzero exit; pinned in Task 7 + Task 8 tests.
- **Unsupported (from,to) pair** -> `registry.converter(from:to:)` returns nil -> `WedgeError.unsupportedConversion`; no silent no-op; pinned in Task 4 + Task 8.
- **Output path already exists** -> `OutputNamer` yields a `-1`-suffixed path, original untouched; `--force` overwrites; pinned in Task 3.
- **Oversized / too-many-entry archive (zip-bomb)** -> `ArchiveConverter` enforces entry-count and total-byte guards, throws `WedgeError.resourceLimitExceeded`; pinned in Task 6.
- **Cancelled batch** -> pending jobs never start and in-flight is cancelled; `ConversionService` checks `Task.isCancelled`; pinned in Task 7.

---

## Task 1: Package scaffold + core models

**Files:**
- Create: `Package.swift`, `.gitignore`, `Sources/WedgeCore/Models/FileFormat.swift`, `Sources/WedgeCore/Models/Conversion.swift`, `Sources/WedgeCore/Models/WedgeError.swift`
- Test: `Tests/WedgeCoreTests/FileFormatTests.swift`

**Interfaces:**
- Produces:
  - `struct FileFormat: Hashable, Sendable { let id: String; let extensions: [String]; let category: FormatCategory }` with `enum FormatCategory: String, Sendable { case image, archive, document, audio, video, data, other }`, static table `FileFormat.known: [FileFormat]`, and `static func format(forExtension: String) -> FileFormat?` (case-insensitive).
  - `struct ConversionOptions: Sendable { var quality: Double?; var maxDimension: Int?; var stripMetadata: Bool; var force: Bool; var extra: [String:String]; init(...) }` (all defaulted).
  - `struct ConversionRequest: Sendable { let input: URL; let target: FileFormat; let outputDirectory: URL?; let options: ConversionOptions }`.
  - `struct ConversionResult: Sendable { let outputs: [URL]; let bytesWritten: Int }`.
  - `enum WedgeError: Error, Equatable { case inputNotFound(URL); case unsupportedConversion(from: String, to: String); case outputExists(URL); case resourceLimitExceeded(String); case toolFailed(tool: String, code: Int32, message: String); case cancelled; case invalidInput(String) }`.

- [ ] **Step 1: Write the failing test** — `FileFormatTests`: `test_formatForExtension_isCaseInsensitive` (`FileFormat.format(forExtension: "PNG")?.id == "png"`), `test_unknownExtension_returnsNil`, `test_known_includesHeicAndZip` (ids contain `heic`, `zip`).
- [ ] **Step 2: Run test to verify it fails** — `swift test --filter FileFormatTests` -> FAIL (no such type).
- [ ] **Step 3: Implement** `Package.swift` (library `WedgeCore`, test target; `platforms: [.macOS(.v13)]`), the three model files, and the `FileFormat.known` table (png, jpeg, heic, tiff, gif, bmp, webp, pdf, zip, tar). `.gitignore` for `.build/`, `.DS_Store`.
- [ ] **Step 4: Run test to verify it passes** — `swift test --filter FileFormatTests` -> PASS.
- [ ] **Step 5: Commit** — `feat: scaffold WedgeCore package and core models`.

## Task 2: ProcessRunner

**Files:**
- Create: `Sources/WedgeCore/Process/ProcessRunner.swift`
- Test: `Tests/WedgeCoreTests/ProcessRunnerTests.swift`

**Interfaces:**
- Produces: `struct ProcessRunner: Sendable { struct Output { let stdout: Data; let stderr: Data; let code: Int32 }; func run(_ executable: URL, _ args: [String], timeout: Duration = .seconds(120)) async throws -> Output }`. On timeout throws `WedgeError.toolFailed(tool:code:message:)` with code `-1`. Uses `Foundation.Process` with argument array (no shell).

**Consumed:** `WedgeError` (Task 1).

- [ ] **Step 1: Write the failing test** — `test_run_capturesStdoutAndZeroExit` (run `/bin/echo` with `["hi"]`, stdout contains `hi`, code 0), `test_run_nonzeroExit` (run `/bin/sh` with `["-c","exit 3"]`, code == 3), `test_run_timeoutThrows` (run `/bin/sleep` `["5"]` with `timeout: .seconds(1)` -> throws `WedgeError.toolFailed`).
- [ ] **Step 2: Run to verify it fails** — `swift test --filter ProcessRunnerTests` -> FAIL.
- [ ] **Step 3: Implement** `ProcessRunner.run` using `Process`, pipes drained concurrently, a timeout that terminates the process and throws. Approach note: read stdout/stderr on background reads to avoid pipe deadlock.
- [ ] **Step 4: Run to verify it passes** — PASS.
- [ ] **Step 5: Commit** — `feat: add ProcessRunner for safe external tool execution`.

## Task 3: OutputNamer (collision policy)

**Files:**
- Create: `Sources/WedgeCore/Output/OutputNamer.swift`
- Test: `Tests/WedgeCoreTests/OutputNamerTests.swift`

**Interfaces:**
- Produces: `struct OutputNamer: Sendable { func destination(forInput: URL, target: FileFormat, in directory: URL?, force: Bool) -> URL }`. Base name = input stem + target primary extension, in `directory ?? input.deletingLastPathComponent()`. If path exists and `!force`, append `-1`, `-2`, ... until free. If `force`, return the base path as-is.

**Consumed:** `FileFormat` (Task 1).

- [ ] **Step 1: Write the failing test** — in a temp dir: `test_noCollision_usesBaseName`, `test_collision_appendsSuffix` (create `a.png`, target png yields `a-1.png`), `test_force_returnsBasePathEvenIfExists`, `test_respectsOutputDirectory`.
- [ ] **Step 2: Run to verify it fails** -> FAIL.
- [ ] **Step 3: Implement** `OutputNamer.destination` using `FileManager.fileExists`.
- [ ] **Step 4: Run to verify it passes** -> PASS.
- [ ] **Step 5: Commit** — `feat: add OutputNamer with non-destructive collision policy`.

## Task 4: Converter protocol + ConverterRegistry

**Files:**
- Create: `Sources/WedgeCore/Registry/Converter.swift`, `Sources/WedgeCore/Registry/ConverterRegistry.swift`
- Test: `Tests/WedgeCoreTests/ConverterRegistryTests.swift`

**Interfaces:**
- Produces:
  - `protocol Converter: Sendable { var id: String { get }; func supports(from: FileFormat, to: FileFormat) -> Bool; func convert(_ request: ConversionRequest, progress: @Sendable (Double) -> Void) async throws -> ConversionResult }`.
  - `final class ConverterRegistry: @unchecked Sendable { func register(_ c: Converter); func converter(from: FileFormat, to: FileFormat) -> Converter?; func pairs() -> [(from: FileFormat, to: FileFormat)] }` — `pairs()` enumerates supported (from,to) across registered converters and `FileFormat.known`, deduplicated and sorted by `from.id,to.id`.

**Consumed:** Task 1 models.

- [ ] **Step 1: Write the failing test** — a `StubConverter` supporting png->jpeg. `test_lookupFindsRegisteredConverter`, `test_unsupportedPairReturnsNil`, `test_pairsListsSupportedAndSorted`.
- [ ] **Step 2: Run to verify it fails** -> FAIL.
- [ ] **Step 3: Implement** protocol + registry (array of converters; first match wins).
- [ ] **Step 4: Run to verify it passes** -> PASS.
- [ ] **Step 5: Commit** — `feat: add Converter protocol and ConverterRegistry`.

## Task 5: ImageConverter (ImageIO)

**Files:**
- Create: `Sources/WedgeCore/Converters/ImageConverter.swift`
- Test: `Tests/WedgeCoreTests/ImageConverterTests.swift`

**Interfaces:**
- Produces: `struct ImageConverter: Converter` — `id = "image.imageio"`; supports among {png, jpeg, heic, tiff, gif, bmp} as both source and dest (category `.image`); honors `options.quality` (jpeg/heic), `options.maxDimension` (proportional resize), `options.stripMetadata`. Uses `CGImageSource`/`CGImageDestination`; writes via `OutputNamer`.

**Consumed:** Task 1, Task 3 (`OutputNamer`), Task 4 (`Converter`).

- [ ] **Step 1: Write the failing test** — a test helper generates a 64x48 PNG in a temp dir via CoreGraphics. `test_pngToJpeg_producesReadableJpeg` (output exists; `CGImageSource` type `public.jpeg`; dims 64x48). `test_maxDimension_resizesProportionally` (maxDimension 32 -> 32x24). `test_stripMetadata_removesExif` (inject EXIF, convert with strip, assert no Exif dict in output). `test_missingInput_throwsInputNotFound`.
- [ ] **Step 2: Run to verify it fails** -> FAIL.
- [ ] **Step 3: Implement** `ImageConverter.convert` (load source, optional resize via `CGContext`, write with destination properties; map UTIs from `FileFormat.id`). Throw `WedgeError.inputNotFound` when source missing, `invalidInput` when undecodable.
- [ ] **Step 4: Run to verify it passes** -> PASS.
- [ ] **Step 5: Commit** — `feat: add ImageIO-backed image converter`.

## Task 6: ArchiveConverter (zip/tar via system tools)

**Files:**
- Create: `Sources/WedgeCore/Converters/ArchiveConverter.swift`
- Test: `Tests/WedgeCoreTests/ArchiveConverterTests.swift`

**Interfaces:**
- Produces: `struct ArchiveConverter: Converter` — `id = "archive.systool"`; supports folder/file -> `zip`/`tar` (create) and `zip`/`tar` -> extracted directory. Create zip via `ditto -c -k --sequesterRsrc --keepParent`, tar via `/usr/bin/tar`. Extract via `ditto -x -k` (zip) / `tar -xf` (tar). Guards: reject if listed entry count > `maxEntries` (default 100_000) or total uncompressed bytes > `maxBytes` (default 2 GiB), throwing `WedgeError.resourceLimitExceeded`. Uses `ProcessRunner`. Make `maxEntries`/`maxBytes` injectable for tests.

**Consumed:** Task 1, Task 2 (`ProcessRunner`), Task 3, Task 4.

- [ ] **Step 1: Write the failing test** — `test_zipRoundTrip` (dir with 2 files -> zip -> extract -> contents equal), `test_tarRoundTrip`, `test_extract_exceedsEntryGuard_throws` (`maxEntries: 1` on a 2-entry archive -> `resourceLimitExceeded`), `test_missingInput_throwsInputNotFound`.
- [ ] **Step 2: Run to verify it fails** -> FAIL.
- [ ] **Step 3: Implement** create/extract branches selecting by `(from.category, to.id)`; pre-scan listing (`tar -tf` / `unzip -l` via ProcessRunner) to enforce guards before extracting.
- [ ] **Step 4: Run to verify it passes** -> PASS.
- [ ] **Step 5: Commit** — `feat: add archive converter with zip/tar and resource guards`.

## Task 7: ConversionService (single + batch, cancel, progress, concurrency)

**Files:**
- Create: `Sources/WedgeCore/Engine/ConversionService.swift`, `Sources/WedgeCore/Wedge.swift` (default registry assembly)
- Test: `Tests/WedgeCoreTests/ConversionServiceTests.swift`

**Interfaces:**
- Produces:
  - `struct ConversionProgress: Sendable { let request: ConversionRequest; let fraction: Double }`.
  - `final class ConversionService: Sendable { init(registry: ConverterRegistry); func convert(_ r: ConversionRequest, progress: @Sendable (Double)->Void = {_ in}) async throws -> ConversionResult; func convertBatch(_ rs: [ConversionRequest], maxConcurrent: Int = 4, progress: @Sendable (ConversionProgress)->Void = {_ in}) async -> [Result<ConversionResult, Error>] }`. `convert` validates input exists (`WedgeError.inputNotFound`) and a converter exists (`WedgeError.unsupportedConversion`). `convertBatch` runs with a concurrency cap via a task group, honors `Task.isCancelled` (pending items return `.failure(WedgeError.cancelled)`; no new work starts).
  - `enum Wedge { static func defaultRegistry() -> ConverterRegistry }` registering ImageConverter + ArchiveConverter.

**Consumed:** Tasks 1,4,5,6.

- [ ] **Step 1: Write the failing test** — `test_convert_missingInput_throws`, `test_convert_unsupportedPair_throws`, `test_convert_png2jpeg_succeeds` (via defaultRegistry), `test_batch_respectsMaxConcurrent` (stub converter records peak concurrency <= cap), `test_batch_cancellation_marksPendingCancelled` (cancel surrounding task; assert >=1 `.failure(WedgeError.cancelled)` and not all succeeded).
- [ ] **Step 2: Run to verify it fails** -> FAIL.
- [ ] **Step 3: Implement** service + `defaultRegistry()`; batch via `withTaskGroup` + a counting actor for the cap. Progress forwarded from converter callbacks.
- [ ] **Step 4: Run to verify it passes** -> PASS.
- [ ] **Step 5: Commit** — `feat: add ConversionService with batch, cancellation and concurrency`.

## Task 8: `wedge` CLI

**Files:**
- Modify: `Package.swift` (add `swift-argument-parser` dep; add `WedgeCLI` library + `wedge` executable targets depending on WedgeCore)
- Create: `Sources/WedgeCLI/RootCommand.swift`, `Sources/WedgeCLI/ConvertCommand.swift`, `Sources/WedgeCLI/ListCommand.swift`, `Sources/WedgeCLI/Run.swift`, `Sources/wedge/main.swift`
- Test: `Tests/WedgeCLITests/CLIIntegrationTests.swift`

**Interfaces:**
- Produces CLI: `wedge convert <input> --to <formatId> [--out <dir>] [--quality <0..1>] [--max-dim <int>] [--strip-metadata] [--force]` (exit 0 on success, nonzero on `WedgeError` with a clear stderr message); `wedge list` (prints supported `from -> to` pairs from `defaultRegistry().pairs()`). Command bodies live in `WedgeCLI` with `func run(_ args: [String]) async -> Int32` so tests call it without spawning; `Sources/wedge/main.swift` is a thin wrapper.

**Consumed:** Task 7, Task 1.

- [ ] **Step 1: Write the failing test** — `test_convert_png2jpeg_createsOutput` (fixture png -> jpeg via `WedgeCLI.run([...])`, returns 0, file exists), `test_convert_missingInput_returnsNonzeroWithMessage`, `test_list_includesPngToJpeg`.
- [ ] **Step 2: Run to verify it fails** -> FAIL.
- [ ] **Step 3: Implement** commands with swift-argument-parser; map `WedgeError` to stderr + exit codes.
- [ ] **Step 4: Run to verify it passes** -> PASS; then full suite `swift test`.
- [ ] **Step 5: Commit** — `feat: add wedge CLI (convert, list)`.

---

## Notes for the executor
- New repo. Task 1's commit is the scaffold on `main`; cut branch `phase-1-core` after it and do Tasks 2-8 there. Do not push; stop for Rihan's go-ahead before any push/PR.
- Run `swift test` green before each commit. Before committing, `git grep -i -E "claude|anthropic"` must be empty.
- macOS frameworks (ImageIO/CoreGraphics) link automatically on the macOS platform.
