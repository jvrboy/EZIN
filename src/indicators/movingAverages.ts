// Moving averages — ported from EZIN/Indicators/MovingAverages.swift
// (SMA, EMA, RMA, WMA, DEMA, TEMA, HMA, VWMA, KAMA).

export function sma(src: number[], len: number): number[] {
  return src.map((_, i) => {
    if (i < len - 1) return 0
    let s = 0
    for (let j = i - len + 1; j <= i; j++) s += src[j]
    return s / len
  })
}

export function ema(src: number[], len: number): number[] {
  const k = 2 / (len + 1)
  const out: number[] = []
  for (let i = 0; i < src.length; i++) {
    out.push(i === 0 ? src[i] : src[i] * k + out[i - 1] * (1 - k))
  }
  return out
}

/** Wilder's smoothing (RMA) — used by RSI / ATR. */
export function rma(src: number[], len: number): number[] {
  const alpha = 1 / len
  const out: number[] = []
  for (let i = 0; i < src.length; i++) {
    out.push(i === 0 ? src[i] : alpha * src[i] + (1 - alpha) * out[i - 1])
  }
  return out
}

export function wma(src: number[], len: number): number[] {
  return src.map((_, i) => {
    if (i < len - 1) return 0
    let num = 0
    let den = 0
    for (let j = 0; j < len; j++) {
      num += src[i - j] * (len - j)
      den += len - j
    }
    return num / den
  })
}

export function dema(src: number[], len: number): number[] {
  const e1 = ema(src, len)
  const e2 = ema(e1, len)
  return src.map((_, i) => 2 * e1[i] - e2[i])
}

export function tema(src: number[], len: number): number[] {
  const e1 = ema(src, len)
  const e2 = ema(e1, len)
  const e3 = ema(e2, len)
  return src.map((_, i) => 3 * e1[i] - 3 * e2[i] + e3[i])
}

export function hma(src: number[], len: number): number[] {
  const half = Math.floor(len / 2)
  const sqrtLen = Math.floor(Math.sqrt(len))
  const w1 = wma(src, Math.max(half, 1))
  const w2 = wma(src, len)
  const raw = src.map((_, i) => 2 * w1[i] - w2[i])
  return wma(raw, Math.max(sqrtLen, 1))
}

export function vwma(src: number[], vol: number[], len: number): number[] {
  return src.map((_, i) => {
    if (i < len - 1) return 0
    let num = 0
    let den = 0
    for (let j = i - len + 1; j <= i; j++) {
      num += src[j] * vol[j]
      den += vol[j]
    }
    return den !== 0 ? num / den : 0
  })
}

export function kama(src: number[], len = 10, fast = 2, slow = 30): number[] {
  const fastSC = 2 / (fast + 1)
  const slowSC = 2 / (slow + 1)
  const out: number[] = []
  for (let i = 0; i < src.length; i++) {
    const v = src[i]
    if (i < len) {
      out.push(v)
      continue
    }
    const change = Math.abs(v - src[i - len])
    let vol = 0
    for (let j = i - len + 1; j <= i; j++) vol += Math.abs(src[j] - src[j - 1])
    const er = vol !== 0 ? change / vol : 0
    const sc = Math.pow(er * (fastSC - slowSC) + slowSC, 2)
    out.push(out[i - 1] + sc * (v - out[i - 1]))
  }
  return out
}
