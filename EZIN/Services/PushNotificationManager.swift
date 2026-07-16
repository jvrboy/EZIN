import Foundation
import UserNotifications
import Combine
import UIKit

/// Real push notification manager for EZIN trading signals and alerts.
/// Registers with APNs, schedules local notifications for signal events,
/// and handles incoming remote notifications.
@MainActor
final class PushNotificationManager: NSObject, ObservableObject {
    static let shared = PushNotificationManager()
    @Published var isEnabled = false
    @Published var deviceToken: String?

    private let center = UNUserNotificationCenter.current()
    private var cancellables = Set<AnyCancellable>()

    private override init() {
        super.init()
        center.delegate = self
        checkAuthorizationStatus()
    }

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            await MainActor.run { self.isEnabled = granted }
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
            return granted
        } catch {
            return false
        }
    }

    func checkAuthorizationStatus() {
        center.getNotificationSettings { [weak self] settings in
            Task { @MainActor in
                self?.isEnabled = settings.authorizationStatus == .authorized
            }
        }
    }

    // MARK: - Local Signal Notifications

    /// Schedule a local push when a high-confidence signal is generated.
    func notifySignalGenerated(_ signal: TradingSignal) {
        guard isEnabled, SettingsStore.shared.pushAlerts else { return }
        // Only notify for strong signals (>= 75 confidence) to avoid spam.
        guard signal.confidence >= 75 else { return }

        let content = UNMutableNotificationContent()
        content.title = "EZIN Signal: \(signal.displayPair)"
        content.body = "\(signal.isBuy ? "BUY" : "SELL") signal at \(fmt(signal.entry)) — Confidence \(Int(signal.confidence))%"
        content.sound = .default
        content.userInfo = ["type": "signal", "symbol": signal.symbol, "direction": signal.isBuy ? "buy" : "sell"]
        content.badge = 1

        let request = UNNotificationRequest(identifier: "signal-\(signal.id.uuidString)", content: content, trigger: nil)
        center.add(request)
    }

    /// Notify when a take profit or stop loss level is hit.
    func notifyLevelHit(symbol: String, level: Double, isTakeProfit: Bool) {
        guard isEnabled, SettingsStore.shared.pushAlerts else { return }

        let content = UNMutableNotificationContent()
        content.title = "EZIN: \(isTakeProfit ? "Take Profit" : "Stop Loss") Hit"
        content.body = "\(DerivSymbols.display(symbol)) reached \(fmt(level))"
        content.sound = isTakeProfit ? .default : UNNotificationSound(named: UNNotificationSoundName("failure.aiff"))
        content.userInfo = ["type": "level_hit", "symbol": symbol, "level_type": isTakeProfit ? "tp" : "sl"]

        let request = UNNotificationRequest(identifier: "level-\(symbol)-\(isTakeProfit ? "tp" : "sl")-\(Date().timeIntervalSince1970)", content: content, trigger: nil)
        center.add(request)
    }

    /// Notify when market regime changes significantly.
    func notifyRegimeChange(symbol: String, from oldRegime: String, to newRegime: String) {
        guard isEnabled, SettingsStore.shared.pushAlerts else { return }

        let content = UNMutableNotificationContent()
        content.title = "EZIN: Regime Shift Detected"
        content.body = "\(DerivSymbols.display(symbol)): \(oldRegime) → \(newRegime)"
        content.sound = .default
        content.userInfo = ["type": "regime_change", "symbol": symbol, "regime": newRegime]

        let request = UNNotificationRequest(identifier: "regime-\(symbol)-\(Date().timeIntervalSince1970)", content: content, trigger: nil)
        center.add(request)
    }

    /// Notify on WebSocket disconnect so user knows connection is lost.
    func notifyConnectionLost() {
        guard isEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "EZIN: Connection Lost"
        content.body = "Live market data disconnected. Attempting to reconnect…"
        content.sound = .default
        content.userInfo = ["type": "connection"]

        let request = UNNotificationRequest(identifier: "connection-lost", content: content, trigger: nil)
        center.add(request)
    }

    /// Notify on successful reconnection.
    func notifyConnectionRestored() {
        guard isEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "EZIN: Reconnected"
        content.body = "Live market data connection restored."
        content.userInfo = ["type": "connection"]

        let request = UNNotificationRequest(identifier: "connection-restored", content: content, trigger: nil)
        center.add(request)
    }

    // MARK: - Badge

    func clearBadge() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        if #available(iOS 16.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(0)
        } else {
            UIApplication.shared.applicationIconBadgeNumber = 0
        }
    }

    // MARK: - Private

    private func fmt(_ v: Double) -> String {
        v > 100 ? String(format: "%.1f", v) : String(format: "%.4f", v)
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension PushNotificationManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        // Handle notification tap — could deep-link to relevant tab.
        if let type = userInfo["type"] as? String {
            print("[PushNotificationManager] User tapped notification: \(type)")
        }
    }
}
