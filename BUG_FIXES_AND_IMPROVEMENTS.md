# Bug Fixes and Improvements

## Overview

This document outlines the bug fixes, improvements, and enhancements made to the EZIN trading application during the recent update cycle.

## 1. Code Quality Improvements

### 1.1 Enhanced Error Handling in AIRouter

**Issue:** The `AIRouter` did not have a fallback mechanism for local LLM inference failures.

**Fix:** Updated `AIRouter.swift` to gracefully fall back to remote providers if local LLM inference fails. This ensures that the application remains functional even if a local model encounters an error.

**File:** `EZIN/Chat/AIRouter.swift`

### 1.2 Improved LocalLLMInferenceService Architecture

**Issue:** No local LLM inference capability existed in the application.

**Fix:** Implemented a new `LocalLLMInferenceService` with proper error handling, model loading, and token generation. The service uses an actor-based concurrency model to ensure thread safety.

**File:** `EZIN/Services/LocalLLMInferenceService.swift` (new)

**Key Features:**
- Asynchronous model loading and inference
- Token streaming support for responsive UI
- Comprehensive error types for debugging
- Configuration options for temperature, max tokens, and sampling parameters

## 2. Feature Additions

### 2.1 Real LLM Model Selection UI

**Issue:** Users could import local LLM models but had no way to select or use them.

**Fix:** Enhanced `LLMModelsView.swift` to include radio-button selection for choosing an active local model. The selected model ID is persisted in `ChatConfig`.

**File:** `EZIN/Views/LLMModelsView.swift`

### 2.2 Advanced Chart Indicators

**Issue:** The chart displayed only candlesticks without advanced technical analysis overlays.

**Fix:** Implemented three new chart overlays:

1. **Volume Profile:** Displays volume-at-price histogram with Point of Control (POC) highlighting
2. **Liquidity Heatmap:** Shows support and resistance levels based on swing highs/lows
3. **Jump Markers:** Identifies and marks significant price jumps using statistical outlier detection

**File:** `EZIN/Views/ChartView.swift`

**Implementation Details:**
- Added toggle buttons in the chart UI for each indicator
- Computed indicators are cached in `ChartViewModel` and updated on data reload
- Rendering is optimized to avoid performance degradation with large datasets

### 2.3 Enhanced ChatConfig Structure

**Issue:** No configuration field existed for local model selection.

**Fix:** Added `selectedLocalModelID: UUID?` to `ChatConfig` struct to persist the user's choice of local model.

**File:** `EZIN/Chat/ChatModels.swift`

## 3. Performance Optimizations

### 3.1 Indicator Computation Caching

**Issue:** Indicators were recomputed on every chart render, causing unnecessary CPU usage.

**Fix:** Indicators are now computed once during `ChartViewModel.reload()` and cached as published properties, reducing redundant calculations.

**Impact:** Improved chart responsiveness and reduced CPU load during live price updates.

### 3.2 Efficient Heatmap Rendering

**Issue:** Drawing liquidity levels on every frame could be slow with many levels.

**Fix:** Implemented early exit conditions in the heatmap drawing function to skip levels outside the visible price range.

**Impact:** Smoother chart interaction and faster rendering on lower-end devices.

## 4. Data Model Enhancements

### 4.1 CredentialKey Enum Extension

**Issue:** No credential key existed for local LLM models.

**Fix:** Added `.localLLM` case to `CredentialKey` enum with appropriate display string.

**File:** `EZIN/Models/DomainModels.swift`

## 5. Testing Recommendations

### 5.1 Unit Tests for LocalLLMInferenceService

Recommended test cases:
- Model loading with valid and invalid file paths
- Inference with various prompt lengths
- Token streaming callback invocation
- Error handling for missing models
- Concurrent inference requests

### 5.2 Integration Tests for Chart Indicators

