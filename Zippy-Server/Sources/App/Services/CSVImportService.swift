import Vapor
import Fluent
import Foundation

/// Pure-Swift CSV parsing and ingestion service.
/// Parses expense data exported from external tools (Splitwise, Mint, YNAB, Expensify, bank exports, Zippy CSVs)
/// with zero external dependencies and inserts the resulting expenses into the exact same schema
/// (`ExtractedReceipt` / `extracted_receipts`) used by native scans.
public enum CSVImportService {

    // MARK: - Public Ingestion API

    /// Parses raw CSV string data, transforms rows into normalized line items,
    /// calculates live foreign exchange rates, and inserts the resulting `ExtractedReceipt` into PostgreSQL.
    public static func importFromCSV(csvString: String, req: Request) async throws -> ExtractedReceipt {
        let cleanedCSV = cleanBOM(csvString)
        let rows = parseCSVRows(cleanedCSV)

        guard !rows.isEmpty else {
            throw Abort(.badRequest, reason: "The uploaded CSV contains no readable rows.")
        }

        // Detect column indices based on header row (or use positional fallback)
        let (headerMapping, dataRows) = extractHeadersAndData(rows: rows)

        guard !dataRows.isEmpty else {
            throw Abort(.badRequest, reason: "The uploaded CSV contains a header but no expense rows.")
        }

        var items: [ReceiptItem] = []
        var detectedCurrency: String = "USD"
        var detectedCategory: String? = nil
        var accumulatedTax: Double = 0.0
        var accumulatedTip: Double = 0.0
        var explicitTotal: Double? = nil

        for (index, row) in dataRows.enumerated() {
            guard !row.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                continue
            }

            let itemName = extractItemName(row: row, mapping: headerMapping, rowIndex: index)
            let itemPrice = extractPrice(row: row, mapping: headerMapping)
            let itemQty = extractQuantity(row: row, mapping: headerMapping)
            let isShared = extractIsShared(row: row, mapping: headerMapping)
            let rowCurrency = extractCurrency(row: row, mapping: headerMapping)
            let rowCategory = extractCategory(row: row, mapping: headerMapping)
            let rowTax = extractTax(row: row, mapping: headerMapping)
            let rowTip = extractTip(row: row, mapping: headerMapping)
            let rowTotal = extractRowTotal(row: row, mapping: headerMapping)

            if let rowCur = rowCurrency, !rowCur.isEmpty {
                detectedCurrency = rowCur.uppercased()
            }
            if let rowCat = rowCategory, !rowCat.isEmpty, detectedCategory == nil {
                detectedCategory = rowCat.lowercased()
            }
            if let t = rowTax {
                accumulatedTax += t
            }
            if let tp = rowTip {
                accumulatedTip += tp
            }
            if let rt = rowTotal, explicitTotal == nil {
                explicitTotal = rt
            }

            // Create standardized ReceiptItem conforming to native scan schema
            let receiptItem = ReceiptItem(
                name: itemName,
                price: itemPrice,
                quantity: itemQty,
                isShared: isShared,
                originalCurrency: detectedCurrency,
                convertedPrice: itemPrice,
                targetCurrency: "USD",
                exchangeRate: 1.0
            )

            items.append(receiptItem)
        }

        guard !items.isEmpty else {
            throw Abort(.badRequest, reason: "Could not extract any valid expense items from the CSV.")
        }

        // Subtotal calculated from items
        let computedSubtotal = items.reduce(0.0) { sum, item in
            sum + (item.price * Double(item.quantity))
        }

        let subtotal = (computedSubtotal * 100).rounded() / 100
        let tax = (accumulatedTax * 100).rounded() / 100
        let tip = (accumulatedTip * 100).rounded() / 100
        let finalTotal: Double
        if let expTotal = explicitTotal, expTotal > 0, items.count == 1 {
            finalTotal = (expTotal * 100).rounded() / 100
        } else {
            finalTotal = ((subtotal + tax + tip) * 100).rounded() / 100
        }

