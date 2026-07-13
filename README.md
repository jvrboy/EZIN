# EZIN

**Deriv signal intelligence — glass edition.** Native SwiftUI iOS app (iOS 15+) porting the
`forex-signals` / `forex-jsx` indicator suite and the multi-agent Deriv trading bots, with a
real-time chart, an AI assistant, and MCP tooling.

## Tabs

1. **Chart** — clean candlestick chart only: instrument picker, timeframe selector, pan + pinch-zoom,
   live tick updates, and unlimited historical backfill. Nothing else on this tab.
2. **Signals** — live council signals as consensus is reached.
3. **Chat** — a simple chat surface backed by a powerful agent/tool orchestrator (see below).
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

## Signal engine

**12 specialist agents** (Trend, Momentum, MeanReversion, Volume, Divergence, Volatility, Structure,
Ichimoku, Breakout, VWAPFlow, Oscillator, HullTrend) cast weighted votes into a **VotingCouncil** for
higher-confluence, more accurate signals. Runs continuously on live Deriv WebSocket data (no mock data).

## AI assistant (Chat tab)

- **Auto-routing** across all your providers (OpenAI, Anthropic, OpenRouter, Gemini, Groq, Mistral):
  picks the strongest available model and falls back on failure.
- **Unlimited API keys per provider** — add as many as you like; EZIN rotates through them (round-robin)
  so a single key's rate limit never blocks you.
- **36 specialist agents + 50 pipelines** power an orchestration loop.
- **In-app tools** the assistant can call: `analyze`, `signals`, `price`, `instruments`, `history`,
  `place_trade` (guarded), and `mcp`.
- **Customizable** in Settings → Chat: editable system prompt, auto-route toggle, trading permission,
  temperature.

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
