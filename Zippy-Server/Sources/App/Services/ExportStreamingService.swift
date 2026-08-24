import Vapor
import Foundation

/// Pure-Swift streaming service for exporting expense history into RFC 4180 CSV
/// and PDF 1.4 vector documents with zero external dependencies.
public enum ExportStreamingService {

    // MARK: - CSV Streaming

    /// Creates a streaming HTTP Response delivering RFC 4180 compliant CSV rows chunk-by-chunk.
    public static func streamCSV(items: [HistoryItemDTO], req: Request) -> Response {
        let response = Response(status: .ok)
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let filename = "zippy_expenses_\(timestamp).csv"

        response.headers.contentType = HTTPMediaType(type: "text", subType: "csv", parameters: ["charset": "utf-8"])
        response.headers.replaceOrAdd(name: .contentDisposition, value: "attachment; filename=\"\(filename)\"")
        response.headers.replaceOrAdd(name: "Cache-Control", value: "no-cache, no-store, must-revalidate")

        let headerRow = [
            "ID",
            "Date",
            "Merchant / Description",
            "Context",
            "Currency",
            "Subtotal",
            "Tax",
            "Tip",
            "Total",
            "Converted Total",
            "Target Currency",
            "Exchange Rate",
            "Settlement Status",
            "Participant Count",
            "Items Summary",
            "Shareable URL"
        ].map(escapeCSV).joined(separator: ",") + "\r\n"

        response.body = Response.Body(stream: { writer in
            Task {
                do {
                    // 1. Write Header Chunk
                    var headerBuffer = ByteBuffer()
                    headerBuffer.writeString(headerRow)
                    _ = try await writer.write(.buffer(headerBuffer)).get()

                    // 2. Stream Data Rows in batches
                    let dateFormatter = DateFormatter()
                    dateFormatter.locale = Locale(identifier: "en_US_POSIX")
                    dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

                    var batchBuffer = ByteBuffer()
                    var count = 0

                    for item in items {
                        let dateStr = item.createdAt.map { dateFormatter.string(from: $0) } ?? ""
                        let itemsStr = item.itemsSummary?.joined(separator: " | ") ?? ""
                        let categoryStr = item.category?.uppercased() ?? "UNCATEGORIZED"
                        let settledStr = item.isSettled ? "SETTLED" : "UNSETTLED"

                        let row = [
                            item.id.uuidString,
                            dateStr,
                            item.title,
                            categoryStr,
                            item.currency,
                            "", // subtotal
                            "", // tax
                            "", // tip
                            String(format: "%.2f", item.total),
                            item.convertedTotal.map { String(format: "%.2f", $0) } ?? String(format: "%.2f", item.total),
                            item.targetCurrency ?? item.currency,
                            item.exchangeRate.map { String(format: "%.4f", $0) } ?? "1.0000",
                            settledStr,
                            String(item.participantCount),
                            itemsStr,
                            item.shareableURL ?? ""
                        ].map(escapeCSV).joined(separator: ",") + "\r\n"

                        batchBuffer.writeString(row)
                        count += 1

                        if count % 20 == 0 {
                            _ = try await writer.write(.buffer(batchBuffer)).get()
                            batchBuffer.clear()
                        }
                    }

                    if batchBuffer.readableBytes > 0 {
                        _ = try await writer.write(.buffer(batchBuffer)).get()
                    }

                    // 3. Complete Stream
                    _ = try await writer.write(.end).get()
                } catch {
                    _ = writer.write(.error(error))
                }
            }
        })

        return response
    }

    /// Escapes a CSV cell value according to RFC 4180 rules.
    private static func escapeCSV(_ text: String) -> String {
        let containsSpecial = text.contains(",") || text.contains("\"") || text.contains("\n") || text.contains("\r")
        if containsSpecial {
            let escaped = text.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return text
    }

    // MARK: - Pure Swift PDF Vector Engine (PDF 1.4)

    /// Creates a streaming HTTP Response delivering a pure Swift generated PDF 1.4 document.
    public static func streamPDF(
        items: [HistoryItemDTO],
        categoryFilter: String? = nil,
        searchQuery: String? = nil,
        req: Request
    ) -> Response {
        let response = Response(status: .ok)
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let filename = "zippy_expenses_\(timestamp).pdf"

        response.headers.contentType = HTTPMediaType(type: "application", subType: "pdf")
        response.headers.replaceOrAdd(name: .contentDisposition, value: "attachment; filename=\"\(filename)\"")
        response.headers.replaceOrAdd(name: "Cache-Control", value: "no-cache, no-store, must-revalidate")

        let pdfData = PureSwiftPDFBuilder.buildExpenseReport(
            items: items,
            categoryFilter: categoryFilter,
            searchQuery: searchQuery
        )

        response.body = Response.Body(stream: { writer in
            Task {
                do {
                    var buffer = ByteBuffer()
                    buffer.writeData(pdfData)
                    _ = try await writer.write(.buffer(buffer)).get()
                    _ = try await writer.write(.end).get()
                } catch {
                    _ = writer.write(.error(error))
                }
            }
        })

        return response
    }
}

// MARK: - Pure Swift Vector PDF Generator (PDF 1.4 Compliant)

public enum PureSwiftPDFBuilder {

