// MARK: - EditableReceiptViewModel.swift

import SwiftUI
import Combine

/// Editable representation of a receipt line item for two-way binding.
struct EditableReceiptItem: Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String = ""
    var priceString: String = "0.00"
    var quantityString: String = "1"
    var isShared: Bool = false

    var price: Double {
        Double(priceString.replacingOccurrences(of: "$", with: "").trimmingCharacters(in: .whitespaces)) ?? 0.0
    }

    var quantity: Int {
        max(1, Int(quantityString.trimmingCharacters(in: .whitespaces)) ?? 1)
    }

    func toReceiptItem() -> ReceiptItem {
        ReceiptItem(
            id: id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            price: price,
            quantity: quantity,
            isShared: isShared
        )
    }

    static func from(item: ReceiptItem) -> EditableReceiptItem {
        EditableReceiptItem(
            id: item.id,
            name: item.name,
            priceString: String(format: "%.2f", item.price),
            quantityString: String(item.quantity),
            isShared: item.isShared
        )
    }
}

/// Drives the black-and-white editable receipt form with immediate debounced Vapor API PATCH synchronization.
@MainActor
final class EditableReceiptViewModel: ObservableObject {
    @Published var receiptId: UUID?
    @Published var referenceId: String
    @Published var items: [EditableReceiptItem] = []
    @Published var subtotalString: String = "0.00"
    @Published var taxString: String = "0.00"
    @Published var tipString: String = "0.00"
    @Published var totalString: String = "0.00"
    @Published var selectedCategory: ReceiptCategory?

    @Published var isSyncing: Bool = false
    @Published var lastSyncedAt: Date?
    @Published var validationReport: ReceiptValidationReport?
    @Published var shareableURL: String?
    @Published var splitSession: SplitSessionResponse?
    @Published var errorMessage: String?

    private var patchTask: Task<Void, Never>?
    private var isInitializing: Bool = true

    var subtotalValue: Double {
        Double(subtotalString.replacingOccurrences(of: "$", with: "").trimmingCharacters(in: .whitespaces)) ?? 0.0
    }

    var taxValue: Double {
        Double(taxString.replacingOccurrences(of: "$", with: "").trimmingCharacters(in: .whitespaces)) ?? 0.0
    }

    var tipValue: Double {
        Double(tipString.replacingOccurrences(of: "$", with: "").trimmingCharacters(in: .whitespaces)) ?? 0.0
    }

    var totalValue: Double {
        Double(totalString.replacingOccurrences(of: "$", with: "").trimmingCharacters(in: .whitespaces)) ?? 0.0
    }

    var computedItemsSubtotal: Double {
        items.reduce(0.0) { $0 + ($1.price * Double($1.quantity)) }
    }

    var computedGrandTotal: Double {
        let base = subtotalValue > 0 ? subtotalValue : computedItemsSubtotal
        return base + taxValue + tipValue
    }

    var asExtractedReceiptResponse: ExtractedReceiptResponse {
        ExtractedReceiptResponse(
            id: receiptId,
            referenceId: referenceId,
            items: items.map { $0.toReceiptItem() },
            subtotal: subtotalValue,
            tax: taxValue,
            tip: tipValue,
            total: totalValue,
            category: selectedCategory?.rawValue
        )
    }

    // MARK: - Initializers

    /// Initialize for AI Correction with pre-extracted receipt data.
    init(receipt: ExtractedReceiptResponse) {
        self.receiptId = receipt.id
        self.referenceId = receipt.referenceId
        self.items = receipt.items.map { EditableReceiptItem.from(item: $0) }
        self.subtotalString = String(format: "%.2f", receipt.subtotal)
        self.taxString = String(format: "%.2f", receipt.tax)
        self.tipString = String(format: "%.2f", receipt.tip)
        self.totalString = String(format: "%.2f", receipt.total)
        self.selectedCategory = receipt.parsedCategory

        self.isInitializing = false

        // Run initial server validation & link fetch
        if let id = receipt.id {
            Task {
                await self.patchToServerImmediate(id: id)
            }
        }
    }

    /// Initialize for blank manual entry from scratch.
    init() {
        self.receiptId = nil
        self.referenceId = "manual-\(UUID().uuidString.prefix(8))"
        self.items = [
            EditableReceiptItem(name: "Coffee", priceString: "4.50", quantityString: "1", isShared: false),
            EditableReceiptItem(name: "Croissant", priceString: "3.75", quantityString: "1", isShared: false)
        ]
        self.subtotalString = "8.25"
        self.taxString = "0.75"
        self.tipString = "1.50"
        self.totalString = "10.50"
        self.selectedCategory = .everyday

        self.isInitializing = false

        Task {
            await self.createInitialManualReceipt()
        }
    }

