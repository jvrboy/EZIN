// Full Deriv symbol catalog — ported from EZIN/Deriv/DerivSymbols.swift
// Symbol strings follow Deriv's WebSocket `active_symbols` API names.

import type { AssetClass } from '../models/core'

export const volatility = ['R_10', 'R_25', 'R_50', 'R_75', 'R_100']
export const volatility1s = ['1HZ10V', '1HZ25V', '1HZ50V', '1HZ75V', '1HZ100V', '1HZ150V', '1HZ250V']
export const boom = ['BOOM300N', 'BOOM500', 'BOOM600', 'BOOM900', 'BOOM1000']
export const crash = ['CRASH300N', 'CRASH500', 'CRASH600', 'CRASH900', 'CRASH1000']
export const jump = ['JD10', 'JD25', 'JD50', 'JD75', 'JD100']
export const step = ['stpRNG', 'stpRNG2', 'stpRNG3', 'stpRNG4', 'stpRNG5']
export const rangeBreak = ['RB100', 'RB200']
export const dex = ['DEX600DN', 'DEX600UP', 'DEX900DN', 'DEX900UP', 'DEX1500DN', 'DEX1500UP']
export const driftSwitch = ['DSI10', 'DSI20', 'DSI30']

export const synthetic = [
  ...volatility,
  ...volatility1s,
  ...boom,
  ...crash,
  ...jump,
  ...step,
  ...rangeBreak,
  ...dex,
  ...driftSwitch,
]

export const forex = [
  'frxEURUSD',
  'frxGBPUSD',
  'frxUSDJPY',
  'frxAUDUSD',
  'frxUSDCAD',
  'frxUSDCHF',
  'frxNZDUSD',
  'frxEURJPY',
  'frxGBPJPY',
  'frxEURGBP',
  'frxEURCHF',
  'frxEURAUD',
  'frxEURCAD',
  'frxAUDJPY',
  'frxGBPAUD',
  'frxGBPCAD',
  'frxGBPCHF',
  'frxAUDCAD',
  'frxAUDNZD',
  'frxAUDCHF',
  'frxCADJPY',
  'frxCHFJPY',
  'frxNZDJPY',
  'frxEURNZD',
]

export const commodity = ['frxXAUUSD', 'frxXAGUSD', 'frxXPTUSD', 'frxXPDUSD']

export const crypto = [
  'cryBTCUSD',
  'cryETHUSD',
  'cryLTCUSD',
  'cryBCHUSD',
  'cryXRPUSD',
  'cryBNBUSD',
  'cryADAUSD',
  'cryDOTUSD',
  'crySOLUSD',
  'cryDOGUSD',
]

export const stockIndex = [
  'OTC_SPC',
  'OTC_NDX',
  'OTC_DJI',
  'OTC_FTSE',
  'OTC_GDAXI',
  'OTC_N225',
  'OTC_AS51',
  'OTC_HSI',
  'OTC_FCHI',
  'OTC_SX5E',
]

export const allSymbols = [...synthetic, ...forex, ...commodity, ...crypto, ...stockIndex]

const nameMap: Record<string, string> = {
  R_10: 'Volatility 10',
  R_25: 'Volatility 25',
  R_50: 'Volatility 50',
  R_75: 'Volatility 75',
  R_100: 'Volatility 100',
  '1HZ10V': 'Volatility 10 (1s)',
  '1HZ25V': 'Volatility 25 (1s)',
  '1HZ50V': 'Volatility 50 (1s)',
  '1HZ75V': 'Volatility 75 (1s)',
  '1HZ100V': 'Volatility 100 (1s)',
  '1HZ150V': 'Volatility 150 (1s)',
  '1HZ250V': 'Volatility 250 (1s)',
  stpRNG: 'Step Index',
  stpRNG2: 'Step 200',
  stpRNG3: 'Step 300',
  stpRNG4: 'Step 400',
  stpRNG5: 'Step 500',
  OTC_SPC: 'US 500',
  OTC_NDX: 'US Tech 100',
  OTC_DJI: 'Wall St 30',
  OTC_FTSE: 'UK 100',
  OTC_GDAXI: 'Germany 40',
  OTC_N225: 'Japan 225',
  OTC_AS51: 'Australia 200',
  OTC_HSI: 'Hong Kong 50',
  OTC_FCHI: 'France 40',
  OTC_SX5E: 'Euro 50',
}

export function displayName(symbol: string): string {
  const mapped = nameMap[symbol]
  if (mapped) return mapped
  if (symbol.startsWith('frx')) {
    const s = symbol.slice(3)
    switch (s) {
      case 'XAUUSD':
        return 'Gold'
      case 'XAGUSD':
        return 'Silver'
      case 'XPTUSD':
        return 'Platinum'
      case 'XPDUSD':
        return 'Palladium'
    }
    if (s.length === 6) return `${s.slice(0, 3)}/${s.slice(3)}`
    return s
  }
  if (symbol.startsWith('cry')) {
    const s = symbol.slice(3)
    if (s.length === 6) return `${s.slice(0, 3)}/${s.slice(3)}`
    return s
  }
  if (symbol.startsWith('BOOM')) {
    const n = symbol.slice(4).replace(/N/g, '')
    return `Boom ${n}`
  }
  if (symbol.startsWith('CRASH')) {
    const n = symbol.slice(5).replace(/N/g, '')
    return `Crash ${n}`
  }
  if (symbol.startsWith('JD')) return `Jump ${symbol.slice(2)}`
  if (symbol.startsWith('RB')) return `Range Break ${symbol.slice(2)}`
  if (symbol.startsWith('DSI')) return `Drift Switch ${symbol.slice(3)}`
  if (symbol.startsWith('DEX')) return `DEX ${symbol.slice(3)}`
  return symbol
}

export function assetClassOf(symbol: string): AssetClass {
  if (commodity.includes(symbol)) return 'commodity'
  if (symbol.startsWith('frx')) return 'forex'
  if (symbol.startsWith('cry')) return 'crypto'
  if (symbol.startsWith('OTC_')) return 'index'
  return 'synthetic'
}

/** Price value of one point/pip for stop conversion. */
export function pointSize(symbol: string): number {
  if (symbol.startsWith('frx')) {
    if (
      symbol.includes('XAU') ||
      symbol.includes('XAG') ||
      symbol.includes('XPT') ||
      symbol.includes('XPD')
    ) {
      return 0.01
    }
    return symbol.includes('JPY') ? 0.01 : 0.0001
  }
  if (symbol.startsWith('cry')) return 1.0
  if (symbol.startsWith('OTC_')) return 0.1
  return 0.01
}

/** All tradable instruments grouped for the picker. */
export const symbolGroups: Array<[string, string[]]> = [
  ['Volatility Indices', volatility],
  ['Volatility Indices (1s)', volatility1s],
  ['Boom & Crash', [...boom, ...crash]],
  ['Jump Indices', jump],
  ['Step Indices', step],
  ['Range Break', rangeBreak],
  ['DEX Indices', dex],
  ['Drift Switch', driftSwitch],
  ['Forex', forex],
  ['Commodities', commodity],
  ['Cryptocurrencies', crypto],
  ['Stock Indices', stockIndex],
]