        // Currency conversion & live exchange rate resolution
        let targetCurrency = "USD"
        let rate = await ExchangeRateService.getRate(from: detectedCurrency, to: targetCurrency, client: req.client)
        let convertedTotal = (finalTotal * rate * 100).rounded() / 100

        // Normalized receipt items with target currency exchange rates
        let normalizedItems = items.map { item -> ReceiptItem in
            let itemConvertedPrice = (item.price * rate * 100).rounded() / 100
            return ReceiptItem(
                name: item.name,
                price: item.price,
                quantity: item.quantity,
                isShared: item.isShared,
                originalCurrency: detectedCurrency,
                convertedPrice: itemConvertedPrice,
                targetCurrency: targetCurrency,
                exchangeRate: rate
            )
        }

        let referenceId = "import-csv-\(UUID().uuidString.prefix(12))"

        // Instantiate the authoritative ExtractedReceipt model (same schema as native scans)
        let receipt = ExtractedReceipt(
            referenceId: referenceId,
            items: normalizedItems,
            subtotal: subtotal,
            tax: tax,
            tip: tip,
            total: finalTotal,
            category: detectedCategory,
            currency: detectedCurrency,
            targetCurrency: targetCurrency,
            exchangeRate: rate,
            convertedTotal: convertedTotal
        )

        // Persist directly to database
        try await receipt.save(on: req.db)
        req.logger.info("Imported CSV into ExtractedReceipt \(receipt.id?.uuidString ?? "") with \(normalizedItems.count) items, total: \(finalTotal) \(detectedCurrency) (\(convertedTotal) USD).")

