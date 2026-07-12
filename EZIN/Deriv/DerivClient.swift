import Foundation
import Combine

enum DerivConnectionState: Equatable {
    case disconnected, connecting, connected, error(String)
    var label: String {
        switch self {
        case .disconnected: return "Offline"
        case .connecting: return "Connecting"
        case .connected: return "Live"
        case .error: return "Error"
        }
    }
}

/// A live open contract (position) tracked via proposal_open_contract.
struct DerivPosition: Identifiable, Equatable {
    let id: Int              // contract_id
    var symbol: String
    var contractType: String // MULTUP / MULTDOWN
    var buyPrice: Double
    var profit: Double
    var isSold: Bool
    var displaySymbol: String { DerivSymbols.display(symbol) }
    var isUp: Bool { contractType.uppercased().contains("UP") }
}

/// A closed trade from profit_table (real history).
struct DerivClosedTrade: Identifiable {
    let id: Int
    let symbol: String
    let contractType: String
    let profit: Double
    let sellTime: Date
    let buyPrice: Double
}

enum DerivError: Error, LocalizedError {
    case timeout, notConnected, api(String)
    var errorDescription: String? {
        switch self {
        case .timeout: return "Request timed out"
        case .notConnected: return "Not connected to Deriv"
        case .api(let m): return m
        }
    }
}

/// Production Deriv WebSocket client (v3 API).
/// Real-time: authorize, balance, ticks, candles, proposal, buy, portfolio,
/// proposal_open_contract (live P&L), sell, profit_table. No mock data.
final class DerivClient: NSObject, ObservableObject {
    static let defaultAppID = 1089
    static let endpoint = "wss://ws.derivws.com/websockets/v3"

    @Published var connectionState: DerivConnectionState = .disconnected
    @Published var authorized = false
    @Published var balance: Double = 0
    @Published var currency: String = "USD"
    @Published var prices: [String: Double] = [:]           // live tick prices
    @Published var positions: [Int: DerivPosition] = [:]    // live open contracts
    @Published var lastError: String?

    private var task: URLSessionWebSocketTask?
    private lazy var session = URLSession(configuration: .default)
    private var appID = DerivClient.defaultAppID
    private var token: String?
    private var reqID = 0

    /// One-shot request/response continuations keyed by req_id.
    private var waiters: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private let lock = NSLock()

    // MARK: - Connection

    func connect(appID: Int?, token: String?) async {
        self.appID = appID ?? DerivClient.defaultAppID
        self.token = token
        await MainActor.run { self.connectionState = .connecting; self.authorized = false }

        guard let url = URL(string: "\(DerivClient.endpoint)?app_id=\(self.appID)") else {
            await MainActor.run { self.connectionState = .error("bad url") }; return
        }
        task?.cancel(with: .goingAway, reason: nil)
        task = session.webSocketTask(with: url)
        task?.resume()
        receiveLoop()
        await MainActor.run { self.connectionState = .connected }

        if let token = token, !token.isEmpty {
            do {
                let resp = try await request(["authorize": token])
                if let auth = resp["authorize"] as? [String: Any] {
                    await MainActor.run {
                        self.authorized = true
                        self.currency = auth["currency"] as? String ?? "USD"
                    }
                    subscribeBalance()
                    subscribeOpenContracts()
                }
            } catch {
                await MainActor.run { self.lastError = error.localizedDescription }
            }
        }
    }

    func disconnect() {
        send(["forget_all": ["ticks", "candles", "balance", "proposal_open_contract"]])
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        connectionState = .disconnected
        authorized = false
    }

    // MARK: - Market data

    func candles(symbol: String, timeframe: Timeframe, count: Int = 200) async throws -> [Candle] {
        let resp = try await request([
            "ticks_history": symbol, "adjust_start_time": 1, "count": count,
            "end": "latest", "granularity": timeframe.granularity, "style": "candles"
        ])
        guard let arr = resp["candles"] as? [[String: Any]] else {
            if let err = resp["error"] as? [String: Any] { throw DerivError.api(err["message"] as? String ?? "candles error") }
            return []
        }
        return arr.compactMap(Self.parseCandle)
    }

