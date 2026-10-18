# Wedge Phase 2 (Document + Media + PDF converters) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Add document, audio/video, and PDF conversions to WedgeCore + the `wedge` CLI, built on the existing registry/service, by orchestrating pandoc and ffmpeg and using native PDFKit.

**Architecture:** New `Converter`s plug into the existing `ConverterRegistry`. External-tool converters (pandoc, ffmpeg) locate their binary via a shared `ToolLocator` and run it through `ProcessRunner`; a missing tool yields a clear `WedgeError.toolNotInstalled`. PDF uses native PDFKit (no external tool). The CLI gains a `doctor` command and prints multi-file outputs.

**Tech Stack:** Swift 6 / SwiftPM, PDFKit/Quartz + ImageIO (native), pandoc + ffmpeg (external, via ProcessRunner), Swift Testing via ./scripts/test.sh.

**Spec:** docs/superpowers/specs/2026-10-18-wedge-design.md

## Global Constraints
- macOS 13+; Swift 6 language mode; builds with Command Line Tools.
- Clean-room; product "Wedge"; CLI "wedge"; offline (no network in any converter).
- Never overwrite silently (reuse OutputNamer + temp-then-move, as ImageConverter does).
- External tools invoked only via ProcessRunner with an argument array; located via ToolLocator (PATH + /opt/homebrew/bin + /usr/local/bin). A missing tool -> WedgeError.toolNotInstalled(tool:installHint:), never a crash or silent skip at runtime.
- No AI-assistant/vendor names in code or commit messages; clean-room name check stays empty.
- Tests that need an external tool are gated with Swift Testing `.enabled(if: ToolLocator.shared.path(for:) != nil)` so they skip cleanly when it is absent; PDFKit tests always run.

