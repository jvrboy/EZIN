import Foundation
import Combine

/// Persists app-generated signals on-device so the History tab shows real-time
/// generated signals even when no Deriv API token is connected.
final class SignalHistoryStore: ObservableObject {
    static let shared = SignalHistoryStore()
    @Published var signals: [TradingSignal] = []
    private let file = "signal_history.json"
    private let maxItems = 300

    private init() {
        signals = FileStore.shared.read([TradingSignal].self, from: file, in: FileStore.shared.dataDir) ?? []
    }

    /// Record newly emitted signals, de-duplicating repeats of the same symbol/direction
    /// within a two-minute window so the log stays clean.
    func record(_ newSignals: [TradingSignal]) {
        guard !newSignals.isEmpty else { return }
        var changed = false
        for s in newSignals {
            let dup = signals.first {
                $0.symbol == s.symbol && $0.type == s.type &&
                abs($0.createdAt.timeIntervalSince(s.createdAt)) < 120
            }
            if dup == nil { signals.insert(s, at: 0); changed = true }
        }
        if signals.count > maxItems { signals = Array(signals.prefix(maxItems)) }
        if changed { save() }
    }

    func clear() { signals = []; save() }

    private func save() { FileStore.shared.write(signals, to: file, in: FileStore.shared.dataDir) }
}
