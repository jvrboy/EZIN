# Repository Audit & Feature Expansion — 2026-07

## Scope

Full pass over the EZIN codebase (126 Swift files: App, Chat, Deriv, Engine,
Indicators, Models, Services, Strategies, Theme, Views, Vinny + EZINTests) focused on:

1. Correctness / crash-safety issues in the chat tool layer.
2. Capability gaps — engines that exist in the codebase but were **not** exposed
   as chat tools.
3. Test coverage for money-critical math.

---

## Audit findings (fixed in this change)

| # | Severity | Finding | Fix |
|---|---|---|---|
| 1 | High | `ChatToolExpansion.calculate` fed raw user input into `NSExpression(format:)`. Malformed input (e.g. `"2 +"`, unbalanced parens, stray letters) raises an **Objective-C exception that Swift cannot catch → app crash** from a single chat message. | Input is now whitelisted to numeric/operator characters and parenthesis-balance-checked before `NSExpression` is constructed; bad input returns a friendly error instead of crashing. |
| 2 | Medium | Duplicate `case "skill_import"` in the `ToolRegistry.run` switch — the second branch (`skillImportTool`, JSON import via SkillsExtensionService) was **unreachable dead code**; JSON skill import could never be invoked. | Second branch renamed to `skill_import_json` and advertised in the system prompt. `skill_import` (text/MD import) keeps its original behavior. |
| 3 | Low | `skills_catalog`, `skill_export`, `skill_create_custom` were wired in the registry but never mentioned in the system prompt → the model could not discover them. | Added to the App-control tool line in `ChatConfig.defaultPrompt`. |
| 4 | Low | Watchlist was only editable through the generic `set_setting(key:"watchlist")` full-replace path — easy for the model to accidentally wipe the list. | Added incremental `watchlist_add` / `watchlist_remove` / `watchlist_show` tools. |

Also verified during the audit (no action needed):

- `ToolRegistry` switch has no other duplicate cases.
- `MarketMath`-style pure helpers previously lived inline inside tool bodies; the
  new `Engine/MarketMath.swift` centralizes them so they are unit-testable.
- CI (`.github/workflows/build.yml`) builds only the app target for the `.ipa` and
  runs `EZINTests` under the `test` action — new test file slots in automatically
  via `project.yml` path-based sources.

---

## New features

### 1. `Engine/MarketMath.swift` — pure market-math layer

Deterministic, dependency-free math used by the new tools and covered by tests:

- **Fibonacci** retracements (23.6–78.6 %) + extensions (127.2–200 %) for up/down legs.
- **Pivot sets**: Classic, Woodie, Camarilla (R1–R3 / S1–S3).
- **Streak statistics**: current/max up-down streaks, P(up|up), P(up|down).
- **Risk/Reward**: geometry validation, R:R ratio, breakeven win rate.
- **Kelly fraction** (clamped, edge-aware) and **expectancy** in R-multiples.

### 2. `Chat/MarketToolPack.swift` — 14 new chat tools

| Tool | What it does |
|---|---|
| `indicator_values(symbol,timeframe)` | One-shot Markdown table of RSI, MACD, ADX/DMI, ATR, Bollinger, Stochastic, CCI, Williams %R, MFI, Supertrend, VWAP, EMA20/50, SMA200, historical vol, CMF, ROC — each with a plain-English read. |
| `divergence_scan(symbol,timeframe[,indicator])` | Regular + hidden divergences between price and RSI / MACD histogram / OBV using the existing `DivergenceEngine` (previously chart-only). |
| `spike_scan(symbol,timeframe)` | Price-spike and ATR volatility-spike detection over the last 30 bars using the existing `Spike` engine (previously unexposed). |
| `fib_levels(symbol,timeframe[,lookback] \| high,low[,direction])` | Fibonacci grid from the auto-detected swing of cached candles or an explicit range. |
| `pivot_levels(symbol,timeframe[,method])` | Classic / Woodie / Camarilla pivots from the previous candle, tagged above/below current price. |
| `streak_stats(symbol,timeframe)` | Streak lengths + conditional continuation probabilities → trend-following vs mean-reversion read. |
| `candle_anatomy(symbol,timeframe[,count])` | Body/upper-wick/lower-wick percentage table of the last N candles for price-action reading. |
| `volatility_rank([symbols,timeframe])` | Ranks watchlist (or given symbols) by ATR % of price and historical volatility. |
| `session_clock()` | Live SAST session status + per-asset-class scan cadence/confidence policy from `TradingSession`. |
| `risk_reward(entry,stop,target[,account_size,risk_percent])` | Validates trade geometry, computes R:R, breakeven win rate, and optional position sizing. |
| `kelly_size(win_rate,payoff[,account_size])` | Full/half/quarter Kelly stake sizing with expectancy check and "don't bet" warning on negative edge. |
| `watchlist_show()` | Watchlist table with live prices. |
| `watchlist_add(symbols)` | Incremental add with symbol validation (rejects unknowns, dedupes). |
| `watchlist_remove(symbols)` | Incremental remove. |

All tools are registered in `ToolRegistry.run`, documented in the default system
prompt (`ChatModels.swift`) **and** in the always-current addendum in
`ChatView.runLoop` so users with a stale persisted prompt still get them.

### 3. Tests — `EZINTests/MarketMathTests.swift`

23 assertions-worth of deterministic coverage: fib up/down legs, all three pivot
methods, streak edge cases (empty/flat/all-down), long/short R:R plus bad-geometry
rejection, Kelly known values / clamping / invalid inputs, and expectancy signs.

---

## Files changed

- **New:** `EZIN/Engine/MarketMath.swift`, `EZIN/Chat/MarketToolPack.swift`,
  `EZINTests/MarketMathTests.swift`, `AUDIT_AND_NEW_TOOLS.md`
- **Modified:** `EZIN/Chat/ToolRegistry.swift` (tool routing + dead-case fix),
  `EZIN/Chat/ChatModels.swift` (prompt), `EZIN/Views/ChatView.swift` (addendum),
  `EZIN/Services/ChatToolExpansionService.swift` (calculate crash guard),
  `README.md` (tool list)