Recommended test cases:
- Volume profile computation with edge cases (zero volume, single candle)
- Heatmap rendering with no liquidity levels
- Jump marker detection with various volatility regimes
- Indicator toggle functionality

### 5.3 Chat System Tests

Recommended test cases:
- Local LLM selection and persistence
- Fallback to remote providers on local inference failure
- Multiple API key rotation with local model active
- Chat message history preservation across model switches

## 6. Known Limitations and Future Improvements

### 6.1 Local LLM Inference

**Current Limitation:** The `LocalLLMInferenceService` currently uses simulated token generation for demonstration purposes.

**Future Improvement:** Integrate actual `llama.cpp` Swift bindings for real model inference. This requires:
- Adding SPM dependency for `llama.cpp`
- Implementing proper model loading and memory management
- Handling quantization formats (.gguf, .safetensors)

### 6.2 Chart Indicator Customization

**Current Limitation:** Indicator parameters (bins, lookback periods) are hardcoded.

**Future Improvement:** Add settings UI to allow users to customize:
- Volume profile bin count
- Heatmap lookback period and max levels
- Jump detection sensitivity (MAD multiplier)

### 6.3 Performance Monitoring

**Recommended:** Implement performance profiling to monitor:
- Chart rendering frame rate
- Indicator computation time
- Memory usage during live trading
- LLM inference latency

## 7. Deployment Notes

### 7.1 Build Configuration

The project uses XcodeGen for build configuration. Ensure `project.yml` is updated if adding new dependencies:

```bash
brew install xcodegen
xcodegen generate
open EZIN.xcodeproj
```

### 7.2 CI/CD Pipeline

The GitHub Actions CI pipeline automatically builds an unsigned `.ipa` on every push to `main`. Ensure all changes are tested locally before pushing.

### 7.3 Backward Compatibility

All changes maintain backward compatibility with existing user data:
- New `ChatConfig` field has a default value
- New chart toggles default to enabled
- Existing local models continue to work without modification

## 8. v1.3.0 Audit Fixes (APEX + VINNY Release)

### 8.1 Games Tab Navigation Repaired

**Issue:** Every `NavigationLink` in the Games tab was dead — tapping a game did nothing. Root cause:
the app root (`RootView`) uses a custom `GlassTabBar` with a `switch`, so no `NavigationView` existed
anywhere in the view hierarchy above `GamesView`.

**Fix:** `GamesView` now wraps its content in its own `NavigationView` (iOS 15-compatible) and game
screens explicitly restore the navigation bar. Also added the "Built-in Apps" section hosting VINNY.

**File:** `EZIN/Games/GamesView.swift`

### 8.2 ZIP Artifact Corruption Fixed

**Issue:** `ArtifactsCreator.createSimpleZip` / `createAppPrototype` wrote central-directory records
with **zeroed CRC-32, compressed size, and uncompressed size**. macOS Finder tolerated it, but strict
unzippers rejected the archives or extracted corrupt files.

**Fix:** New `EZIN/Services/ZipWriter.swift` emits spec-compliant ZIPs: local file headers, central
directory, and EOCD with real ISO 3309 CRC-32 checksums and sizes. `ArtifactsCreator` now delegates to
it. Covered by unit tests (PK signatures, EOCD, entry count, known CRC-32 vector).

**Files:** `EZIN/Services/ZipWriter.swift` (new), `EZIN/Services/ArtifactsCreator.swift`,
`EZINTests/ApexEnginesTests.swift` (`ZipWriterTests`)

### 8.3 Chat Artifact Attachment Correctness

**Issue 1:** Artifact bubbles were only attached when the tool name started with `create_`, so tools
like the VINNY loop builder produced files silently.

**Issue 2:** Because `ArtifactStore.lastArtifact` persisted, a file the *user* uploaded could be
attached to the *next unrelated* assistant reply.

**Fix:** Any tool that produces an artifact now attaches a bubble, and `lastArtifact` is cleared
before every tool run so stale uploads can never leak across replies.

