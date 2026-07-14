// Core technical indicators — ported from EZIN/Indicators/Indicators.swift

import { ema, rma, sma } from './movingAverages'

// RSI
export function rsi(close: number[], len = 14): number[] {
  if (close.length === 0) return []
  const gains = new Array<number>(close.length).fill(0)
  const losses = new Array<number>(close.length).fill(0)
  for (let i = 1; i < close.length; i++) {
    const d = close[i] - close[i - 1]
    gains[i] = d > 0 ? d : 0
    losses[i] = d < 0 ? -d : 0
  }
  const avgG = rma(gains, len)
  const avgL = rma(losses, len)
  return close.map((_, i) => {
    if (avgL[i] === 0) return 100
    const rs = avgG[i] / avgL[i]
    return 100 - 100 / (1 + rs)
  })
}

// MACD
export function macd(
  close: number[],
  fast = 12,
  slow = 26,
  signal = 9,
): { macd: number[]; signal: number[]; histogram: number[] } {
  const emaFast = ema(close, fast)
  const emaSlow = ema(close, slow)
  const macdLine = close.map((_, i) => emaFast[i] - emaSlow[i])
  const sig = ema(macdLine, signal)
  const hist = macdLine.map((v, i) => v - sig[i])
  return { macd: macdLine, signal: sig, histogram: hist }
}

// True Range + ATR
export function trueRange(high: number[], low: number[], close: number[]): number[] {
  return high.map((_, i) => {
    if (i === 0) return high[i] - low[i]
    return Math.max(high[i] - low[i], Math.abs(high[i] - close[i - 1]), Math.abs(low[i] - close[i - 1]))
  })
}

export function atr(high: number[], low: number[], close: number[], len = 14): number[] {
  return rma(trueRange(high, low, close), len)
}

// Bollinger Bands
export function bollinger(
  close: number[],
  len = 20,
  mult = 2,
): { upper: number[]; middle: number[]; lower: number[] } {
  const mid = sma(close, len)
  const upper = new Array<number>(close.length).fill(0)
  const lower = new Array<number>(close.length).fill(0)
  for (let i = len - 1; i < close.length; i++) {
    let sumSq = 0
    for (let j = i - len + 1; j <= i; j++) sumSq += Math.pow(close[j] - mid[i], 2)
    const sd = Math.sqrt(sumSq / len)
    upper[i] = mid[i] + mult * sd
    lower[i] = mid[i] - mult * sd
  }
  return { upper, middle: mid, lower }
}

// Stochastic
export function stochastic(
  high: number[],
  low: number[],
  close: number[],
  kLen = 14,
  dLen = 3,
): { k: number[]; d: number[] } {
  const k = new Array<number>(close.length).fill(50)
  for (let i = kLen - 1; i < close.length; i++) {
    let hh = high[i]
    let ll = low[i]
    for (let j = i - kLen + 1; j <= i; j++) {
      if (high[j] > hh) hh = high[j]
      if (low[j] < ll) ll = low[j]
    }
    k[i] = hh - ll !== 0 ? ((close[i] - ll) / (hh - ll)) * 100 : 50
  }
  return { k, d: sma(k, dLen) }
}

// CCI
export function cci(high: number[], low: number[], close: number[], len = 20): number[] {
  const tp = close.map((_, i) => (high[i] + low[i] + close[i]) / 3)
  const smaTP = sma(tp, len)
  const out = new Array<number>(close.length).fill(0)
  for (let i = len - 1; i < close.length; i++) {
    let md = 0
    for (let j = i - len + 1; j <= i; j++) md += Math.abs(tp[j] - smaTP[i])
    md /= len
    out[i] = md !== 0 ? (tp[i] - smaTP[i]) / (0.015 * md) : 0
  }
  return out
}

// Williams %R
export function williamsR(high: number[], low: number[], close: number[], len = 14): number[] {
  const out = new Array<number>(close.length).fill(-50)
  for (let i = len - 1; i < close.length; i++) {
    let hh = high[i]
    let ll = low[i]
    for (let j = i - len + 1; j <= i; j++) {
      if (high[j] > hh) hh = high[j]
      if (low[j] < ll) ll = low[j]
    }
    out[i] = hh - ll !== 0 ? ((hh - close[i]) / (hh - ll)) * -100 : -50
  }
  return out
}

