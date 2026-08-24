import Vapor
import Fluent
import Foundation

struct ReceiptController {
    
    // MARK: - Handlers
    
    @Sendable
    func upload(req: Request) async throws -> UploadResponse {
        // Decode the multipart form-data
        let input: ReceiptUpload
        do {
            input = try req.content.decode(ReceiptUpload.self)
        } catch {
            req.logger.warning("Failed to decode receipt upload: \(error)")
            throw Abort(.badRequest, reason: "Invalid upload format or missing 'image' field.")
        }
        
        let imageFile = input.image
        
        // Basic validation: ensure we have data
        guard imageFile.data.readableBytes > 0 else {
            throw Abort(.badRequest, reason: "Uploaded image is empty.")
        }
        
        // Determine storage path
        guard let storageDir = req.application.storage[ReceiptStorageKey.self] else {
            throw Abort(.internalServerError, reason: "Storage configuration missing.")
        }
        
        // Generate temporary reference identifier
        let referenceId = UUID().uuidString
        let fileName = "\(referenceId).jpg"
        
        let fileURL = URL(fileURLWithPath: storageDir).appendingPathComponent(fileName)
        
        // Write bytes to disk
        do {
            let data = Data(buffer: imageFile.data)
            try data.write(to: fileURL)
            req.logger.info("Successfully saved receipt to \(fileURL.path)")
        } catch {
            req.logger.error("Failed to write receipt image to disk: \(error)")
            throw Abort(.internalServerError, reason: "Failed to save the receipt image.")
        }
        
        return UploadResponse(referenceId: referenceId)
    }
    
    /// Triggers AI extraction on a previously uploaded receipt image.
    @Sendable
    func extract(req: Request) async throws -> ExtractedReceipt {
        guard let referenceId = req.parameters.get("referenceId") else {
            throw Abort(.badRequest, reason: "Missing referenceId parameter.")
        }
        
        // Check if already extracted
        if let existing = try await ExtractedReceipt.query(on: req.db)
            .filter(\.$referenceId == referenceId)
            .first() {
            return existing
        }
        
        // Run AI extraction
        let receipt = try await ExtractionService.extract(
            referenceId: referenceId,
            app: req.application
        )
        
        // Save to database
        try await receipt.save(on: req.db)
        
        req.logger.info("Extracted and saved receipt for referenceId: \(referenceId)")
        return receipt
    }
    
    /// Retrieves a previously extracted receipt by its database ID.
    @Sendable
    func getResult(req: Request) async throws -> ExtractedReceipt {
        guard let id = req.parameters.get("id", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid or missing receipt ID.")
        }
        
        guard let receipt = try await ExtractedReceipt.find(id, on: req.db) else {
            throw Abort(.notFound, reason: "No extracted receipt found with ID: \(id)")
        }
        
        return receipt
    }

    /// Creates a manually entered receipt directly into the database with live exchange rate conversion.
    @Sendable
    func createManual(req: Request) async throws -> ExtractedReceipt {
        let input = try req.content.decode(CreateManualReceiptRequest.self)

        let statedSubtotal = input.subtotal ?? 0
        let statedTax = input.tax ?? 0
        let statedTip = input.tip ?? 0
        let statedTotal = input.total ?? 0

        let validation = ReceiptValidator.validate(
            items: input.items,
            subtotal: statedSubtotal,
            tax: statedTax,
            tip: statedTip,
            total: statedTotal
        )

        let effectiveSubtotal = statedSubtotal > 0 ? statedSubtotal : validation.computedSubtotal
        let effectiveTotal = statedTotal > 0 ? statedTotal : validation.computedTotal
        let refId = input.referenceId ?? "manual-\(UUID().uuidString.prefix(8))"

        let currency = input.currency ?? "USD"
        let targetCurrency = input.targetCurrency ?? "USD"
        let rate = await ExchangeRateService.getRate(from: currency, to: targetCurrency, client: req.client)
        let convertedTotal = (effectiveTotal * rate * 100).rounded() / 100

        let receipt = ExtractedReceipt(
            referenceId: refId,
            items: input.items,
            subtotal: effectiveSubtotal,
            tax: statedTax,
            tip: statedTip,
            total: effectiveTotal,
            category: input.category,
            currency: currency,
            targetCurrency: targetCurrency,
            exchangeRate: rate,
            convertedTotal: convertedTotal
        )

        try await receipt.save(on: req.db)
        req.logger.info("Manually created receipt \(receipt.id?.uuidString ?? "?") with \(input.items.count) items, total \(effectiveTotal) \(currency) (\(convertedTotal) \(targetCurrency))")
        return receipt
    }

