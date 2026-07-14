// Core market types — ported from EZIN/Models/CoreTypes.swift

export enum Direction {
  StrongBearish = -2,
  Bearish = -1,
  Neutral = 0,
  Bullish = 1,
  StrongBullish = 2,
}

export function isBullish(d: Direction): boolean {
  return d === Direction.Bullish || d === Direction.StrongBullish
}

export function isBearish(d: Direction): boolean {
  return d === Direction.Bearish || d === Direction.StrongBearish
}

export enum SignalStrength {
  Weak = 1,
  Moderate = 2,
  Strong = 3,
  VeryStrong = 4,
  Extreme = 5,
}

export type SignalType = 'BUY' | 'SELL' | 'HOLD' | 'STRONG_BUY' | 'STRONG_SELL'

export type AssetClass = 'forex' | 'crypto' | 'synthetic' | 'commodity' | 'index'

export type Timeframe = '1m' | '5m' | '15m' | '30m' | '1h' | '4h' | '1d'

export const TIMEFRAMES: Timeframe[] = ['1m', '5m', '15m', '30m', '1h', '4h', '1d']

/** Deriv granularity in seconds. */
export function granularity(tf: Timeframe): number {
  switch (tf) {
    case '1m':
      return 60
    case '5m':
      return 300
    case '15m':
      return 900
    case '30m':
      return 1800
    case '1h':
      return 3600
    case '4h':
      return 14400
    case '1d':
      return 86400
  }
}

// OHLCV candle

export interface Candle {
  /** epoch seconds */
  timestamp: number
  open: number
  high: number
  low: number
  close: number
  volume: number
}

export function candleBody(c: Candle): number {
  return Math.abs(c.close - c.open)
}

export function candleRange(c: Candle): number {
  return c.high - c.low
}

export function candleIsBullish(c: Candle): boolean {
  return c.close > c.open
}

export function candleIsBearish(c: Candle): boolean {
  return c.close < c.open
}

// MarketData

export interface MarketData {
  symbol: string
  assetClass: AssetClass
  timeframe: Timeframe
  candles: Candle[]
  currentPrice: number
  bid: number
  ask: number
}

export function closes(m: MarketData): number[] {
  return m.candles.map((c) => c.close)
}
export function highs(m: MarketData): number[] {
  return m.candles.map((c) => c.high)
}
export function lows(m: MarketData): number[] {
  return m.candles.map((c) => c.low)
}
export function opens(m: MarketData): number[] {
  return m.candles.map((c) => c.open)
}
export function volumes(m: MarketData): number[] {
  return m.candles.map((c) => c.volume)
}
export function latest(m: MarketData): Candle | undefined {
  return m.candles[m.candles.length - 1]
}

// Agent vote & council decision

export interface AgentVote {
  agentName: string
  direction: Direction
  confidence: number // 0...1
  weight: number // agent trust weight
  rationale: string
}

export interface CouncilDecision {
  symbol: string
  timeframe: Timeframe
  direction: Direction
  confidence: number
  consensusRatio: number
  votes: AgentVote[]
  strength: SignalStrength
}
