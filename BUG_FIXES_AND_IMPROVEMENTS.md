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