## Review Focus
- **Missing external tool at runtime** -> `toolNotInstalled` with an actionable hint (`brew install pandoc`), nonzero CLI exit; pinned in Task 1 + Task 5.
- **Multi-file output** (PDF -> one PNG per page) -> `ConversionResult.outputs` lists every file; CLI prints them all; pinned in Task 4 + Task 5.
- **Filenames with spaces/unicode / dash-prefixed** reach pandoc/ffmpeg as array args (no shell, `--` where needed); pinned in Task 2 + Task 3.
- **Overwrite safety** for tool outputs (ffmpeg's own `-y`) -> write to temp then move via OutputNamer; original never clobbered; pinned in Task 2/3.
- **Empty/garbled source** (0-page PDF, empty md, corrupt media) -> clear `invalidInput`/`toolFailed`, not a crash; pinned per converter.

---

## Task 1: ToolLocator + toolNotInstalled + catalog expansion

**Files:**
- Create: `Sources/WedgeCore/Process/ToolLocator.swift`
- Modify: `Sources/WedgeCore/Models/WedgeError.swift` (add case), `Sources/WedgeCore/Models/FileFormat.swift` (add formats)
- Test: `Tests/WedgeCoreTests/ToolLocatorTests.swift`, `Tests/WedgeCoreTests/FileFormatCatalogTests.swift`

**Interfaces:**
- Produces:
  - `struct ToolLocator: Sendable { static let shared: ToolLocator; func path(for tool: String) -> URL? }` — searches PATH then /opt/homebrew/bin, /usr/local/bin; returns the executable URL or nil.
  - `WedgeError.toolNotInstalled(tool: String, installHint: String)` added to the existing enum (keep Equatable).
  - `FileFormat.known` gains: documents `md, html, docx, epub, txt, rtf` (category `.document`); audio `mp3, m4a, wav, flac, aac` (`.audio`); video `mp4, mov, mkv, webm` (`.video`). (`pdf` already present.)

- [ ] Step 1: Write failing tests — ToolLocator finds `/bin/ls`-style known tool by absolute presence (use a tool sure to exist, e.g. "swift" or "tar") and returns nil for a nonsense name; catalog test asserts `format(forExtension:)` resolves `md`,`docx`,`mp4`,`mp3` to the right categories.
- [ ] Step 2: `./scripts/test.sh --filter ToolLocatorTests` and `--filter FileFormatCatalogTests` -> FAIL.
- [ ] Step 3: Implement ToolLocator, the error case, and the catalog additions.
- [ ] Step 4: Run both filters -> PASS; `swift build` clean.
- [ ] Step 5: Commit `feat: add ToolLocator, toolNotInstalled error, and document/media formats`.

## Task 2: PandocConverter (document <-> document)

**Files:** Create `Sources/WedgeCore/Converters/PandocConverter.swift`; Test `Tests/WedgeCoreTests/PandocConverterTests.swift`

**Interfaces:**
- `struct PandocConverter: Converter` — id "doc.pandoc"; init takes an injectable `ToolLocator` and `ProcessRunner` (defaults) for testability; `supports` among {md, html, docx, epub, txt, rtf} both directions (same-format excluded). `convert` maps `FileFormat.id` -> pandoc format name (md->markdown, txt->plain, etc.), runs `pandoc <in> -f <from> -t <to> -o <tmp>` via ProcessRunner, then moves tmp -> OutputNamer destination. Missing pandoc -> `toolNotInstalled(tool:"pandoc", installHint:"brew install pandoc")`.

- [ ] Step 1: Failing tests (gated on pandoc present): md -> html produces HTML containing a converted heading; md -> docx produces a nonzero .docx; missing-input -> `inputNotFound`; a test that when pandoc is absent `convert` throws `toolNotInstalled` (inject a ToolLocator stub returning nil).
- [ ] Step 2: run filter -> FAIL.
- [ ] Step 3: Implement PandocConverter.
- [ ] Step 4: filter -> PASS; build clean.
- [ ] Step 5: Commit `feat: add pandoc-backed document converter`.

## Task 3: MediaConverter (ffmpeg audio/video)

**Files:** Create `Sources/WedgeCore/Converters/MediaConverter.swift`; Test `Tests/WedgeCoreTests/MediaConverterTests.swift`

**Interfaces:**
- `struct MediaConverter: Converter` — id "media.ffmpeg"; injectable locator/runner; `supports` across audio {mp3,m4a,wav,flac,aac} and video {mp4,mov,mkv,webm} (audio->audio, video->video, and video->audio extract; not audio->video). `convert` runs `ffmpeg -nostdin -i <in> <tmp.ext>` (array args, generous timeout) then moves tmp -> OutputNamer destination. Missing ffmpeg -> `toolNotInstalled(tool:"ffmpeg", installHint:"brew install ffmpeg")`.

- [ ] Step 1: Failing tests (gated on ffmpeg present): generate a 0.1s silent wav via `ffmpeg -f lavfi -i anullsrc` in a test helper, convert wav -> mp3 (output exists, nonzero, probes as audio); a video->audio extract using a tiny generated test clip; missing-input -> `inputNotFound`; absent-ffmpeg (stub locator) -> `toolNotInstalled`.
- [ ] Step 2: run filter -> FAIL.
- [ ] Step 3: Implement MediaConverter.
- [ ] Step 4: filter -> PASS; build clean.
- [ ] Step 5: Commit `feat: add ffmpeg-backed media converter`.

## Task 4: PDFConverter (native PDFKit)

**Files:** Create `Sources/WedgeCore/Converters/PDFConverter.swift`; Test `Tests/WedgeCoreTests/PDFConverterTests.swift`

**Interfaces:**
- `struct PDFConverter: Converter` — id "pdf.pdfkit"; no external tool. `supports`: pdf -> txt, pdf -> png (one image per page -> multiple outputs), and image {png,jpeg,tiff,heic} -> pdf (each input image becomes a single-page PDF; a future task may add multi-image merge). `convert` uses PDFKit `PDFDocument` (text extraction; page rendering to PNG via `page.thumbnail`/CGContext) and builds PDFs from images via `PDFDocument`/`PDFPage(image:)`. Multi-page pdf->png returns all page files in `ConversionResult.outputs` (named `<stem>-1.png`, `<stem>-2.png`, ...). Non-destructive writes.

- [ ] Step 1: Failing tests: build a 2-page PDF in a helper (PDFKit from two images), convert pdf->png yields 2 files; pdf->txt yields a file containing known text (make a PDF with text via PDFKit/CoreText); png->pdf yields a 1-page PDF; missing-input -> `inputNotFound`; empty/0-page pdf -> `invalidInput`.
- [ ] Step 2: run filter -> FAIL.
- [ ] Step 3: Implement PDFConverter.
- [ ] Step 4: filter -> PASS; build clean.
- [ ] Step 5: Commit `feat: add PDFKit-backed PDF converter`.

## Task 5: Registry wiring + `wedge doctor` + multi-output CLI

**Files:** Modify `Sources/WedgeCore/Wedge.swift` (register new converters), `Sources/WedgeCLI/*` (doctor command + multi-output printing); Create `Sources/WedgeCLI/DoctorCommand.swift`; Tests `Tests/WedgeCoreTests/DefaultRegistryPhase2Tests.swift`, `Tests/WedgeCLITests/DoctorAndMultiOutputTests.swift`

**Interfaces:**
- `Wedge.defaultRegistry()` also registers PandocConverter, MediaConverter, PDFConverter.
- CLI: `wedge doctor` prints each external tool (pandoc, ffmpeg) with found/missing + install hint; exit 0 always. `wedge convert` prints every file in `ConversionResult.outputs` (not just the first). `wedge list` now includes the new pairs.
- Consumes Tasks 1-4.

- [ ] Step 1: Failing tests: `defaultRegistry().converter(from: md, to: html)` and `(pdf, png)` resolve; `wedge list` output includes `md -> html` and `pdf -> png`; `wedge doctor` output names pandoc and ffmpeg; a pdf->png CLI run prints 2 output paths.
- [ ] Step 2: run filters -> FAIL.
- [ ] Step 3: Implement wiring + DoctorCommand + multi-output printing.
- [ ] Step 4: filters -> PASS; full `./scripts/test.sh` green; build clean.
- [ ] Step 5: Commit `feat: register phase-2 converters, add wedge doctor and multi-output`.

## Task 6: Packaging — runtime deps + CI + docs

**Files:** Modify `.github/workflows/release.yml` (formula template), `.github/workflows/ci.yml` (install pandoc+ffmpeg before tests), Create/modify `README.md`

**Interfaces:**
- release.yml formula template gains `depends_on "pandoc"` and `depends_on "ffmpeg"` so `brew install wedge` pulls them.
- ci.yml installs pandoc + ffmpeg before `swift test` so gated tests actually run on CI.
- README documents the converters, the `doctor` command, and the external-tool requirements.

- [ ] Step 1: Update release.yml formula heredoc to add the two `depends_on` lines (keep `depends_on macos: :ventura`). 
- [ ] Step 2: Update ci.yml to `brew install pandoc ffmpeg` before tests.
- [ ] Step 3: Write README (install, usage, converters, doctor, deps). `git grep` clean-room check empty.
- [ ] Step 4: `swift build` + full `./scripts/test.sh` still green locally.
- [ ] Step 5: Commit `chore: declare runtime deps in formula and CI, add README`.

---

## Notes for the executor
- New branch `phase-2-doc-media` cut from `phase-1-core` HEAD (Phase 1 PR not yet merged; Phase 2 stacks on it). Do not push; stop for Rihan's go-ahead.
- Run `./scripts/test.sh` green before each commit; `git grep -i` clean-room check empty.
- pandoc/ffmpeg are being installed locally; if a gated test's tool is missing it must SKIP (via `.enabled(if:)`), never fail.