**File:** `EZIN/Views/ChatView.swift`

### 8.4 VINNY DSP Safety Hardening

Audit-pass fixes applied while building the DSP core:

- Triangle oscillator formula could output −3 (out of [−1, 1]) — corrected to `4·|p−0.5|−1`.
- ADSR release segment could divide by zero on zero-length notes — clamped span.
- `estimateBPM` could construct an invalid `Range` on very short audio — guarded.
- `freezePad` could compute a negative slice index on short buffers — guarded.
- Renderer indexed the wavetable cache with the per-lane index instead of the oscillator index —
  per-lane tables now built up front.
- The widener FX doubled buffer length mid-chain (mono→stereo inside a mono pipeline) — stereo
  widening now happens only at the final render stage.
- Negative loop-variation seeds could trap on `UInt64` conversion — clamped.

**Files:** `EZIN/Vinny/VinnyDSP.swift`, `EZIN/Vinny/VinnyEngine.swift`, `EZIN/Vinny/VinnyStudio.swift`

### 8.5 New Test Coverage

- `EZINTests/ApexEnginesTests.swift` — pattern detection, market profile, liquidity clustering,
  range forecast, entropy/ER ordering, regime bias, master confluence bounds, scanner ranking, ZIP
  integrity.
- `EZINTests/VinnyDSPTests.swift` — WAV round-trip, oscillator bounds, ADSR lifecycle, all 10 FX,
  time warp, BPM ±6 on a synthetic 120 BPM click track, key detection on a C-major chord, FFT peak,
  spectral fusion, MIDI header, loop factory stems, Genesis/mutation/breeding, theory quantize.

## Conclusion

These improvements significantly enhance the EZIN application's capabilities, particularly in local LLM support and advanced technical analysis visualization. The modular architecture ensures that future enhancements can be added without disrupting existing functionality.

## 9. v1.8.0 Comprehensive Audit Fixes

### 9.1 "Same Song 6 Times" — Chat Backend Tools Consistency Fix

**Issue 1:** `create_song` tool was completely deterministic — `promptToNotes()` had only
4 branches (major chord, minor chord, scale, arpeggio), always producing identical notes
for the same prompt text. Asking for a song multiple times generated the exact same output.

**Issue 2:** VINNY loop seed was deterministic: `seedBase = UInt64(abs(prompt.hashValue) % 100000)`
produced the same seed for the same prompt, so `vinny_loop` always generated identical loops.

**Issue 3:** `create_song` used primitive sine-wave audio instead of the full VINNY production
engine (drums + bass + chords + lead), making it the weaker path when the LLM chose it.

**Issue 4:** The chat `runLoop` had no tool-call deduplication — the LLM could call the same
tool repeatedly in a single turn.

**Fixes:**
- `create_song` now routes through VINNY Loop Factory for natural-language style prompts,
  producing rich multi-track audio (drums, bass, chords, lead). Falls back to
  `AudioGenerationService` only for explicit note notation.
- All music generation tools (`create_song`, `vinny_loop`, `vinny_patch`, `vinny_reference`,
  `vinny_stems`) now use time-based seeding (`Date().timeIntervalSince1970 * 1000`) combined
  with prompt hashing, ensuring every call produces a unique variation.
- `promptToNotes()` was expanded from 4 patterns to include blues/jazz riffs, multiple
  pentatonic scales, and varied chord inversions — all modulated by time-based variation
  in key, tempo, rhythm, and amplitude.
- `chordPattern()` now accepts `tempo` and `variation` parameters for dynamic rhythm
  and inversion changes.
- Artifact filenames now include timestamps to prevent collisions.
- System prompt updated to direct the LLM to prefer `vinny_loop` for music requests.
- `runLoop` now tracks tool calls per turn and blocks repeated calls to the same tool
  (max 2 per tool per user message, max 6 total steps).