    /// Patches an extracted receipt with manual edits/corrections, re-runs validation, and updates any active split session.
    @Sendable
    func patchReceipt(req: Request) async throws -> PatchReceiptResponse {
        guard let id = req.parameters.get("id", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid or missing receipt ID.")
        }

        let input = try req.content.decode(PatchReceiptRequest.self)

        guard let receipt = try await ExtractedReceipt.find(id, on: req.db) else {
            throw Abort(.notFound, reason: "No extracted receipt found with ID: \(id)")
        }

        // Overwrite fields
        if let newItems = input.items {
            receipt.items = newItems
        }
        if let newSubtotal = input.subtotal {
            receipt.subtotal = newSubtotal
        }
        if let newTax = input.tax {
            receipt.tax = newTax
        }
        if let newTip = input.tip {
            receipt.tip = newTip
        }
        if let newTotal = input.total {
            receipt.total = newTotal
        }
        if let newCategory = input.category {
            receipt.category = newCategory
        }
        if let newRef = input.referenceId {
            receipt.referenceId = newRef
        }

        let currency = input.currency ?? receipt.currency ?? "USD"
        let targetCurrency = input.targetCurrency ?? receipt.targetCurrency ?? "USD"
        let rate = await ExchangeRateService.getRate(from: currency, to: targetCurrency, client: req.client)
        receipt.currency = currency
        receipt.targetCurrency = targetCurrency
        receipt.exchangeRate = rate
        receipt.convertedTotal = (receipt.total * rate * 100).rounded() / 100

        // Re-run authoritative validation
        let validation = ReceiptValidator.validate(
            items: receipt.items,
            subtotal: receipt.subtotal,
            tax: receipt.tax,
            tip: receipt.tip,
            total: receipt.total
        )

        // Save updated receipt
        try await receipt.update(on: req.db)
        req.logger.info("Receipt \(id) patched: \(receipt.items.count) items, subtotal \(receipt.subtotal), total \(receipt.total) \(currency) (@ rate \(rate) \(targetCurrency)). Valid: \(validation.isValid), Math: \(validation.isMathConsistent)")

        // Re-calculate linked SplitSession if active, to immediately synchronize the shareable link state
        var splitResponse: SplitSessionResponse? = nil
        var shareableURL: String? = nil

        if let session = try await SplitSession.query(on: req.db).filter(\.$receiptId == id).first() {
            let method = session.splitMethod.flatMap(SplitMethod.init(rawValue:)) ?? .itemized
            session.currency = currency
            session.targetCurrency = targetCurrency
            session.exchangeRate = rate

            // Recompute authoritative per-person balances with updated receipt items and taxes
            let updatedBalances = SplitCalculator.calculate(
                method: method,
                items: receipt.items,
                receiptSubtotal: receipt.subtotal,
                tax: receipt.tax,
                tip: receipt.tip,
                total: receipt.total,
                currency: currency,
                targetCurrency: targetCurrency,
                exchangeRate: rate,
                participants: session.participants,
                assignments: session.assignments,
                percentageAllocations: session.percentageAllocations,
                shareAllocations: session.shareAllocations,
                exactAllocations: session.exactAllocations
            )

            // Preserve existing payment/settlement flags for participants
            var mergedBalances = updatedBalances
            for i in mergedBalances.indices {
                if let oldBalance = session.balances.first(where: { $0.participantId == mergedBalances[i].participantId }) {
                    mergedBalances[i].isPaid = oldBalance.isPaid
                    mergedBalances[i].paidAt = oldBalance.paidAt
                    mergedBalances[i].paymentMethod = oldBalance.paymentMethod
                    mergedBalances[i].settlementStatus = oldBalance.settlementStatus
                }
            }

            session.balances = mergedBalances
            if let cat = receipt.category {
                session.category = cat
            }

            try await session.update(on: req.db)

            let baseURL = Environment.get("BASE_URL") ?? "http://localhost:8080"
            let token = session.shareToken ?? session.id!.uuidString
            let url = "\(baseURL)/s/\(token)"
            shareableURL = url

            splitResponse = SplitSessionResponse(
                id: session.id!,
                receiptId: session.receiptId,
                participants: session.participants,
                splitMethod: method,
                assignments: session.assignments,
                percentageAllocations: session.percentageAllocations,
                shareAllocations: session.shareAllocations,
                exactAllocations: session.exactAllocations,
                balances: session.balances,
                receiptTotal: receipt.total,
                currency: currency,
                targetCurrency: targetCurrency,
                exchangeRate: rate,
                convertedReceiptTotal: receipt.convertedTotal,
                category: session.category,
                shareableURL: url,
                createdAt: session.createdAt
            )

            req.logger.info("Synchronized split session \(session.id?.uuidString ?? "") balances for shareable URL \(url)")
        }

        let message = validation.isMathConsistent
            ? "Receipt updated and validated successfully."
            : "Receipt updated with \(validation.warnings.count) validation notice(s)."

        return PatchReceiptResponse(
            success: validation.isValid,
            receipt: receipt,
            validation: validation,
            splitSession: splitResponse,
            shareableURL: shareableURL,
            message: message
        )
    }

