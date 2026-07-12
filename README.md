# EZIN

**Deriv signal intelligence — glass edition.** Native SwiftUI iOS app (iOS 15+) ported from the
`forex-signals` / `forex-jsx` indicator suite and the multi-agent Deriv trading bots.

## Features

- **Glassmorphism UI** — frosted `.ultraThinMaterial` cards, animated aurora background, spring transitions.
- **4 tabs:** Signals · History · Bot · Settings.
- **Faithful indicator engine (Swift):** Moving Averages (SMA/EMA/RMA/WMA/DEMA/TEMA/HMA/VWMA/KAMA),
  RSI, MACD, ATR, Bollinger Bands, Stochastic, CCI, Williams %R, Momentum, ROC, OBV, MFI, ADX/DMI,
  Supertrend, plus a pivot-based **Divergence Engine** and spike detectors.
- **Hidden multi-agent backend:** 7 specialized agents (Trend, Momentum, MeanReversion, Volume,
  Divergence, Volatility, Structure) → weighted **VotingCouncil** → **SignalEngine**. Runs continuously
  in the background and pushes signals to the UI.
- **Deriv API:** default **public app id `1089`** out of the box; users can add their own app id + token.
- **Settings for everything:** notifications, auto-trade, risk sizing, default strategy.
- **LLM model import:** import `.gguf`, `.safetensors`, `.bin` or any file — **no size limit** — copied
  into the app's own directory.
- **AI API keys:** OpenAI, Anthropic, Gemini, Groq, Mistral, OpenRouter, Hugging Face — saved to the
  **Keychain** so you never re-enter them.
- **Pipelines:** build ordered analysis pipelines (fetch → indicators → divergence → agents → council → emit → trade).
- **Self-owned storage:** creates its own directory under **On My iPhone → EZIN** (Files app) and persists
  models, pipelines, history and logs automatically.

## Architecture

```
EZIN/
├── App/            EZINApp, AppState, RootView (glass tab bar)
├── Theme/          Glass design system + aurora background
├── Models/         Core types, TradingSignal, indicators container, domain models
├── Indicators/     MovingAverages + full indicator library
├── Strategies/     DivergenceEngine + spike detectors
├── Engine/         TechnicalAnalyzer, Agents, VotingCouncil, SignalEngine, BotRuntime
├── Deriv/          WebSocket client + symbol catalog
├── Services/       FileStore (Files-app dir), CredentialStore (Keychain), Stores
└── Views/          Signals, History, Bot, Settings + sub-screens
```

## Build

The project is defined with **XcodeGen** (`project.yml`). CI builds an **unsigned `.ipa`** on every push.

```bash
brew install xcodegen
xcodegen generate
open EZIN.xcodeproj
```

CI: `.github/workflows/build.yml` → generates the project, runs `xcodebuild` with signing disabled, and
uploads `EZIN-unsigned.ipa` as a workflow artifact.

> Note: EZIN is a **native iOS (Swift)** app. An Android `.apk` target is not applicable to a SwiftUI
> codebase; only the iOS unsigned `.ipa` is produced.
