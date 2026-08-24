import Vapor
import Fluent
import Foundation

/// Background worker managing continuous periodic scheduled jobs scanning unsettled records.
final class PaymentReminderScheduledJob: @unchecked Sendable {
    private let app: Application
    private var isRunning: Bool = false
    private var task: Task<Void, Never>?

    init(app: Application) {
        self.app = app
    }

    /// Starts the periodic scheduled job loop in the background.
    func start() {
        guard !isRunning else { return }
        isRunning = true

        let intervalSeconds = Environment.get("REMINDER_SCAN_INTERVAL_SECONDS").flatMap(UInt64.init) ?? 3600
        let nanoseconds = intervalSeconds * 1_000_000_000

        app.logger.info("[SCHEDULER] Payment reminder scheduled job started (Interval: \(intervalSeconds)s)")

        task = Task.detached(priority: .background) { [weak self] in
            guard let self = self else { return }

            // Initial brief delay after boot before first run
            try? await Task.sleep(nanoseconds: 5_000_000_000)

            while !Task.isCancelled && self.isRunning {
                do {
                    self.app.logger.info("[SCHEDULER] Running periodic unsettled payment scan...")
                    _ = try await PaymentReminderService.scanAndDispatchReminders(
                        db: self.app.db,
                        logger: self.app.logger
                    )
                } catch {
                    self.app.logger.error("[SCHEDULER] Unsettled payment scan encountered error: \(error)")
                }

                do {
                    try await Task.sleep(nanoseconds: nanoseconds)
                } catch {
                    break
                }
            }
        }
    }

    /// Stops the scheduled background job.
    func stop() {
        isRunning = false
        task?.cancel()
        task = nil
        app.logger.info("[SCHEDULER] Payment reminder scheduled job stopped.")
    }
}

struct PaymentReminderJobKey: StorageKey {
    typealias Value = PaymentReminderScheduledJob
}