    /// Generates a valid standard PDF 1.4 binary data containing the black-and-white expense report.
    public static func buildExpenseReport(
        items: [HistoryItemDTO],
        categoryFilter: String? = nil,
        searchQuery: String? = nil
    ) -> Data {
        let pageWidth: Double = 612.0  // Standard US Letter (8.5" x 11")
        let pageHeight: Double = 792.0
        let itemsPerPage = 14

        let totalPages = max(1, Int(ceil(Double(max(1, items.count)) / Double(itemsPerPage))))

        var pagesContent: [String] = []

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"

        let generatedDateStr = dateFormatter.string(from: Date())

        let totalAmount = items.reduce(0.0) { $0 + $1.total }
        let settledCount = items.filter(\.isSettled).count
        let primaryCurrency = items.first?.currency ?? "USD"

        for pageIndex in 0..<totalPages {
            var stream = ""

            // --- Page Frame & Margins ---
            let leftMargin: Double = 40.0
            let rightMargin: Double = 572.0
            let contentWidth = rightMargin - leftMargin

            // --- Page Header (Top) ---
            var currentY: Double = pageHeight - 50.0

            // Top thick black accent rule
            stream += "0 g\n"
            stream += "\(leftMargin) \(currentY) \(contentWidth) 2 re f\n"
            currentY -= 16.0

            // Title: ZIPPY // EXPENSE REPORT
            stream += "BT\n/F2 16 Tf\n\(leftMargin) \(currentY) Td\n(ZIPPY // EXPENSE HISTORY REPORT) Tj\nET\n"

            // Sub-header date
            stream += "BT\n/F3 9 Tf\n\(rightMargin - 150.0) \(currentY + 2.0) Td\n(\(pdfEscape(generatedDateStr))) Tj\nET\n"
            currentY -= 14.0

            // Active Filter Metadata
            var filterDetails: [String] = []
            if let cat = categoryFilter, !cat.isEmpty, cat != "all" {
                filterDetails.append("CONTEXT: \(cat.uppercased())")
            }
            if let q = searchQuery, !q.isEmpty {
                filterDetails.append("QUERY: \"\(q)\"")
            }
            if filterDetails.isEmpty {
                filterDetails.append("ALL EXPENSES")
            }
            let filterText = filterDetails.joined(separator: "  |  ")
            stream += "BT\n/F1 9 Tf\n0.3 g\n\(leftMargin) \(currentY) Td\n(\(pdfEscape(filterText))) Tj\nET\n"
            currentY -= 18.0

            // Summary Metrics Box (Page 1 only)
            if pageIndex == 0 {
                // Background summary card with thin border
                stream += "0.96 g\n\(leftMargin) \(currentY - 26.0) \(contentWidth) 30 re f\n"
                stream += "0.2 G\n0.5 w\n\(leftMargin) \(currentY - 26.0) \(contentWidth) 30 re S\n"

                let summaryY = currentY - 17.0
                let totalStr = String(format: "%.2f %@", totalAmount, primaryCurrency)
                stream += "0 g\nBT\n/F2 9 Tf\n\(leftMargin + 12.0) \(summaryY) Td\n(TOTAL RECORDS: ) Tj\n/F3 9 Tf\n(\(items.count)) Tj\nET\n"
                stream += "BT\n/F2 9 Tf\n\(leftMargin + 160.0) \(summaryY) Td\n(TOTAL VOLUME: ) Tj\n/F3 9 Tf\n(\(pdfEscape(totalStr))) Tj\nET\n"
                stream += "BT\n/F2 9 Tf\n\(leftMargin + 360.0) \(summaryY) Td\n(SETTLED: ) Tj\n/F3 9 Tf\n(\(settledCount)/\(items.count)) Tj\nET\n"
                currentY -= 40.0
            } else {
                currentY -= 10.0
            }

            // --- Table Header ---
            let tableHeaderY = currentY
            let tableHeaderHeight: Double = 18.0

            // Solid black header row
            stream += "0 g\n\(leftMargin) \(tableHeaderY - tableHeaderHeight + 4.0) \(contentWidth) \(tableHeaderHeight) re f\n"

            // White column titles
            stream += "1 g\n"
            stream += "BT\n/F2 8 Tf\n\(leftMargin + 6.0) \(tableHeaderY - 8.0) Td\n(DATE) Tj\nET\n"
            stream += "BT\n/F2 8 Tf\n\(leftMargin + 72.0) \(tableHeaderY - 8.0) Td\n(MERCHANT / DESCRIPTION) Tj\nET\n"
            stream += "BT\n/F2 8 Tf\n\(leftMargin + 250.0) \(tableHeaderY - 8.0) Td\n(CONTEXT) Tj\nET\n"
            stream += "BT\n/F2 8 Tf\n\(leftMargin + 340.0) \(tableHeaderY - 8.0) Td\n(CUR) Tj\nET\n"
            stream += "BT\n/F2 8 Tf\n\(leftMargin + 380.0) \(tableHeaderY - 8.0) Td\n(AMOUNT) Tj\nET\n"
            stream += "BT\n/F2 8 Tf\n\(leftMargin + 465.0) \(tableHeaderY - 8.0) Td\n(STATUS) Tj\nET\n"

            currentY -= 22.0

            // --- Table Rows ---
            let startIndex = pageIndex * itemsPerPage
            let endIndex = min(startIndex + itemsPerPage, items.count)
            let pageItems = startIndex < items.count ? Array(items[startIndex..<endIndex]) : []

            if pageItems.isEmpty {
                stream += "0.4 g\nBT\n/F1 10 Tf\n\(leftMargin + 180.0) \(currentY - 20.0) Td\n(No expense entries matching criteria.) Tj\nET\n"
            } else {
                for item in pageItems {
                    let rowY = currentY
                    let rowHeight: Double = 26.0

                    // Clean hairline divider
                    stream += "0.85 G\n0.5 w\n\(leftMargin) \(rowY - rowHeight + 8.0) m \(rightMargin) \(rowY - rowHeight + 8.0) l S\n"

                    let itemDateStr = item.createdAt.map { dateFormatter.string(from: $0) } ?? "---"
                    let truncatedTitle = truncateString(item.title, maxLength: 28)
                    let categoryTag = (item.category ?? "everyday").uppercased()
                    let amountStr = String(format: "%.2f", item.total)
                    let isSettled = item.isSettled

                    // Date
                    stream += "0.3 g\nBT\n/F3 7.5 Tf\n\(leftMargin + 6.0) \(rowY - 8.0) Td\n(\(pdfEscape(itemDateStr))) Tj\nET\n"

                    // Title / Merchant
                    stream += "0 g\nBT\n/F2 8.5 Tf\n\(leftMargin + 72.0) \(rowY - 8.0) Td\n(\(pdfEscape(truncatedTitle))) Tj\nET\n"

                    // Subtitle preview of line items
                    if let summary = item.itemsSummary, !summary.isEmpty {
                        let subPreview = truncateString(summary.joined(separator: ", "), maxLength: 34)
                        stream += "0.5 g\nBT\n/F1 6.5 Tf\n\(leftMargin + 72.0) \(rowY - 17.0) Td\n(\(pdfEscape(subPreview))) Tj\nET\n"
                    }

                    // Context Badge
                    stream += "0.2 g\nBT\n/F3 7.5 Tf\n\(leftMargin + 250.0) \(rowY - 8.0) Td\n(\(pdfEscape(categoryTag))) Tj\nET\n"

                    // Currency
                    stream += "0.4 g\nBT\n/F3 8 Tf\n\(leftMargin + 340.0) \(rowY - 8.0) Td\n(\(pdfEscape(item.currency))) Tj\nET\n"

                    // Amount (Monospaced Bold)
                    stream += "0 g\nBT\n/F3 8.5 Tf\n\(leftMargin + 380.0) \(rowY - 8.0) Td\n(\(pdfEscape(amountStr))) Tj\nET\n"

                    // Settlement Status Badge
                    if isSettled {
                        // Solid black filled badge with white text
                        stream += "0 g\n\(leftMargin + 465.0) \(rowY - 14.0) 48 11 re f\n"
                        stream += "1 g\nBT\n/F2 6.5 Tf\n\(leftMargin + 472.0) \(rowY - 10.0) Td\n(SETTLED) Tj\nET\n"
                    } else {
                        // Thin bordered badge
                        stream += "0.3 G\n0.5 w\n\(leftMargin + 465.0) \(rowY - 14.0) 48 11 re S\n"
                        stream += "0.3 g\nBT\n/F1 6.5 Tf\n\(leftMargin + 472.0) \(rowY - 10.0) Td\n(UNPAID) Tj\nET\n"
                    }

                    currentY -= rowHeight
                }
            }

            // --- Footer (Bottom) ---
            let footerY: Double = 40.0
            stream += "0 G\n0.5 w\n\(leftMargin) \(footerY + 12.0) m \(rightMargin) \(footerY + 12.0) l S\n"

            let footerPageStr = "PAGE \(pageIndex + 1) OF \(totalPages)  //  ZIPPY MONOCHROME ENGINE"
            stream += "0.4 g\nBT\n/F3 7.5 Tf\n\(leftMargin) \(footerY) Td\n(\(pdfEscape(footerPageStr))) Tj\nET\n"

            pagesContent.append(stream)
        }

        // --- Assemble PDF Objects and XRef Table ---
        return renderPDFStructure(pages: pagesContent, pageWidth: pageWidth, pageHeight: pageHeight)
    }

