import Foundation

/// Deriv symbol catalog (subset of config/settings.DERIV_ASSETS) + display mapping.
enum DerivSymbols {
    static let forex = ["frxEURUSD", "frxGBPUSD", "frxUSDJPY", "frxAUDUSD",
                        "frxUSDCAD", "frxUSDCHF", "frxNZDUSD", "frxEURJPY", "frxGBPJPY"]
    static let synthetic = ["R_75", "R_100", "R_50", "R_25", "R_10", "1HZ75V", "BOOM1000", "CRASH1000"]
    static let crypto = ["cryBTCUSD", "cryETHUSD"]
    static let commodity = ["frxXAUUSD", "frxXAGUSD"]

    static let all = forex + synthetic + crypto + commodity

    static func display(_ symbol: String) -> String {
        if symbol.hasPrefix("frx") {
            let s = String(symbol.dropFirst(3))
            if s.count == 6 {
                return "\(s.prefix(3))/\(s.suffix(3))"
            }
            return s
        }
        switch symbol {
        case "R_75": return "V75"
        case "R_100": return "V100"
        case "R_50": return "V50"
        case "R_25": return "V25"
        case "R_10": return "V10"
        case "cryBTCUSD": return "BTC/USD"
        case "cryETHUSD": return "ETH/USD"
        default: return symbol
        }
    }

    static func assetClass(_ symbol: String) -> AssetClass {
        if forex.contains(symbol) { return .forex }
        if crypto.contains(symbol) { return .crypto }
        if commodity.contains(symbol) { return .commodity }
        return .synthetic
    }
}
