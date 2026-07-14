# Implementation Plan for EZIN Enhancements

This document outlines the detailed plan for implementing the requested features: real LLM import and integration, and advanced chart indicators (heatmap, volume profile, markers profile).

## 1. Real LLM Import and Integration

**Current State:**
- `AIRouter.swift` handles routing to remote LLM providers.
- `LLMModelsView.swift` and `FileStore.swift` manage the import and storage of local LLM model files, but no local inference logic exists.
- `ChatView.swift` and `ChatModels.swift` lack UI and configuration for local LLM selection.

**Proposed Solution:**

### 1.1. Add `llama.cpp` Swift Bindings Dependency
- **Action:** Integrate a Swift Package Manager (SPM) compatible `llama.cpp` binding. The official `ggerganov/llama.cpp` repository offers SPM support, which is the preferred method.
- **File:** `project.yml` (to add the SPM dependency).

### 1.2. Create `LocalLLMInferenceService`
- **Action:** Develop a new Swift class responsible for loading and executing local LLM models.
- **File:** `EZIN/Services/LocalLLMInferenceService.swift` (new file).
- **Details:**
    - This service will take an `LLMModel` object (from `LLMModelStore`) and use the `llama.cpp` bindings to load the model.
    - It will expose a method, e.g., `func generate(prompt: String, model: LLMModel) async throws -> String`, to perform inference.
    - Error handling for model loading, inference, and resource management will be included.

### 1.3. Update `DomainModels.swift`
- **Action:** Add a new `CredentialKey` to represent local LLM inference.
- **File:** `EZIN/Models/DomainModels.swift`.
- **Details:**
    - Add `.localLLM` to the `CredentialKey` enum.

### 1.4. Update `ChatModels.swift`
- **Action:** Extend `ChatConfig` to include a property for the selected local LLM model.
- **File:** `EZIN/Chat/ChatModels.swift`.
- **Details:**
    - Add an optional `UUID` property, e.g., `var selectedLocalModelID: UUID?`, to `ChatConfig` to store the ID of the chosen local model.
    - Update `ChatConfigStore` to persist this new property.

### 1.5. Modify `AIRouter.swift`
- **Action:** Implement logic to route chat requests to the `LocalLLMInferenceService` if a local model is selected.
- **File:** `EZIN/Chat/AIRouter.swift`.
- **Details:**
    - In the `complete` function, check `ChatConfig.shared.selectedLocalModelID`.
    - If a `selectedLocalModelID` is present and the corresponding `LLMModel` is available in `LLMModelStore`, instantiate `LocalLLMInferenceService` and call its `generate` method.
    - Prioritize local LLM inference if selected, otherwise fall back to the existing remote provider routing logic.

### 1.6. Update `ChatView.swift` and `LLMModelsView.swift`
- **Action:** Enhance the UI to allow users to select an imported local model for chat.
- **Files:** `EZIN/Views/ChatView.swift`, `EZIN/Views/LLMModelsView.swift`.
- **Details:**
    - In `LLMModelsView.swift`, add a selection mechanism (e.g., a radio button or a 
toggle) next to each imported model to set it as the active model for chat.
    - In `ChatSettingsView.swift` (or `ChatView.swift` if more appropriate), display the currently selected local model and provide a way to navigate to `LLMModelsView` for selection.

## 2. Advanced Chart Indicators: Heatmap, Volume Profile, Markers Profile

**Current State:**
- `ChartView.swift` renders a basic candlestick chart with price and time axes, but no overlays for advanced indicators.
- `Microstructure.swift` already contains the calculations for `volumeProfile`, `marketProfile`, `detectJumps` (for markers), and `liquidityLevels` (for heatmap).
- `CoreTypes.swift` defines `Candle` and `MarketData` which are suitable for consuming by the rendering logic.

**Proposed Solution:**

### 2.1. Extend `ChartViewModel`
- **Action:** Add published properties to `ChartViewModel` to hold the computed data for the new indicators.
- **File:** `EZIN/Views/ChartView.swift`.
- **Details:**
    - Add `@Published var volumeProfileData: Microstructure.VolumeProfile?`.
    - Add `@Published var marketProfileData: [Microstructure.MarketProfileRow]?`.
    - Add `@Published var jumpEvents: [Microstructure.JumpEvent]?`.
    - Add `@Published var liquidityLevels: [Microstructure.LiquidityLevel]?`.
    - Modify the `reload()` method to call the respective `Microstructure` functions and populate these new properties.

### 2.2. Update `CandleChart.render`
- **Action:** Implement drawing logic within the `render` function of `CandleChart` to visualize the new indicators.
- **File:** `EZIN/Views/ChartView.swift`.
- **Details:**
    - **Volume Profile:** Iterate through `volumeProfileData.bins` and draw horizontal bars (rectangles) at the corresponding price levels, with width proportional to volume. Highlight POC, Value Area High, and Value Area Low.
    - **Heatmap (Liquidity Levels):** Iterate through `liquidityLevels` and draw horizontal lines or shaded areas at the specified price levels, with opacity or color intensity reflecting `strength`.
    - **Markers Profile (Jump Events):** Iterate through `jumpEvents` and draw small icons or triangles at the `index` (time) and corresponding price, indicating the direction (`up`) and `magnitude` of the jump.
    - Ensure proper scaling and positioning of these overlays relative to the existing candlestick chart, respecting `vm.scale` and `vm.offset`.
    - Add toggles in the UI (e.g., in `ChartView`'s `selectorBar` or a new settings menu) to enable/disable the visibility of each indicator.

### 2.3. Refactor `ChartView` for Readability and Maintainability
- **Action:** Extract drawing logic for each indicator into separate helper functions or sub-views within `CandleChart` to keep `render` clean.
- **File:** `EZIN/Views/ChartView.swift`.
- **Details:**
    - Create private functions like `drawVolumeProfile(ctx:size:lo:hi:plotW:y:)`, `drawHeatmap(ctx:size:lo:hi:plotW:y:)`, `drawJumpMarkers(ctx:size:lo:hi:x:y:)`.
    - This will improve code organization and make it easier to add more indicators in the future.

## 3. Bug Fixes and General Improvements

**Current State:**
- No explicit bugs were found during the initial `grep` search for TODO/FIXME/BUG.
- The `README.md` mentions 
no specific bugs, but general improvements are always possible.

**Proposed Solution:**

### 3.1. Code Review and Refactoring
- **Action:** Conduct a thorough code review of `SignalEngine.swift` and `DerivClient.swift` for potential logic errors, race conditions, or inefficiencies.
- **Files:** `EZIN/Engine/SignalEngine.swift`, `EZIN/Deriv/DerivClient.swift`.
- **Details:**
    - Pay close attention to data handling, WebSocket communication, and signal generation logic.
    - Optimize any identified performance bottlenecks.

### 3.2. Error Handling and Logging
- **Action:** Enhance error handling and logging across the application, especially in critical components like `DerivClient` and `AIRouter`.
- **Files:** Various Swift files.
- **Details:**
    - Implement more specific error types where appropriate.
    - Add comprehensive logging to aid in debugging and monitoring.

### 3.3. Performance Optimization
- **Action:** Profile the application to identify and address any performance issues, particularly related to chart rendering and LLM inference.
- **Files:** Various Swift files.
- **Details:**
    - Optimize data structures and algorithms where necessary.
    - Ensure efficient use of system resources.

## Conclusion

This plan provides a roadmap for integrating local LLM capabilities and advanced chart indicators into EZIN, along with general improvements. Each step will be implemented and tested incrementally to ensure stability and functionality.
