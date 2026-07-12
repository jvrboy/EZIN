import Foundation

/// Full Deriv symbol catalog — every major tradable instrument grouped for the picker.
/// Symbol strings follow Deriv's WebSocket `active_symbols` API names.
enum DerivSymbols {

    // MARK: Synthetics
    static let volatility = ["R_10", "R_25", "R_50", "R_75", "R_100"]
    static let volatility1s = ["1HZ10V", "1HZ25V", "1HZ50V", "1HZ75V", "1HZ100V", "1HZ150V", "1HZ250V"]
    static let boom = ["BOOM300N", "BOOM500", "BOOM600", "BOOM900", "BOOM1000"]
    static let crash = ["CRASH300N", "CRASH500", "CRASH600", "CRASH900", "CRASH1000"]
    static let jump = ["JD10", "JD25", "JD50", "JD75", "JD100"]
    static let step = ["stpRNG", "stpRNG2", "stpRNG3", "stpRNG4", "stpRNG5"]
    static let rangeBreak = ["RB100", "RB200"]
    static let dex = ["DEX600DN", "DEX600UP", "DEX900DN", "DEX900UP", "DEX1500DN", "DEX1500UP"]
    static let driftSwitch = ["DSI10", "DSI20", "DSI30"]

    static let synthetic = volatility + volatility1s + boom + crash + jump + step + rangeBreak + dex + driftSwitch

    // MARK: Forex
    static let forex = [
        "frxEURUSD", "frxGBPUSD", "frxUSDJPY", "frxAUDUSD", "frxUSDCAD", "frxUSDCHF",
        "frxNZDUSD", "frxEURJPY", "frxGBPJPY", "frxEURGBP", "frxEURCHF", "frxEURAUD",
        "frxEURCAD", "frxAUDJPY", "frxGBPAUD", "frxGBPCAD", "frxGBPCHF", "frxAUDCAD",
        "frxAUDNZD", "frxAUDCHF", "frxCADJPY", "frxCHFJPY", "frxNZDJPY", "frxEURNZD"
    ]

    // MARK: Commodities (metals)
    static let commodity = ["frxXAUUSD", "frxXAGUSD", "frxXPTUSD", "frxXPDUSD"]

    // MARK: Crypto
    static let crypto = [
        "cryBTCUSD", "cryETHUSD", "cryLTCUSD", "cryBCHUSD", "cryXRPUSD",
        "cryBNBUSD", "cryADAUSD", "cryDOTUSD", "crySOLUSD", "cryDOGUSD"
    ]

    // MARK: Stock indices (Deriv OTC)
    static let stockIndex = [
        "OTC_SPC", "OTC_NDX", "OTC_DJI", "OTC_FTSE", "OTC_GDAXI",
        "OTC_N225", "OTC_AS51", "OTC_HSI", "OTC_FCHI", "OTC_SX5E"
    ]

    static let all = synthetic + forex + commodity + crypto + stockIndex

    private static let nameMap: [String: String] = [
        "R_10": "Volatility 10", "R_25": "Volatility 25", "R_50": "Volatility 50",
        "R_75": "Volatility 75", "R_100": "Volatility 100",
        "1HZ10V": "Volatility 10 (1s)", "1HZ25V": "Volatility 25 (1s)", "1HZ50V": "Volatility 50 (1s)",
        "1HZ75V": "Volatility 75 (1s)", "1HZ100V": "Volatility 100 (1s)",
        "1HZ150V": "Volatility 150 (1s)", "1HZ250V": "Volatility 250 (1s)",
        "stpRNG": "Step Index", "stpRNG2": "Step 200", "stpRNG3": "Step 300",
        "stpRNG4": "Step 400", "stpRNG5": "Step 500",
        "OTC_SPC": "US 500", "OTC_NDX": "US Tech 100", "OTC_DJI": "Wall St 30",
        "OTC_FTSE": "UK 100", "OTC_GDAXI": "Germany 40", "OTC_N225": "Japan 225",
        "OTC_AS51": "Australia 200", "OTC_HSI": "Hong Kong 50", "OTC_FCHI": "France 40",
        "OTC_SX5E": "Euro 50"
    ]

    static func display(_ symbol: String) -> String {
        if let n = nameMap[symbol] { return n }
        if symbol.hasPrefix("frx") {
            let s = String(symbol.dropFirst(3))
            switch s {
            case "XAUUSD": return "Gold"
            case "XAGUSD": return "Silver"
            case "XPTUSD": return "Platinum"
            case "XPDUSD": return "Palladium"
            default: break
            }
            if s.count == 6 { return "\(s.prefix(3))/\(s.suffix(3))" }
            return s
        }
        if symbol.hasPrefix("cry") {
            let s = String(symbol.dropFirst(3))
            if s.count == 6 { return "\(s.prefix(3))/\(s.suffix(3))" }
            return s
        }
        if symbol.hasPrefix("BOOM") {
            let n = symbol.dropFirst(4).replacingOccurrences(of: "N", with: "")
            return "Boom \(n)"
        }
        if symbol.hasPrefix("CRASH") {
            let n = symbol.dropFirst(5).replacingOccurrences(of: "N", with: "")
            return "Crash \(n)"
        }
        if symbol.hasPrefix("JD") { return "Jump \(symbol.dropFirst(2))" }
        if symbol.hasPrefix("RB") { return "Range Break \(symbol.dropFirst(2))" }
        if symbol.hasPrefix("DSI") { return "Drift Switch \(symbol.dropFirst(3))" }
        if symbol.hasPrefix("DEX") { return "DEX \(symbol.dropFirst(3))" }
        return symbol
    }

    static func assetClass(_ symbol: String) -> AssetClass {
        if commodity.contains(symbol) { return .commodity }
        if symbol.hasPrefix("frx") { return .forex }
        if symbol.hasPrefix("cry") { return .crypto }
        if symbol.hasPrefix("OTC_") { return .index }
        return .synthetic
    }

    /// Price value of one point/pip for stop conversion.
    static func pointSize(_ symbol: String) -> Double {
        if symbol.hasPrefix("frx") {
            if symbol.contains("XAU") || symbol.contains("XAG") || symbol.contains("XPT") || symbol.contains("XPD") { return 0.01 }
            return symbol.contains("JPY") ? 0.01 : 0.0001
        }
        if symbol.hasPrefix("cry") { return 1.0 }
        if symbol.hasPrefix("OTC_") { return 0.1 }
        return 0.01
    }

    /// All tradable instruments grouped for the picker.
    static let groups: [(String, [String])] = [
        ("Volatility Indices", volatility),
        ("Volatility Indices (1s)", volatility1s),
        ("Boom & Crash", boom + crash),
        ("Jump Indices", jump),
        ("Step Indices", step),
        ("Range Break", rangeBreak),
        ("DEX Indices", dex),
        ("Drift Switch", driftSwitch),
        ("Forex", forex),
        ("Commodities", commodity),
        ("Cryptocurrencies", crypto),
        ("Stock Indices", stockIndex),
    ]
}
