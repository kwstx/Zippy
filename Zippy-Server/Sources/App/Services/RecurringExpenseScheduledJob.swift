import Vapor
import Fluent
import Foundation

/// Background worker managing continuous periodic scheduled jobs that scan and clone due recurring expenses.
final class RecurringExpenseScheduledJob: @unchecked Sendable {
    private let app: Application
    private var isRunning: Bool = false
    private var task: Task<Void, Never>?

    init(app: Application) {
        self.app = app
    }

    /// Starts the periodic scheduled cron job loop in the background.
    func start() {
        guard !isRunning else { return }
        isRunning = true

        let intervalSeconds = Environment.get("RECURRING_SCAN_INTERVAL_SECONDS").flatMap(UInt64.init) ?? 60
        let nanoseconds = intervalSeconds * 1_000_000_000

        app.logger.info("[SCHEDULER] Recurring expense scheduled cron job started (Interval: \(intervalSeconds)s)")

        task = Task.detached(priority: .background) { [weak self] in
            guard let self = self else { return }

            // Initial brief delay after boot before first run
            try? await Task.sleep(nanoseconds: 3_000_000_000)

            while !Task.isCancelled && self.isRunning {
                do {
                    _ = try await RecurringExpenseService.processDueTemplates(
                        db: self.app.db,
                        logger: self.app.logger,
                        client: self.app.client
                    )
                } catch {
                    self.app.logger.error("[SCHEDULER] Recurring expense cron encountered error: \(error)")
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
        app.logger.info("[SCHEDULER] Recurring expense scheduled cron job stopped.")
    }
}

struct RecurringExpenseJobKey: StorageKey {
    typealias Value = RecurringExpenseScheduledJob
}