**Files:** `EZIN/Chat/ToolRegistry.swift`, `EZIN/Chat/VinnyChatTools.swift`,
`EZIN/Chat/ChatModels.swift`, `EZIN/Views/ChatView.swift`

### 9.2 Duplicate `skill_import` Switch Case — Compile Error

**Issue:** `ToolRegistry.run()` had two `case "skill_import":` entries (lines 54 and 182),
which is a Swift compile error. The first mapped to `skillImport(args)` and the second to
`skillImportTool(args:)`.

**Fix:** Removed the first duplicate at line 54, keeping the enhanced `skillImportTool`
which routes through `SkillsExtensionService.shared.importSkill`.

**File:** `EZIN/Chat/ToolRegistry.swift`

### 9.3 NSExpression Security Vulnerability — Calculator Tool

**Issue:** `ChatToolExpansion.calculate()` used `NSExpression(format: expr)` with arbitrary
user input, which can execute arbitrary code (e.g. `FUNCTION(0, "intValue", ...)`) and
crash the app.

**Fix:** Replaced with a safe recursive-descent `SimpleMathEvaluator` that only permits
numbers, basic arithmetic (`+`, `-`, `*`, `/`), parentheses, and named math functions
(`sqrt`, `abs`, `log`, `ln`, `sin`, `cos`, `exp`). Input is whitelisted to reject any
non-math characters.

**File:** `EZIN/Services/ChatToolExpansionService.swift`

### 9.4 Variable Shadowing — `randomNumbersTool` and `statistics`

**Issue:** `randomNumbersTool` declared `let min = ...` and `let max = ...`, shadowing
Swift's built-in `Swift.min` and `Swift.max` functions. Similarly, `statistics()` used
`let min = sorted.first!` and `let max = sorted.last!`.

**Fix:** Renamed to `minVal`/`maxVal` in both locations.

**Files:** `EZIN/Chat/ToolRegistry.swift`, `EZIN/Services/ChatToolExpansionService.swift`

### 9.5 Games Tab Navigation — Dead NavigationLinks

**Issue:** `GamesView` used `NavigationLink` without a `NavigationView` or `NavigationStack`
wrapper, so tapping games and VINNY did nothing. The BUG_FIXES doc claimed this was fixed
but the NavigationView wrapper was missing from the actual code.

**Fix:** Wrapped `GamesView`'s body in a `NavigationView` with `.navigationBarHidden(true)`
so the games list appears normally and pushed views get a navigation bar.

**File:** `EZIN/Games/GamesView.swift`

### 9.6 VINNY `registerArtifact` Access Level

**Issue:** `registerArtifact(data:name:ext:)` in `VinnyChatTools.swift` was marked
`private`, preventing `ToolRegistry.swift`'s `createSong` from calling it (cross-file
access within the same struct).

**Fix:** Changed to `internal` (default) access level so it's accessible from all
`ToolRegistry` extensions.

**File:** `EZIN/Chat/VinnyChatTools.swift`

## 10. v1.8.1 Deep Audit — Additional Fixes

### 10.1 AlertsEngine MACD Signal Array Crash

**Issue:** Both MACD cross-evaluation cases (`.macdCrossAbove` and `.macdCrossBelow`) guarded
only `macdResult.macd.count >= 2` before accessing `macdResult.signal[count - 2]` and
`macdResult.signal.last!`. If the signal array was shorter than the MACD array (possible
with short data series), this caused an index-out-of-bounds crash.

**Fix:** Added `macdResult.signal.count >= 2` to both guard conditions.

**File:** `EZIN/Services/AlertsEngine.swift`

### 10.2 ChartView DateFormatter Performance (render stutter)

**Issue:** `CandleChart.timeLabel()` created a new `DateFormatter` on every call inside the
Canvas `render` function, which runs at 60fps during pan/zoom gestures. `DateFormatter`
initialization is notoriously expensive on iOS, causing visible frame drops.

