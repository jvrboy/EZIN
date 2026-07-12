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

/// Deriv WebSocket client (v3 API).
/// Uses the default public app id (1089) unless the user configures their own.
final class DerivClient: NSObject, ObservableObject {
    static let defaultAppID = 1089
    static let endpoint = "wss://ws.derivws.com/websockets/v3"

    @Published var connectionState: DerivConnectionState = .disconnected

    private var task: URLSessionWebSocketTask?
    private lazy var session = URLSession(configuration: .default)
    private var appID = DerivClient.defaultAppID
    private var token: String?
    private var reqID = 0

    /// Continuations for candle history requests keyed by req_id.
    private var historyWaiters: [Int: CheckedContinuation<[Candle], Error>] = [:]

    func connect(appID: Int?, token: String?) async {
        self.appID = appID ?? DerivClient.defaultAppID
        self.token = token
        await MainActor.run { self.connectionState = .connecting }

        guard let url = URL(string: "\(DerivClient.endpoint)?app_id=\(self.appID)") else {
            await MainActor.run { self.connectionState = .error("bad url") }; return
        }
        task?.cancel(with: .goingAway, reason: nil)
        task = session.webSocketTask(with: url)
        task?.resume()
        receiveLoop()

        // Authorize if a token is present, else public data still works.
        if let token = token, !token.isEmpty {
            send(["authorize": token])
        }
        await MainActor.run { self.connectionState = .connected }
    }

    func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        connectionState = .disconnected
    }

    /// Fetch historical candles for a symbol/timeframe.
    func candles(symbol: String, timeframe: Timeframe, count: Int = 200) async throws -> [Candle] {
        reqID += 1
        let id = reqID
        let payload: [String: Any] = [
            "ticks_history": symbol,
            "adjust_start_time": 1,
            "count": count,
            "end": "latest",
            "granularity": timeframe.granularity,
            "style": "candles",
            "req_id": id
        ]
        return try await withCheckedThrowingContinuation { cont in
            historyWaiters[id] = cont
            send(payload)
            // Timeout guard.
            DispatchQueue.global().asyncAfter(deadline: .now() + 15) { [weak self] in
                if let waiter = self?.historyWaiters.removeValue(forKey: id) {
                    waiter.resume(throwing: DerivError.timeout)
                }
            }
        }
    }

    // MARK: - Internals

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
                if case let .string(text) = message { self.handle(text) }
                self.receiveLoop()
            }
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        if let id = json["req_id"] as? Int, let waiter = historyWaiters.removeValue(forKey: id) {
            if let candlesJSON = json["candles"] as? [[String: Any]] {
                waiter.resume(returning: candlesJSON.compactMap(Self.parseCandle))
            } else if let err = json["error"] as? [String: Any] {
                waiter.resume(throwing: DerivError.api(err["message"] as? String ?? "unknown"))
            } else {
                waiter.resume(returning: [])
            }
        }
    }

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
}

enum DerivError: Error { case timeout, api(String) }
