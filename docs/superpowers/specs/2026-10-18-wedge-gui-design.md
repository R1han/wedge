# Wedge GUI — design (Phases 3-4)

Clean-room macOS GUI on top of the existing `WedgeCore` library + `wedge` CLI. Our own code/assets/brand.

## Approved decisions
- Build env: **full Xcode installed locally** (CLT-only can't build a `.app`); release builds already use Xcode CI runners.
- Order: **Phase 3 = menu-bar app shell first**, then **Phase 4 = the radial Action Wheel**.
- The novel drag→modifier→radial-menu interaction gets a **throwaway spike first**, then Phase 4 is planned from what it teaches.

## Constraints
- macOS 13+, Swift 6. SwiftUI for views; an AppKit `NSView`/`NSWindow` layer for the drag source + overlay (SwiftUI can't read modifier keys mid-drag — confirmed by RE).
- Menu-bar app: `LSUIElement`/`MenuBarExtra`, no Dock icon by default.
- `WedgeCore` stays UI-agnostic; the app depends on it as a local SwiftPM package. No conversion logic in the UI layer.
- Project generated with **xcodegen** (`project.yml` in git; `brew install xcodegen`) so the repo carries no hand-edited `.xcodeproj`; CI runs `xcodegen generate` then `xcodebuild`.
- Distribution: the app ships as a Homebrew **cask** (separate from the CLI formula), ad-hoc signed initially (Developer ID/notarization later). Cask wiring is a packaging task after the app is feature-complete (end of Phase 4), not Phase 3.
- Testing: all non-visual logic lives in testable `@MainActor` view-models / service wrappers (Swift Testing). Views are verified by running the app + screenshots; keep UI automated tests minimal.

## Architecture
- `WedgeApp` (SwiftUI `App`, `MenuBarExtra`) — lifecycle, menu-bar menu, opens windows.
- `ConversionModel` (`@MainActor @Observable`) — wraps `ConversionService`; holds the item queue, per-item progress, results; actions addFiles/convert/cancel. The testable heart of the UI.
- Floating file **shelf** window — drag-drop import, file chips, target-format picker (from `registry.pairs()`), options, Convert, progress, reveal outputs.
- **Settings** window — default format, output policy, Launch-at-Login (via a mockable `LoginItemService` over `SMAppService`), persisted with `@AppStorage`.
- `LoginItemService` — protocol + real (`SMAppService.mainApp`) + fake for tests.

## Phase 3 scope (menu-bar app shell) — see the Phase 3 plan
App scaffold (xcodegen) · ConversionModel · floating shelf with drag-drop + convert + progress · Settings + Launch-at-Login · menu-bar menu/lifecycle · CI app-build check.

## Phase 4 overview (Action Wheel) — planned after the spike
A transparent overlay window renders a radial menu while a file is dragged from the shelf. The held modifier combination selects the ring — Conversions (⇧), Tools (⌘), Actions (⌃) — each a remappable `ModifierCombination` in `@AppStorage`. Release over a segment runs it. Plus the RE-identified improvements: drag-time hint overlay, first-run tutorial, a hotkey/menu-bar way to open it, keyboard + VoiceOver access, batch, presets, watch folders. (Advanced "tools" ring — compress/crop/trim/split/merge — reuses WedgeCore + qpdf; some are new WedgeCore ops added alongside.)

## Wheel spike (throwaway, built once Xcode is in)
Goal: prove feasibility + feel of the three hard parts before committing the Phase 4 plan.
- One draggable chip in a window; start an `NSDraggingSession`; return `false` from `ignoreModifierKeysForDraggingSession:`.
- A borderless, transparent, click-through overlay `NSWindow` that renders a radial menu and follows the cursor during the drag.
- A local/global event monitor reading `NSEvent.modifierFlags` live to switch the active ring label (⇧/⌘/⌃).
- On drop, hit-test the cursor position to the nearest segment and log the choice.
Deliverable: a short note on what worked, timing/jank, permission prompts (if any), and the chosen rendering approach — feeds the Phase 4 plan. The spike is discarded; keeping any of it comes back through brainstorming.

## Non-goals (GUI phases)
Not iOS; no cloud/account/telemetry; no paywall. Not notarized on day one (ad-hoc signed; Gatekeeper right-click-open until Developer ID). The wheel does not require Accessibility permission (the drag originates from our own shelf, so we own the session).