    func subscribeTicks(_ symbol: String) { send(["ticks": symbol, "subscribe": 1]) }

    // MARK: - Trading (Deriv Multipliers)

    /// Request a price proposal for a multiplier contract. Returns (proposalId, askPrice).
    func proposal(symbol: String, up: Bool, stake: Double, multiplier: Int,
                  currency: String, stopLoss: Double?, takeProfit: Double?) async throws -> (id: String, price: Double) {
        var params: [String: Any] = [
            "proposal": 1,
            "amount": stake,
            "basis": "stake",
            "contract_type": up ? "MULTUP" : "MULTDOWN",
            "currency": currency,
            "symbol": symbol,
            "multiplier": multiplier
        ]
        var limit: [String: Any] = [:]
        if let sl = stopLoss { limit["stop_loss"] = sl }
        if let tp = takeProfit { limit["take_profit"] = tp }
        if !limit.isEmpty { params["limit_order"] = limit }

        let resp = try await request(params)
        if let err = resp["error"] as? [String: Any] { throw DerivError.api(err["message"] as? String ?? "proposal error") }
        guard let p = resp["proposal"] as? [String: Any],
              let id = p["id"] as? String else { throw DerivError.api("no proposal id") }
        let price = (p["ask_price"] as? Double) ?? Double((p["ask_price"] as? Int) ?? 0)
        return (id, price)
    }

    /// Buy a contract by proposal id. Returns contract_id.
    @discardableResult
    func buy(proposalId: String, price: Double) async throws -> Int {
        let resp = try await request(["buy": proposalId, "price": price])
        if let err = resp["error"] as? [String: Any] { throw DerivError.api(err["message"] as? String ?? "buy error") }
        guard let b = resp["buy"] as? [String: Any] else { throw DerivError.api("no buy result") }
        let cid = (b["contract_id"] as? Int) ?? Int((b["contract_id"] as? Double) ?? 0)
        subscribeContract(cid)
        return cid
    }

    /// Sell (close) an open contract at market.
    func sell(contractId: Int) async throws {
        let resp = try await request(["sell": contractId, "price": 0])
        if let err = resp["error"] as? [String: Any] { throw DerivError.api(err["message"] as? String ?? "sell error") }
    }

    /// Current open positions count (from live tracking).
    var openPositionCount: Int { positions.values.filter { !$0.isSold }.count }
    var totalOpenProfit: Double { positions.values.filter { !$0.isSold }.reduce(0) { $0 + $1.profit } }

    // MARK: - History

    func profitTable(limit: Int = 50) async throws -> [DerivClosedTrade] {
        let resp = try await request(["profit_table": 1, "description": 1, "limit": limit, "sort": "DESC"])
        if let err = resp["error"] as? [String: Any] { throw DerivError.api(err["message"] as? String ?? "profit_table error") }
        guard let pt = resp["profit_table"] as? [String: Any],
              let txns = pt["transactions"] as? [[String: Any]] else { return [] }
        return txns.compactMap { t in
            func dbl(_ k: String) -> Double { (t[k] as? Double) ?? Double((t[k] as? Int) ?? 0) }
            let buy = dbl("buy_price"); let sell = dbl("sell_price")
            let profit = sell - buy
            let cid = (t["contract_id"] as? Int) ?? Int((t["contract_id"] as? Double) ?? 0)
            let sellEpoch = dbl("sell_time")
            let sym = (t["shortcode"] as? String).flatMap(Self.symbolFromShortcode) ?? (t["underlying_symbol"] as? String ?? "?")
            let type = (t["contract_type"] as? String) ?? ((t["shortcode"] as? String)?.uppercased().contains("MULTUP") == true ? "MULTUP" : "MULTDOWN")
            return DerivClosedTrade(id: cid, symbol: sym, contractType: type, profit: profit,
                                    sellTime: Date(timeIntervalSince1970: sellEpoch), buyPrice: buy)
        }
    }

    // MARK: - Subscriptions

    private func subscribeBalance() { send(["balance": 1, "subscribe": 1]) }
    private func subscribeOpenContracts() { send(["proposal_open_contract": 1, "subscribe": 1]) }
    private func subscribeContract(_ id: Int) { send(["proposal_open_contract": 1, "contract_id": id, "subscribe": 1]) }