    /// Assembles valid PDF 1.4 syntax with precise cross-reference byte offsets.
    private static func renderPDFStructure(pages: [String], pageWidth: Double, pageHeight: Double) -> Data {
        var pdf = "%PDF-1.4\n%\u{00E2}\u{00E3}\u{00CF}\u{00D3}\n"
        var objectOffsets: [Int: Int] = [:]

        func appendObject(_ id: Int, _ body: String) {
            objectOffsets[id] = pdf.utf8.count
            pdf += "\(id) 0 obj\n\(body)\nendobj\n"
        }

        // Object 1: Catalog
        appendObject(1, "<< /Type /Catalog /Pages 2 0 R >>")

        // Objects for Fonts
        // Object 4: Helvetica Regular
        appendObject(4, "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>")
        // Object 5: Helvetica Bold
        appendObject(5, "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>")
        // Object 6: Courier (Monospaced)
        appendObject(6, "<< /Type /Font /Subtype /Type1 /BaseFont /Courier /Encoding /WinAnsiEncoding >>")

        // Pre-calculate object IDs for pages and content streams
        let pageCount = pages.count
        var pageObjectIds: [Int] = []
        var contentObjectIds: [Int] = []

        var nextId = 7
        for _ in 0..<pageCount {
            pageObjectIds.append(nextId)
            nextId += 1
            contentObjectIds.append(nextId)
            nextId += 1
        }

        // Object 2: Pages Container
        let kidsArray = pageObjectIds.map { "\($0) 0 R" }.joined(separator: " ")
        appendObject(2, "<< /Type /Pages /Kids [\(kidsArray)] /Count \(pageCount) /MediaBox [0 0 \(pageWidth) \(pageHeight)] >>")

        // Objects for each Page and its Content Stream
        for i in 0..<pageCount {
            let pageId = pageObjectIds[i]
            let contentId = contentObjectIds[i]
            let contentString = pages[i]
            let contentLength = contentString.utf8.count

            // Page Object
            appendObject(pageId, """
            << /Type /Page /Parent 2 0 R
               /Resources <<
                 /Font <<
                   /F1 4 0 R
                   /F2 5 0 R
                   /F3 6 0 R
                 >>
               >>
               /Contents \(contentId) 0 R
            >>
            """)

            // Content Stream Object
            appendObject(contentId, """
            << /Length \(contentLength) >>
            stream
            \(contentString)
            endstream
            """)
        }

        // XRef Table
        let totalObjects = nextId - 1
        let xrefStartOffset = pdf.utf8.count
        pdf += "xref\n0 \(totalObjects + 1)\n0000000000 65535 f \n"

        for id in 1...totalObjects {
            let offset = objectOffsets[id] ?? 0
            let formatted = String(format: "%010d 00000 n \n", offset)
            pdf += formatted
        }

        // Trailer
        pdf += """
        trailer
        << /Size \(totalObjects + 1)
           /Root 1 0 R
        >>
        startxref
        \(xrefStartOffset)
        %%EOF

        """

        return pdf.data(using: .utf8) ?? Data()
    }

    /// Escapes PDF literal string characters `\`, `(`, `)`.
    private static func pdfEscape(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "(", with: "\\(")
            .replacingOccurrences(of: ")", with: "\\)")
    }

    /// Truncates string with ellipsis if exceeding max character limit.
    private static func truncateString(_ text: String, maxLength: Int) -> String {
        if text.count <= maxLength {
            return text
        }
        return String(text.prefix(maxLength - 2)) + ".."
    }
}