        return receipt
    }

    // MARK: - Pure-Swift RFC 4180 CSV Parsing Engine

    /// Parses an entire CSV string into an array of rows, each containing an array of column values.
    /// Accurately handles quoted fields, escaped quotes (""), embedded commas, and multiline values.
    public static func parseCSVRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var inQuotes = false

        var index = text.startIndex
        let endIndex = text.endIndex

        while index < endIndex {
            let char = text[index]

            if inQuotes {
                if char == "\"" {
                    let nextIndex = text.index(after: index)
                    if nextIndex < endIndex && text[nextIndex] == "\"" {
                        // Escaped quote: "" -> "
                        currentField.append("\"")
                        index = nextIndex // Skip second quote
                    } else {
                        // End of quoted field
                        inQuotes = false
                    }
                } else {
                    currentField.append(char)
                }
            } else {
                if char == "\"" {
                    inQuotes = true
                } else if char == "," {
                    currentRow.append(currentField.trimmingCharacters(in: .whitespaces))
                    currentField = ""
                } else if char == "\r" {
                    let nextIndex = text.index(after: index)
                    if nextIndex < endIndex && text[nextIndex] == "\n" {
                        index = nextIndex
                    }
                    currentRow.append(currentField.trimmingCharacters(in: .whitespaces))
                    currentField = ""
                    if !currentRow.isEmpty && !currentRow.allSatisfy({ $0.isEmpty }) {
                        rows.append(currentRow)
                    }
                    currentRow = []
                } else if char == "\n" {
                    currentRow.append(currentField.trimmingCharacters(in: .whitespaces))
                    currentField = ""
                    if !currentRow.isEmpty && !currentRow.allSatisfy({ $0.isEmpty }) {
                        rows.append(currentRow)
                    }
                    currentRow = []
                } else {
                    currentField.append(char)
                }
            }

            index = text.index(after: index)
        }

        // Flush remaining field & row
        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField.trimmingCharacters(in: .whitespaces))
            if !currentRow.isEmpty && !currentRow.allSatisfy({ $0.isEmpty }) {
                rows.append(currentRow)
            }
        }

        return rows
    }

    // MARK: - Column Mapping & Field Extraction

    public struct ColumnMapping {
        var nameIndex: Int?
        var priceIndex: Int?
        var quantityIndex: Int?
        var isSharedIndex: Int?
        var currencyIndex: Int?
        var categoryIndex: Int?
        var subtotalIndex: Int?
        var taxIndex: Int?
        var tipIndex: Int?
        var totalIndex: Int?
        var dateIndex: Int?
    }

    private static func extractHeadersAndData(rows: [[String]]) -> (ColumnMapping, [[String]]) {
        guard let firstRow = rows.first else {
            return (ColumnMapping(), [])
        }

        let normalizedHeaders = firstRow.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

        var mapping = ColumnMapping()
        var hasRecognizedHeader = false

        for (idx, header) in normalizedHeaders.enumerated() {
            if matchesHeader(header, synonyms: ["item", "name", "description", "merchant", "title", "payee", "details", "merchant / description", "items summary"]) {
                if mapping.nameIndex == nil { mapping.nameIndex = idx }
                hasRecognizedHeader = true
            } else if matchesHeader(header, synonyms: ["price", "amount", "cost", "unit price", "debit", "rate"]) {
                if mapping.priceIndex == nil { mapping.priceIndex = idx }
                hasRecognizedHeader = true
            } else if matchesHeader(header, synonyms: ["total", "converted total", "grand total", "net amount"]) {
                if mapping.totalIndex == nil { mapping.totalIndex = idx }
                hasRecognizedHeader = true
            } else if matchesHeader(header, synonyms: ["qty", "quantity", "count"]) {
                mapping.quantityIndex = idx
                hasRecognizedHeader = true
            } else if matchesHeader(header, synonyms: ["shared", "is shared", "isshared", "split"]) {
                mapping.isSharedIndex = idx
                hasRecognizedHeader = true
            } else if matchesHeader(header, synonyms: ["currency", "curr", "code"]) {
                mapping.currencyIndex = idx
                hasRecognizedHeader = true
            } else if matchesHeader(header, synonyms: ["category", "context", "tag", "tags", "type"]) {
                mapping.categoryIndex = idx
                hasRecognizedHeader = true
            } else if matchesHeader(header, synonyms: ["subtotal", "sub_total", "items subtotal"]) {
                mapping.subtotalIndex = idx
                hasRecognizedHeader = true
            } else if matchesHeader(header, synonyms: ["tax", "vat", "gst"]) {
                mapping.taxIndex = idx
                hasRecognizedHeader = true
            } else if matchesHeader(header, synonyms: ["tip", "gratuity"]) {
                mapping.tipIndex = idx
                hasRecognizedHeader = true
            } else if matchesHeader(header, synonyms: ["date", "created", "timestamp", "transaction date", "time"]) {
                mapping.dateIndex = idx
                hasRecognizedHeader = true
            }
        }

        if hasRecognizedHeader {
            // First row was header
            return (mapping, Array(rows.dropFirst()))
        } else {
            // No header found: construct positional fallback
            var fallback = ColumnMapping()
            if firstRow.count >= 1 { fallback.nameIndex = 0 }
            if firstRow.count >= 2 { fallback.priceIndex = 1 }
            if firstRow.count >= 3 { fallback.quantityIndex = 2 }
            if firstRow.count >= 4 { fallback.categoryIndex = 3 }
            return (fallback, rows)
        }
    }

    private static func matchesHeader(_ header: String, synonyms: [String]) -> Bool {
        synonyms.contains { syn in
            header == syn || header.contains(syn)
        }
    }

    private static func extractItemName(row: [String], mapping: ColumnMapping, rowIndex: Int) -> String {
        if let idx = mapping.nameIndex, idx < row.count {
            let raw = row[idx].trimmingCharacters(in: .whitespacesAndNewlines)
            if !raw.isEmpty {
                return titleCase(raw)
            }
        }
        return "Imported Item #\(rowIndex + 1)"
    }

    private static func extractPrice(row: [String], mapping: ColumnMapping) -> Double {
        if let idx = mapping.priceIndex ?? mapping.totalIndex ?? mapping.subtotalIndex, idx < row.count {
            return sanitizeNumber(row[idx])
        }
        // Fallback: search row for first parseable number
        for val in row {
            let num = sanitizeNumber(val)
            if num > 0 { return num }
        }
        return 0.0
    }

    private static func extractRowTotal(row: [String], mapping: ColumnMapping) -> Double? {
        if let idx = mapping.totalIndex, idx < row.count {
            let val = sanitizeNumber(row[idx])
            return val > 0 ? val : nil
        }
        return nil
    }

    private static func extractQuantity(row: [String], mapping: ColumnMapping) -> Int {
        if let idx = mapping.quantityIndex, idx < row.count {
            let num = Int(sanitizeNumber(row[idx]))
            return max(num, 1)
        }
        return 1
    }

    private static func extractIsShared(row: [String], mapping: ColumnMapping) -> Bool {
        if let idx = mapping.isSharedIndex, idx < row.count {
            let val = row[idx].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return ["true", "1", "yes", "y", "shared"].contains(val)
        }
        return false
    }

    private static func extractCurrency(row: [String], mapping: ColumnMapping) -> String? {
        if let idx = mapping.currencyIndex, idx < row.count {
            let val = row[idx].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if ExchangeRateService.supportedCurrencies.contains(val) {
                return val
            }
        }
        // Check price strings for currency signs ($ -> USD, € -> EUR, £ -> GBP, ¥ -> JPY)
        for field in row {
            if field.contains("$") { return "USD" }
            if field.contains("€") { return "EUR" }
            if field.contains("£") { return "GBP" }
            if field.contains("¥") { return "JPY" }
            if field.contains("CAD") { return "CAD" }
            if field.contains("AUD") { return "AUD" }
        }
        return nil
    }

    private static func extractCategory(row: [String], mapping: ColumnMapping) -> String? {
        if let idx = mapping.categoryIndex, idx < row.count {
            let raw = row[idx].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if raw.contains("rest") || raw.contains("food") || raw.contains("dine") || raw.contains("meal") {
                return "restaurants"
            } else if raw.contains("trip") || raw.contains("travel") || raw.contains("flight") || raw.contains("hotel") {
                return "trips"
            } else if raw.contains("room") || raw.contains("rent") || raw.contains("house") || raw.contains("util") {
                return "roommates"
            } else if raw.contains("everyday") || raw.contains("groc") || raw.contains("shop") {
                return "everyday"
            }
            return raw.isEmpty ? nil : raw
        }
        return nil
    }

    private static func extractTax(row: [String], mapping: ColumnMapping) -> Double? {
        if let idx = mapping.taxIndex, idx < row.count {
            let num = sanitizeNumber(row[idx])
            return num > 0 ? num : nil
        }
        return nil
    }

    private static func extractTip(row: [String], mapping: ColumnMapping) -> Double? {
        if let idx = mapping.tipIndex, idx < row.count {
            let num = sanitizeNumber(row[idx])
            return num > 0 ? num : nil
        }
        return nil
    }

    // MARK: - Sanitizers & Normalizers

    private static func cleanBOM(_ str: String) -> String {
        if str.hasPrefix("\u{FEFF}") {
            return String(str.dropFirst())
        }
        return str
    }

    private static func sanitizeNumber(_ str: String) -> Double {
        let stripped = str
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: "£", with: "")
            .replacingOccurrences(of: "¥", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let doubleVal = Double(stripped) {
            return abs(doubleVal)
        }
        return 0.0
    }

    private static func titleCase(_ text: String) -> String {
        text
            .split(separator: " ")
            .map { word in
                word.prefix(1).uppercased() + word.dropFirst().lowercased()
            }
            .joined(separator: " ")
    }
}
