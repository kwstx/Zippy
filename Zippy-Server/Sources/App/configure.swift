import Vapor
import Fluent
import FluentPostgresDriver
import Foundation

// configures your application
public func configure(_ app: Application) async throws {
    // Set max body size for uploads (e.g., 10MB)
    app.routes.defaultMaxBodySize = "10mb"
    
    // Determine storage path from environment or use default
    let storagePath = Environment.get("RECEIPT_STORAGE_PATH") ?? "./Storage/Receipts/"
    
    // Ensure the directory exists
    let fm = FileManager.default
    if !fm.fileExists(atPath: storagePath) {
        do {
            try fm.createDirectory(atPath: storagePath, withIntermediateDirectories: true, attributes: nil)
            app.logger.info("Created storage directory at \(storagePath)")
        } catch {
            app.logger.error("Failed to create storage directory at \(storagePath): \(error)")
            throw error
        }
    } else {
        app.logger.info("Using existing storage directory at \(storagePath)")
    }
    
    // Store configuration in app.storage for easy access in controllers
    app.storage[ReceiptStorageKey.self] = storagePath
    
    // Configure PostgreSQL
    if let databaseURL = Environment.get("DATABASE_URL") {
        try app.databases.use(
            .postgres(url: databaseURL),
            as: .psql
        )
    } else {
        app.databases.use(
            .postgres(
                hostname: Environment.get("DB_HOST") ?? "localhost",
                port: Environment.get("DB_PORT").flatMap(Int.init) ?? 5432,
                username: Environment.get("DB_USER") ?? "zippy",
                password: Environment.get("DB_PASSWORD") ?? "zippy",
                database: Environment.get("DB_NAME") ?? "zippy"
            ),
            as: .psql
        )
    }
    
    // Register migrations
    app.migrations.add(CreateExtractedReceipt())
    app.migrations.add(CreateSplitSession())
    app.migrations.add(AddCategoryMigration())
    app.migrations.add(AddSplitMethodsMigration())
    app.migrations.add(CreatePersistentGroupMigration())
    app.migrations.add(CreateLedgerEventMigration())
    app.migrations.add(AddMultiCurrencySupportMigration())
    app.migrations.add(CreatePaymentReminderLogMigration())
    app.migrations.add(CreateRecurringExpenseTemplateMigration())
    app.migrations.add(CreateSubscriptionRecordMigration())
    
    // Auto-migrate in development
    try await app.autoMigrate()

    // Start background scheduled job for unsettled payment tracking & reminders
    let reminderJob = PaymentReminderScheduledJob(app: app)
    app.storage[PaymentReminderJobKey.self] = reminderJob
    reminderJob.start()

    // Start background scheduled cron job for recurring expense template cloning
    let recurringJob = RecurringExpenseScheduledJob(app: app)
    app.storage[RecurringExpenseJobKey.self] = recurringJob
    recurringJob.start()

    // register routes
    try routes(app)
}

struct ReceiptStorageKey: StorageKey {
    typealias Value = String
}
