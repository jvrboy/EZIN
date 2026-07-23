# EZIN

**Deriv signal intelligence — glass edition.** Native SwiftUI iOS app (iOS 15+) porting the
`forex-signals` / `forex-jsx` indicator suite and the multi-agent Deriv trading bots, with a
real-time chart, an AI assistant, and MCP tooling.

## Tabs

1. **Chart** — clean candlestick chart with advanced overlays: instrument picker, timeframe selector, pan + pinch-zoom,
   live tick updates, unlimited historical backfill, **Volume Profile**, **Heatmap**, **Jump Markers**, and persistent on-chart **support/resistance lines, time markers, supply/demand rectangles, and trend rays**.
2. **Signals** — live council signals with **Multi-Timeframe Analysis** and **Real-Time Performance Tracking**.
3. **Games** — built-in mini-apps, headlined by **VINNY** (see below): a full on-device sound-design
   and loop-building workstation.
4. **Chat** — a simple chat surface backed by a powerful agent/tool orchestrator with **Local LLM support** and **Nvidia NIM/Cerebras** integration.
5. **History** — *Trades* (real closed trades from your Deriv account) and *Signals* (app-generated
   signals logged on-device in real time, shown even with **no API token**).
6. **Bot** — start/stop the perpetual scalper.
7. **Settings** — assistant, bot, appearance, API keys, MCP, Deriv config.

## Instruments (all Deriv markets)

Volatility Indices + Volatility (1s), Boom & Crash (300/500/600/900/1000), Jump, Step, Range Break,
DEX, Drift Switch, plus Forex, Commodities (metals), Crypto and Stock Indices.

## Indicators (50+)

- **Volatility:** ATR, Bollinger Bands, Keltner, Donchian, Std Dev, Historical Volatility,
  Chaikin Volatility, Mass Index, Ulcer Index, Chandelier Exit, Bollinger %B, Z-Score bands.
- **Momentum:** RSI, Stochastic, MACD, Momentum, ROC, Williams %R, CCI, TRIX, Ultimate Oscillator,
  Chande Momentum (CMO), MFI, PPO, Coppock Curve, Fisher Transform, Aroon Oscillator, Vortex Indicator.
- **Direction/Trend:** ADX/DMI, Parabolic SAR, Ichimoku, Supertrend, SMA/EMA/WMA/DEMA/TEMA/HMA/VWMA/KAMA,
  Gann HiLo, Pivot Points, Linear Regression slope, Heikin Ashi, trend strength.
- **Volume:** OBV, A/D Line, Chaikin Money Flow, Volume Oscillator, MFI, Ease of Movement,
  NVI, PVI, VWAP, Force Index.
- **Advanced Overlays:**
    - **Volume Profile:** POC, Value Area High/Low, and volume-at-price distribution.
    - **Liquidity Heatmap:** Clustered swing highs/lows indicating resting orders.
    - **Jump Markers:** Statistical outlier detection for significant price moves.

## Signal engine (Multi-Timeframe)

**Multi-Timeframe Consensus Engine** analyzes M1, M5, M15, M30, H1, H4, and D1 simultaneously using **18 specialist agents** per timeframe.
- **Indicator Confluence**: Requires agreement across multiple timeframes and 50+ indicators.
- **Microstructure Analysis**: Incorporates volume profile, order flow, and liquidity levels.
- **Real-Time Tracking**: Monitors every signal's P&L, accuracy, and win rate in real-time.
- **Self-Improvement**: Automated recommendation engine suggests strategy adjustments based on performance metrics.

## APEX — second-generation analysis layer

APEX is a new on-device backend that fuses classic price action with quantitative measures, and feeds
both the signal council and the chat assistant:

- **Candlestick pattern engine** — engulfing, hammer/shooting star, doji, morning/evening star,
  three soldiers/crows with graded strength.
- **Market profile (TPO)** — Point of Control and 70% value area from tick-volume distribution.
- **Liquidity map** — clustered equal highs/lows (resting liquidity) plus sweep detection.
- **Range forecast** — Parkinson and Garman–Klass volatility estimators project the next-bar range.
- **Entropy & trend quality** — Shannon entropy, Kaufman Efficiency Ratio, and Higuchi fractal
  dimension separate trending from noisy regimes.
- **Regime switching** — a Markov-lite bull/bear/range classifier with transition probabilities.
- **Tape speed** — tick-rate analysis for activity bursts.
- **Master confluence** — a weighted scorecard that merges every APEX engine *and* the existing
  agent council into one actionable read.
- **Multi-symbol scanner** — ranks your watchlist by combined confluence.

Six new council agents (`PatternAgent`, `MarketProfileAgent`, `TrendQualityAgent`, `LiquidityAgent`,
`RegimeSwitchAgent`, `TapeSpeedAgent`) vote alongside the original twelve.

## AI assistant (Chat tab)

- **Extended Provider Support:** Now includes **Nvidia NIM**, **Cerebras**, and **FreeModel.dev** for high-performance, low-latency inference.
- **Local LLM Inference:** Import and run your own GGUF or SafeTensors models directly on-device for private, low-latency assistance.
- **Auto-routing** across all your providers (OpenAI, Anthropic, OpenRouter, Gemini, Groq, Mistral):
  picks the strongest available model and falls back on failure.
- **Unlimited API keys per provider** — add as many as you like; EZIN rotates through them (round-robin)
  so a single key's rate limit never blocks you.