    // MARK: - Item Manipulations

    func addItem() {
        let newItem = EditableReceiptItem(
            name: "",
            priceString: "0.00",
            quantityString: "1",
            isShared: false
        )
        items.append(newItem)
        autoRecalculateTotals(silent: true)
        scheduleDebouncedPatch()
    }

    func removeItem(id: UUID) {
        items.removeAll { $0.id == id }
        autoRecalculateTotals(silent: true)
        scheduleDebouncedPatch()
    }

    func duplicateItem(id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        let duplicate = EditableReceiptItem(
            name: item.name + " (Copy)",
            priceString: item.priceString,
            quantityString: item.quantityString,
            isShared: item.isShared
        )
        items.append(duplicate)
        autoRecalculateTotals(silent: true)
        scheduleDebouncedPatch()
    }

    func autoRecalculateTotals(silent: Bool = false) {
        let sumSubtotal = computedItemsSubtotal
        subtotalString = String(format: "%.2f", sumSubtotal)
        let total = sumSubtotal + taxValue + tipValue
        totalString = String(format: "%.2f", total)

        if !silent {
            scheduleDebouncedPatch()
        }
    }

    func setCategory(_ category: ReceiptCategory?) {
        self.selectedCategory = category
        scheduleDebouncedPatch()
    }

    // MARK: - Debounced Immediate PATCH

    /// Debounces field updates by 300ms before sending PATCH to Vapor backend.
    func scheduleDebouncedPatch() {
        guard !isInitializing else { return }
        isSyncing = true
        errorMessage = nil

        patchTask?.cancel()
        patchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
            guard !Task.isCancelled else { return }
            await self.performPatch()
        }
    }

    /// Performs the network PATCH or creation request.
    private func performPatch() async {
        let payload = PatchReceiptPayload(
            items: items.map { $0.toReceiptItem() },
            subtotal: subtotalValue,
            tax: taxValue,
            tip: tipValue,
            total: totalValue,
            category: selectedCategory?.rawValue,
            referenceId: referenceId
        )

        do {
            if let id = receiptId {
                let response = try await ReceiptService.patchReceipt(id: id, payload: payload)
                self.validationReport = response.validation
                self.shareableURL = response.shareableURL
                self.splitSession = response.splitSession
                self.lastSyncedAt = Date()
                self.isSyncing = false
            } else {
                let created = try await ReceiptService.createManualReceipt(payload: payload)
                self.receiptId = created.id
                if let newId = created.id {
                    let response = try await ReceiptService.patchReceipt(id: newId, payload: payload)
                    self.validationReport = response.validation
                    self.shareableURL = response.shareableURL
                    self.splitSession = response.splitSession
                }
                self.lastSyncedAt = Date()
                self.isSyncing = false
            }
        } catch {
            self.errorMessage = "Sync failed: \(error.localizedDescription)"
            self.isSyncing = false
        }
    }

    private func patchToServerImmediate(id: UUID) async {
        isSyncing = true
        let payload = PatchReceiptPayload(
            items: items.map { $0.toReceiptItem() },
            subtotal: subtotalValue,
            tax: taxValue,
            tip: tipValue,
            total: totalValue,
            category: selectedCategory?.rawValue,
            referenceId: referenceId
        )
        do {
            let response = try await ReceiptService.patchReceipt(id: id, payload: payload)
            self.validationReport = response.validation
            self.shareableURL = response.shareableURL
            self.splitSession = response.splitSession
            self.lastSyncedAt = Date()
            self.isSyncing = false
        } catch {
            self.errorMessage = "Validation error: \(error.localizedDescription)"
            self.isSyncing = false
        }
    }

    private func createInitialManualReceipt() async {
        isSyncing = true
        let payload = PatchReceiptPayload(
            items: items.map { $0.toReceiptItem() },
            subtotal: subtotalValue,
            tax: taxValue,
            tip: tipValue,
            total: totalValue,
            category: selectedCategory?.rawValue,
            referenceId: referenceId
        )
        do {
            let created = try await ReceiptService.createManualReceipt(payload: payload)
            self.receiptId = created.id
            if let newId = created.id {
                let response = try await ReceiptService.patchReceipt(id: newId, payload: payload)
                self.validationReport = response.validation
                self.shareableURL = response.shareableURL
                self.splitSession = response.splitSession
            }
            self.lastSyncedAt = Date()
            self.isSyncing = false
        } catch {
            self.errorMessage = "Creation error: \(error.localizedDescription)"
            self.isSyncing = false
        }
    }
}