    // MARK: - Transport

    private func nextID() -> Int { lock.lock(); reqID += 1; let v = reqID; lock.unlock(); return v }

    private func request(_ dict: [String: Any], timeout: TimeInterval = 20) async throws -> [String: Any] {
        guard task != nil else { throw DerivError.notConnected }
        let id = nextID()
        var payload = dict; payload["req_id"] = id
        return try await withCheckedThrowingContinuation { cont in
            lock.lock(); waiters[id] = cont; lock.unlock()
            send(payload)
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
                guard let self = self else { return }
                self.lock.lock(); let w = self.waiters.removeValue(forKey: id); self.lock.unlock()
                w?.resume(throwing: DerivError.timeout)
            }
        }
    }

    private func send(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(str)) { _ in }
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let err):
                DispatchQueue.main.async { self.connectionState = .error(err.localizedDescription) }
            case .success(let message):
                if case let .string(text) = message { self.route(text) }
                self.receiveLoop()
            }
        }
    }

    private func route(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        // Resolve one-shot request first.
        if let id = json["req_id"] as? Int {
            lock.lock(); let w = waiters.removeValue(forKey: id); lock.unlock()
            if let w = w { w.resume(returning: json); return }
        }

        // Streaming updates by msg_type.
        let type = json["msg_type"] as? String
        switch type {
        case "tick":
            if let t = json["tick"] as? [String: Any], let sym = t["symbol"] as? String {
                let q = (t["quote"] as? Double) ?? Double((t["quote"] as? Int) ?? 0)
                DispatchQueue.main.async { self.prices[sym] = q }
            }
        case "balance":
            if let b = json["balance"] as? [String: Any] {
                let v = (b["balance"] as? Double) ?? Double((b["balance"] as? Int) ?? 0)
                DispatchQueue.main.async { self.balance = v; self.currency = b["currency"] as? String ?? self.currency }
            }
        case "proposal_open_contract":
            if let c = json["proposal_open_contract"] as? [String: Any] {
                self.updatePosition(c)
            }
        default:
            if let err = json["error"] as? [String: Any] {
                DispatchQueue.main.async { self.lastError = err["message"] as? String }
            }
        }
    }

    private func updatePosition(_ c: [String: Any]) {
        let cid = (c["contract_id"] as? Int) ?? Int((c["contract_id"] as? Double) ?? 0)
        guard cid != 0 else { return }
        func dbl(_ k: String) -> Double { (c[k] as? Double) ?? Double((c[k] as? Int) ?? 0) }
        let sold = (c["is_sold"] as? Int == 1) || (c["is_sold"] as? Bool == true)
        let pos = DerivPosition(
            id: cid,
            symbol: c["underlying"] as? String ?? c["symbol"] as? String ?? "?",
            contractType: c["contract_type"] as? String ?? "MULT",
            buyPrice: dbl("buy_price"),
            profit: dbl("profit"),
            isSold: sold
        )
        DispatchQueue.main.async {
            if sold { self.positions.removeValue(forKey: cid) }
            else { self.positions[cid] = pos }
        }
    }

    // MARK: - Parsing helpers

    private static func parseCandle(_ c: [String: Any]) -> Candle? {
        func d(_ k: String) -> Double? {
            if let v = c[k] as? Double { return v }
            if let v = c[k] as? Int { return Double(v) }
            if let v = c[k] as? String { return Double(v) }
            return nil
        }
        guard let o = d("open"), let h = d("high"), let l = d("low"), let cl = d("close") else { return nil }
        let epoch = (c["epoch"] as? Double) ?? Double((c["epoch"] as? Int) ?? 0)
        return Candle(timestamp: Date(timeIntervalSince1970: epoch),
                      open: o, high: h, low: l, close: cl, volume: d("volume") ?? 0)
    }

    private static func symbolFromShortcode(_ s: String) -> String? {
        // e.g. MULTUP_R_75_... -> R_75
        let parts = s.split(separator: "_")
        if parts.count >= 3, parts[0].uppercased().hasPrefix("MULT") { return "\(parts[1])_\(parts[2])" }
        return nil
    }
}