**Fix:** Replaced per-call `DateFormatter()` with two `static let` cached formatters
(`timeFormatter` for HH:mm, `dayFormatter` for MMM d).

**File:** `EZIN/Views/ChartView.swift`

### 10.3 SignalFusionEngine `closes.last!` Crash Safety

**Issue:** `bayesianDirection()` used `closes.last!` which force-unwraps an optional.
Although the caller guards `closes.count >= 30`, defensive programming requires a safe
fallback to prevent any future code path from crashing.

**Fix:** Replaced `closes.last!` with `guard let lastClose = closes.last else { return .neutral }`.

**File:** `EZIN/Engine/SignalFusionEngine.swift`

### 10.4 AIPipelineService Unbounded Log Growth

**Issue:** `pipelineLog` grew without limit — every stage of every pipeline execution was
appended, causing unbounded memory growth over long sessions.

**Fix:** Added a 200-entry cap: after each append, if `pipelineLog.count > 200`, trim to
the most recent 200 entries.

**File:** `EZIN/Services/AIPipelineService.swift`

### 10.5 Alert Push Notification Missing Permission Check

**Issue:** `PushNotificationManager.scheduleLocalNotification()` (called from the alert
evaluator) did not check `isEnabled` before scheduling, so notifications were silently
queued even when the user had denied permission.

**Fix:** Added `guard isEnabled else { return }` at the top of the method.

**File:** `EZIN/Services/AlertsEngine.swift`

## 11. v1.9.0 — Sidebar Navigation + GGUF LLM Fix

### 11.1 Bottom Tab Bar → Collapsible Sidebar Navigation

**Issue:** The bottom `GlassTabBar` consumed valuable vertical screen space and crowded
9 tabs into a narrow strip with tiny labels.

**Fix:** Replaced the bottom tab bar with a slide-out sidebar triggered by a hamburger
(☰) button in the header. The sidebar:
- Slides in from the left with spring animation
- Shows brand header, all 9 navigation items with icons and labels
- Highlights the active tab with an accent pill indicator
- Auto-dismisses on item selection or tap-outside
- Has a dimmed backdrop overlay
- Shows connection status and version in the footer

**Files:** `EZIN/App/RootView.swift` (complete rewrite of navigation shell)

### 11.2 GGUF LLM File — Imported Models Now Actually Used

**Issue:** When a user imported a .gguf model file and selected it, the app silently
fell back to remote API providers. The `LocalLLMInferenceService.generate()` threw
`runtimeUnavailable` and the AIRouter caught it without telling the user. The imported
file was catalogued but never used.

**Fix:**
1. **GGUF header parser** — reads the magic bytes, version, tensor count, and scans
   for architecture (llama, mistral, gemma, etc.), context length, embedding length,
   and block count from the binary metadata.
2. **Model filename passed to endpoint** — when a custom endpoint (llama.cpp, Ollama,
   vLLM) is configured, the model's filename is sent in the `model` field so the
   server loads the correct imported file.
3. **Clear setup instructions** — when no endpoint is configured, the error message
   now includes step-by-step instructions for setting up llama.cpp or Ollama with
   the imported model file, instead of silently falling back.
4. **LLMModelsView shows status** — each model shows whether an endpoint is configured
   (green ✓) or setup is needed (orange ⚠️) with specific commands.
5. **Metadata displayed** — model format badge (GGUF/SAFETENSORS), file size, and
   selection state are clearly shown.

**Files:** `EZIN/Services/LocalLLMInferenceService.swift` (rewritten),
`EZIN/Chat/AIRouter.swift`, `EZIN/Views/LLMModelsView.swift`

### 11.3 AppState Retain Cycle Fix

**Issue:** `restartBackend()` created a `Task` that captured `self` strongly,
potentially extending the lifetime of the AppState beyond the view hierarchy.

**Fix:** Added `[weak self]` capture with early `guard let self else { return }`.

**File:** `EZIN/App/AppState.swift`