// Momentum & ROC
export function momentum(close: number[], len = 10): number[] {
  return close.map((_, i) => (i >= len ? close[i] - close[i - len] : 0))
}

export function roc(close: number[], len = 12): number[] {
  return close.map((_, i) =>
    i >= len && close[i - len] !== 0 ? ((close[i] - close[i - len]) / close[i - len]) * 100 : 0,
  )
}

// OBV
export function obv(close: number[], volume: number[]): number[] {
  const out = new Array<number>(close.length).fill(0)
  for (let i = 1; i < close.length; i++) {
    if (close[i] > close[i - 1]) out[i] = out[i - 1] + volume[i]
    else if (close[i] < close[i - 1]) out[i] = out[i - 1] - volume[i]
    else out[i] = out[i - 1]
  }
  return out
}

// MFI
export function mfi(high: number[], low: number[], close: number[], volume: number[], len = 14): number[] {
  const tp = close.map((_, i) => (high[i] + low[i] + close[i]) / 3)
  const out = new Array<number>(close.length).fill(50)
  for (let i = len; i < close.length; i++) {
    let pos = 0
    let neg = 0
    for (let j = i - len + 1; j <= i; j++) {
      if (j <= 0) continue
      const raw = tp[j] * volume[j]
      if (tp[j] > tp[j - 1]) pos += raw
      else if (tp[j] < tp[j - 1]) neg += raw
    }
    out[i] = neg !== 0 ? 100 - 100 / (1 + pos / neg) : 100
  }
  return out
}

// ADX / DMI
export function adx(
  high: number[],
  low: number[],
  close: number[],
  len = 14,
): { adx: number[]; plusDI: number[]; minusDI: number[] } {
  const n = close.length
  const plusDM = new Array<number>(n).fill(0)
  const minusDM = new Array<number>(n).fill(0)
  for (let i = 1; i < n; i++) {
    const up = high[i] - high[i - 1]
    const down = low[i - 1] - low[i]
    plusDM[i] = up > down && up > 0 ? up : 0
    minusDM[i] = down > up && down > 0 ? down : 0
  }
  const tr = trueRange(high, low, close)
  const atrS = rma(tr, len)
  const plusS = rma(plusDM, len)
  const minusS = rma(minusDM, len)
  const plusDI = new Array<number>(n).fill(0)
  const minusDI = new Array<number>(n).fill(0)
  const dx = new Array<number>(n).fill(0)
  for (let i = 0; i < n; i++) {
    plusDI[i] = atrS[i] !== 0 ? (100 * plusS[i]) / atrS[i] : 0
    minusDI[i] = atrS[i] !== 0 ? (100 * minusS[i]) / atrS[i] : 0
    const sum = plusDI[i] + minusDI[i]
    dx[i] = sum !== 0 ? (100 * Math.abs(plusDI[i] - minusDI[i])) / sum : 0
  }
  return { adx: rma(dx, len), plusDI, minusDI }
}

// Supertrend
export function supertrend(
  high: number[],
  low: number[],
  close: number[],
  len = 10,
  mult = 3,
): { line: number[]; up: boolean[] } {
  const n = close.length
  const atrS = atr(high, low, close, len)
  const line = new Array<number>(n).fill(0)
  const up = new Array<boolean>(n).fill(true)
  for (let i = 0; i < n; i++) {
    const hl2 = (high[i] + low[i]) / 2
    const upperBand = hl2 + mult * atrS[i]
    const lowerBand = hl2 - mult * atrS[i]
    if (i === 0) {
      line[i] = lowerBand
      up[i] = true
      continue
    }
    if (close[i] > line[i - 1]) up[i] = true
    else if (close[i] < line[i - 1]) up[i] = false
    else up[i] = up[i - 1]
    line[i] = up[i] ? Math.max(lowerBand, line[i - 1]) : Math.min(upperBand, line[i - 1])
  }
  return { line, up }
}
