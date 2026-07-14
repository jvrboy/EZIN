# EZIN

**Deriv signal intelligence — glass edition.** Native SwiftUI iOS app (iOS 15+) porting the
`forex-signals` / `forex-jsx` indicator suite and the multi-agent Deriv trading bots, with a
real-time chart, an AI assistant, and MCP tooling.

## Tabs

1. **Chart** — clean candlestick chart with advanced overlays: instrument picker, timeframe selector, pan + pinch-zoom,
   live tick updates, unlimited historical backfill, **Volume Profile**, **Heatmap**, and **Jump Markers**.
2. **Signals** — live council signals with **Multi-Timeframe Analysis** and **Real-Time Performance Tracking**.
3. **Chat** — a simple chat surface backed by a powerful agent/tool orchestrator with **Local LLM support** and **Nvidia NIM/Cerebras** integration.
4. **History** — *Trades* (real closed trades from your Deriv account) and *Signals* (app-generated
   signals logged on-device in real time, shown even with **no API token**).
5. **Bot** — start/stop the perpetual scalper.
6. **Settings** — assistant, bot, appearance, API keys, MCP, Deriv config.

## Instruments (all Deriv markets)

Volatility Indices + Volatility (1s), Boom & Crash (300/500/600/900/1000), Jump, Step, Range Break,
DEX, Drift Switch, plus Forex, Commodities (metals), Crypto and Stock Indices.

## Indicators (50+)

- **Volatility:** ATR, Bollinger Bands, Keltner, Donchian, Std Dev, Historical Volatility,
  Chaikin Volatility, Mass Index, Ulcer Index.
- **Momentum:** RSI, Stochastic, MACD, Momentum, ROC, Williams %R, CCI, TRIX, Ultimate Oscillator,
  Chande Momentum (CMO), MFI.
- **Direction/Trend:** ADX/DMI, Parabolic SAR, Ichimoku, Supertrend, SMA/EMA/WMA/DEMA/TEMA/HMA/VWMA/KAMA,
  Gann HiLo, Pivot Points, Linear Regression slope, Heikin Ashi, trend strength.
- **Volume:** OBV, A/D Line, Chaikin Money Flow, Volume Oscillator, MFI, Ease of Movement,
  NVI, PVI, VWAP, Force Index.
- **Advanced Overlays:**
    - **Volume Profile:** POC, Value Area High/Low, and volume-at-price distribution.
    - **Liquidity Heatmap:** Clustered swing highs/lows indicating resting orders.
    - **Jump Markers:** Statistical outlier detection for significant price moves.

## Signal engine (Multi-Timeframe)

**Multi-Timeframe Consensus Engine** analyzes M1, M5, M15, M30, H1, H4, and D1 simultaneously using **12 specialist agents** per timeframe.
- **Indicator Confluence**: Requires agreement across multiple timeframes and 50+ indicators.
- **Microstructure Analysis**: Incorporates volume profile, order flow, and liquidity levels.
- **Real-Time Tracking**: Monitors every signal's P&L, accuracy, and win rate in real-time.
- **Self-Improvement**: Automated recommendation engine suggests strategy adjustments based on performance metrics.

## AI assistant (Chat tab)

- **Extended Provider Support:** Now includes **Nvidia NIM**, **Cerebras**, and **FreeModel.dev** for high-performance, low-latency inference.
- **Local LLM Inference:** Import and run your own GGUF or SafeTensors models directly on-device for private, low-latency assistance.
- **Auto-routing** across all your providers (OpenAI, Anthropic, OpenRouter, Gemini, Groq, Mistral):
  picks the strongest available model and falls back on failure.
- **Unlimited API keys per provider** — add as many as you like; EZIN rotates through them (round-robin)
  so a single key's rate limit never blocks you.
- **36 specialist agents + 50 pipelines** power an orchestration loop.
- **In-app tools** the assistant can call: `analyze`, `signals`, `price`, `instruments`, `history`,
  `place_trade` (guarded), and `mcp`.

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