    /// Updates the optional category tag on an extracted receipt.
    @Sendable
    func updateCategory(req: Request) async throws -> ExtractedReceipt {
        guard let id = req.parameters.get("id", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid or missing receipt ID.")
        }

        let input = try req.content.decode(UpdateCategoryRequest.self)

        guard let receipt = try await ExtractedReceipt.find(id, on: req.db) else {
            throw Abort(.notFound, reason: "No extracted receipt found with ID: \(id)")
        }

        receipt.category = input.category
        try await receipt.update(on: req.db)

        // Also sync category to linked split sessions if any
        if let session = try await SplitSession.query(on: req.db).filter(\.$receiptId == id).first() {
            session.category = input.category
            try await session.update(on: req.db)
        }

        req.logger.info("Updated category for receipt \(id) to '\(input.category ?? "none")'")
        return receipt
    }

    /// Lists receipts with optional category and keyword search query parameters.
    @Sendable
    func list(req: Request) async throws -> [ExtractedReceipt] {
        let query = try? req.query.decode(HistoryFilterQuery.self)
        let categoryFilter = query?.category?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let searchTerm = query?.search?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        var dbQuery = ExtractedReceipt.query(on: req.db)

        if let category = categoryFilter, !category.isEmpty, category != "all" {
            dbQuery = dbQuery.filter(\.$category == category)
        }

        var receipts = try await dbQuery.sort(\.$createdAt, .descending).all()

        if let search = searchTerm, !search.isEmpty {
            receipts = receipts.filter { receipt in
                let matchesRef = receipt.referenceId.lowercased().contains(search)
                let matchesItems = receipt.items.contains { $0.name.lowercased().contains(search) }
                let matchesTotal = String(format: "%.2f", receipt.total).contains(search)
                let matchesCategory = receipt.category?.lowercased().contains(search) ?? false
                let matchesCurrency = (receipt.currency ?? "USD").lowercased().contains(search)
                return matchesRef || matchesItems || matchesTotal || matchesCategory || matchesCurrency
            }
        }

        return receipts
    }

    /// Streams exported receipts as pure-Swift CSV or PDF format.
    @Sendable
    func export(req: Request) async throws -> Response {
        let receipts = try await list(req: req)
        let query = try? req.query.decode(HistoryFilterQuery.self)
        let format = query?.format?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "csv"
        let category = query?.category?.trimmingCharacters(in: .whitespacesAndNewlines)
        let search = query?.search?.trimmingCharacters(in: .whitespacesAndNewlines)

        let items: [HistoryItemDTO] = receipts.map { receipt in
            let title = receipt.items.first?.name ?? "Receipt (\(receipt.referenceId.prefix(6)))"
            let itemsSummary = receipt.items.prefix(4).map(\.name)
            return HistoryItemDTO(
                id: receipt.id ?? UUID(),
                receiptId: receipt.id,
                title: title,
                category: receipt.category,
                total: receipt.total,
                currency: receipt.currency ?? "USD",
                convertedTotal: receipt.convertedTotal ?? receipt.total,
                targetCurrency: receipt.targetCurrency ?? receipt.currency ?? "USD",
                exchangeRate: receipt.exchangeRate ?? 1.0,
                createdAt: receipt.createdAt,
                participantCount: 0,
                isSettled: false,
                shareableURL: nil,
                itemsSummary: Array(itemsSummary)
            )
        }

        if format == "pdf" {
            return ExportStreamingService.streamPDF(
                items: items,
                categoryFilter: category,
                searchQuery: search,
                req: req
            )
        } else {
            return ExportStreamingService.streamCSV(
                items: items,
                req: req
            )
        }
    }
}
