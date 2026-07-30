# EZIN Architecture

EZIN is a native SwiftUI iOS application built from `project.yml` with XcodeGen. The current app target is organized by feature folders and is being prepared for a package-oriented architecture that can support stricter concurrency, backend services, and production compliance.

## Client modules

| Area | Current location | Responsibility |
| --- | --- | --- |
| App shell | `EZIN/App` | App entry point, root navigation, shared runtime state. |
| Views | `EZIN/Views` | SwiftUI screens for charting, settings, chat, signals, journal, alerts, bots, and analytics. |
| Services | `EZIN/Services` | Local persistence, credential storage, notifications, artifacts, LLM support, news/calendar surfaces, and background refresh. |
| Trading engines | `EZIN/Engine` | Signal generation, voting, backtesting, analytics, portfolio, bot runtime, and APEX analysis. |
| Indicators | `EZIN/Indicators` | Deterministic technical indicator calculations. |
| Chat | `EZIN/Chat` | Assistant routing, tools, memory, conversations, artifacts, and provider selection. |
| Broker/data | `EZIN/Deriv` | Deriv symbol catalog and WebSocket client. |
| MCP | `EZIN/MCP` | Client-side MCP connector metadata and request execution. |
| VINNY | `EZIN/Vinny`, `EZIN/Games` | On-device DSP, music generation, playback, and mini-app surfaces. |

## Target module boundaries

The next migration step is to extract stable code into Swift Packages in this order:

1. `Core`: shared models, formatters, validation, and errors.
2. `TradingEngine`: indicators, signal generation, voting, risk math, and backtesting.
3. `MarketData`: broker/data clients, tick buffers, candles, and market sessions.
4. `AgentEngine`: agent orchestration, LLM gateway contracts, audit events, and tool permissions.
5. `DataLayer`: encrypted local persistence, sync DTOs, and cache policies.
6. `UI`: SwiftUI feature modules with dependency-injected state.
7. `Testing`: fixtures, mocks, deterministic clocks, and sample market data.

## Backend boundary

Backend code lives under `backend/functions` and is configured by `firebase.json`. Cloud Functions provide authenticated ingestion and safety backstops for calendar, news, risk, and LLM proxy workflows. Firestore rules enforce per-user access and append-only audit logs.

## Security baseline

- Trading credentials and API keys stay in Keychain on-device.
- Firestore user data is scoped by Firebase Auth UID.
- Audit log documents are append-only.
- Paper trading remains the default operating mode.
- Server-side endpoints require Firebase bearer tokens and admin custom claims for ingestion workflows.

## Concurrency baseline

The project is configured for Swift 6 language mode with complete strict concurrency diagnostics. UI-bound stores should remain `@MainActor`; shared mutable non-UI state should move behind actors or immutable value types as the compiler migration proceeds.
