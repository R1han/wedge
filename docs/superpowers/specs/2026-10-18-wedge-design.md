# Wedge — design (approved)

Clean-room macOS file-conversion utility with a drag-triggered radial "Action Wheel".
Our own code, assets, and brand; inspired by Tangerine's ideas, nothing copied.

## Approved decisions
- Name: **Wedge** (CLI: `wedge`). Personal GitHub: **R1han** (app repo `R1han/wedge`, tap `R1han/homebrew-wedge`).
- Distribution: **Homebrew tap** (cask -> GitHub Release; ad-hoc signed; `brew upgrade`).
- v1 scope: **focused, extensible** conversion core.
- Interaction: **keep + improve** the drag + modifier radial wheel.
- Developer-feature packs (data/asset/CLI-polish/Shortcuts): **deferred to phase 2.**

## How it's made
- macOS 13+, Swift, universal. UI: SwiftUI + thin AppKit `NSView` drag layer.
- SwiftPM core + CLI; Xcode app via xcodegen (later phase; needs full Xcode).
- Orchestrate proven engines (ffmpeg, pandoc, qpdf, libarchive) as Homebrew deps;
  native frameworks where better (ImageIO/sips, PDFKit/Quartz, Vision, AVFoundation).

## Architecture (3 layers)
- **WedgeCore** (SwiftPM lib): converter registry (one file per format), job engine
  (async queue, cancel, progress, concurrency, timeout, guards), data-driven catalog,
  safe output-naming. No UI; fully unit-tested.
- **wedge** (SwiftPM executable): CLI over WedgeCore; scriptable; CI-testable.
- **Wedge.app** (later): menu-bar LSUIElement SwiftUI app + AppKit drag layer,
  SMAppService login item, floating shelf, the wheel.

## Action Wheel (kept + improved) — later phase
Drag a file past ~4pt -> NSDraggingSession; `ignoreModifierKeysForDraggingSession:` = NO
so modifiers stay live; held modifier combo selects ring (Conversions/Tools/Actions),
each a remappable `ModifierCombination` OptionSet in @AppStorage. Improvements:
discoverability (hint overlay, first-run tutorial, hotkey + menu-bar open), accessibility
(keyboard + VoiceOver), batch + progress/cancel, presets + history, watch folders,
privacy/quality controls, Finder/Services + Share extension, never-overwrite safety.

## v1 catalog (focused, extensible)
Images (HEIC/PNG/JPEG/WebP/TIFF/GIF/BMP/PDF via ImageIO/sips; resize/strip-metadata),
Documents (PDF<->DOCX/MD/HTML/EPUB/txt via pandoc+PDFKit), A/V (ffmpeg), Archives
(zip/tar/7z via libarchive). Tools: compress/crop/resize/rotate/trim/split/merge/OCR/QR.
Actions: AirDrop/Float/Copy/Move/Copy Path/Reveal/Terminal.

## Non-goals / anti-goals
Not the full 275-matrix on day one; not iOS; no cloud/account/telemetry; no paywall;
not a general PDF editor. Failure = silent data loss, overwriting originals, or needing
the network for a local conversion.

## Phases (subagent-driven waves; each build -> review -> verify)
1. **Core + CLI** (this plan): registry, job engine, image + archive converters, tests.
2. Docs + media converters (pandoc/ffmpeg/PDFKit/qpdf).
3. App shell (menu-bar, SMAppService, settings, shelf).
4. Action Wheel (drag layer + radial UI, rings, remap, improvements).
5. Integrations (Finder/Services + Share ext, watch folders, presets, history) + dev-feature packs.
6. Packaging (xcodegen, GitHub Actions, Homebrew tap).