- **36 specialist agents + 50 pipelines** power an orchestration loop, now expanded with a deterministic virtual backend layer exposing 1,500 additional analytics/risk/structure/execution/data-quality/agentic tools.
- **In-app tools** the assistant can call: `analyze`, `signals`, `price`, `instruments`, `history`,
  `quant_analysis`, `market_regime`, `backtest`, `risk_plan`, `structure_confluence`, `performance_snapshot`, `export_signal_data`, `place_trade` (guarded), and `mcp`.
- **APEX tools**: `master_confluence`, `pattern_scan`, `market_profile`, `liquidity_map`,
  `range_forecast`, `entropy_analysis`, `symbol_scanner`.
- **Expanded backend tools**: `backend_tool_catalog`, `agentic_pipeline_catalog`, `agentic_power_plan`, and `backend_tool_001` through `backend_tool_1500` for deterministic specialist diagnostics.
- **VINNY tools**: `vinny_loop` (text → finished loop), `vinny_patch` (text → synth patch),
  `vinny_reference` (upload any audio in chat and ask for a loop "like this"), `vinny_stems`
  (STEMS ZIP export), `vinny_library` (saved loops/presets).
- **Audio artifacts play inline** — WAV/MP3/AIFF attachments render a player bubble with
  play/pause, ±10s skip, scrub slider, and share sheet.

## VINNY — Unified Sound Intelligence Engine

A complete audio workstation built into the Games tab, powered by a pure-Swift DSP core
(no external dependencies):

- **Genesis** — describe a sound in words ("dark gritty 808 with slow attack") and VINNY builds the
  synth patch; or import/record audio and it reverse-engineers a matching patch.
- **Loop Factory** — genre-aware drums, bass, chords, and lead generation with swing, humanize,
  per-lane stems, and a mastered mix. Exports WAV + MIDI + a real **STEMS ZIP**.
- **WaveForge** — oscillator lab: 4 stacked oscillators (sine/triangle/saw/square/noise/wavetable),
  unison, FM/RM/AM, sub + noise, ADSR, and a resonant multi-mode filter.
- **TempoShift** — time warp (speed, multiband, tape-stop), a 16-step gate sequencer, and re-groove.
- **Earprint** — import or record 4 seconds of audio; VINNY estimates BPM, key
  (Krumhansl–Schmuckler), spectral centroid, and loudness, then stores an 8-D "sound fingerprint"
  you can match against your preset library — or one-tap "Build Similar Loop".
- **FlowState** — drawable modulation curves routed to filter/pitch/width, plus LFO shapes
  (sine, tri, square, sample & hold, gravity, pendulum, chaos).
- **Organica** — granular cloud and freeze-pad synthesis from any source audio.
- **Spaceship** — a 24-slot FX rack: delay, reverb, chorus, flanger, distortion, bitcrush,
  ring mod, compressor, 3-band EQ, widener.
- **Hybridizer** — spectral fusion (STFT cross-synthesis), rhythm/timbre transfer, genre migrator,
  and patch breeding/mutation.
- **Stage** — 16 scale-locked performance pads, arpeggiator, 16 scenes, and scene morphing.
- **Vault** — searchable patch/loop library, JSON import/export, and a render time machine.
- **VINNY AI** — chat commands ("make it darker", "add more bounce"), a coach that suggests
  improvements, color-to-sound, a piano roll, and a guided learning path.

Everything VINNY renders can be sent to chat as a playable artifact, saved to the Vault,
or exported (WAV / MIDI / STEMS ZIP / patch JSON).

## MCP connectors

Settings → Chat → MCP Connectors. Point EZIN at your own MCP servers:

- **MetaTrader 5** — e.g. `vincentwongso/mt5-trading-mcp` or `amirkhonov/metatrader5-mcp` (Windows/Docker).
- **TradingView** — e.g. `atilaahmettaner/tradingview-mcp`.
- **Custom** — any HTTP MCP server.

The app is the MCP **client**; heavy tools (code/script execution, web scraping/automation) run on the
MCP servers you connect — the correct architecture for a sandboxed iOS app.

## Appearance

8 themes (Aurora, Liquid Glass, Midnight, Sunset, Ocean, Forest, Mono, Neon) with gradient palettes and
an animated-background motion toggle.

## Quantitative & structure backends

The on-device quantitative backend exposes repeatable trend, momentum, breakout and mean-reversion scores; descriptive statistics; ACF/Hurst/cycle estimates; chi-square, entropy, runs and Markov-style transition diagnostics; ATR/Kelly/VaR/CVaR risk inputs; a deterministic **market-regime classifier** (trend / squeeze / mean-reversion / transitional state); and a cost-aware crossover replay. The structure backend combines clustered support/resistance, supply/demand impulses, and RSI/MACD divergences. Signal tracking now also supports **performance snapshots** and **CSV export** for later review. These are decision-support tools, not predictions or execution authority.

## Real-time & production

Live Deriv WebSocket API (`wss://ws.derivws.com`) with **automatic reconnect + backoff + resubscribe**,
live balance/ticks/candles, proposals, buys, `proposal_open_contract` (live P&L), sells, and `profit_table`.
Credentials are stored in the Keychain **device-only** (never synced to iCloud). App Transport Security is
enforced (no arbitrary loads).

> Live order execution requires your Deriv PAT. Validate on a **demo** account first before going live.

## Build

XcodeGen (`project.yml`). CI builds an unsigned `.ipa` on every push to `main` and publishes it to the
`build-latest` GitHub Release.

```bash
brew install xcodegen
xcodegen generate
open EZIN.xcodeproj
```

> EZIN is a native iOS (Swift) app; only the iOS unsigned `.ipa` is produced.
