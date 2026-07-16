import Foundation
import BackgroundTasks

/// Best-effort iOS background refresh. iOS does not permit arbitrary 24/7 sockets while
/// suspended, so this manager combines (1) aggressive foreground auto-refresh/reconnect,
/// (2) system background fetch/processing windows, and (3) push notifications for signal
/// alerts. It keeps the backend warm without violating App Store background rules.
@MainActor
final class BackgroundRefreshManager {
    static let shared = BackgroundRefreshManager()
    private init() {}

    private let refreshID = "com.ezin.refresh"
    private let processingID = "com.ezin.processing"
    private weak var app: AppState?
    private var configured = false

    func configure(app: AppState) {
        guard !configured else { return }
        configured = true
        self.app = app
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshID, using: nil) { task in
            Task { @MainActor in
                await self.handleRefresh(task as? BGAppRefreshTask)
            }
        }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: processingID, using: nil) { task in
            Task { @MainActor in
                await self.handleProcessing(task as? BGProcessingTask)
            }
        }
        scheduleRefresh()
        scheduleProcessing()
    }

    func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    func scheduleProcessing() {
        let request = BGProcessingTaskRequest(identifier: processingID)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func handleRefresh(_ task: BGAppRefreshTask?) async {
        scheduleRefresh()
        guard let app else { task?.setTaskCompleted(success: false); return }
        var expired = false
        task?.expirationHandler = { expired = true }
        await app.refreshRealtime()
        await app.refreshHistory()
        task?.setTaskCompleted(success: !expired)
    }

    private func handleProcessing(_ task: BGProcessingTask?) async {
        scheduleProcessing()
        guard let app else { task?.setTaskCompleted(success: false); return }
        var expired = false
        task?.expirationHandler = { expired = true }
        await app.refreshRealtime()
        if app.deriv.authorized { await app.refreshHistory() }
        app.signalPerformance.updatePrices(app.deriv.prices)
        task?.setTaskCompleted(success: !expired)
    }
}
