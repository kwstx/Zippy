import Vapor
import Foundation

/// Sends a stored receipt image to Google Gemini for structured extraction,
/// then normalizes the result with pure-Swift parsing before returning.
enum ExtractionService {

    // MARK: - Public

    /// Extract receipt data from an image stored on disk.
    /// - Parameters:
    ///   - referenceId: The UUID string used as the image filename (without extension).
    ///   - app: The running Vapor `Application` (used for storage path + HTTP client).
    /// - Returns: A populated `ExtractedReceipt` (not yet saved).
    static func extract(referenceId: String, app: Application) async throws -> ExtractedReceipt {
        // 1. Read the stored image
        guard let storageDir = app.storage[ReceiptStorageKey.self] else {
            throw Abort(.internalServerError, reason: "Storage configuration missing.")
        }
        let imagePath = URL(fileURLWithPath: storageDir)
            .appendingPathComponent("\(referenceId).jpg").path

        guard FileManager.default.fileExists(atPath: imagePath) else {
            throw Abort(.notFound, reason: "Receipt image not found for referenceId: \(referenceId)")
        }

        let imageData = try Data(contentsOf: URL(fileURLWithPath: imagePath))
        let base64Image = imageData.base64EncodedString()

        // 2. Call Gemini
        let rawJSON = try await callGemini(base64Image: base64Image, app: app)

        // 3. Parse and normalize
        let receipt = try parseAndNormalize(json: rawJSON, referenceId: referenceId)
        return receipt
    }

    // MARK: - Gemini API

    private static func callGemini(base64Image: String, app: Application) async throws -> Data {
        guard let apiKey = Environment.get("GEMINI_API_KEY") else {
            throw Abort(.internalServerError, reason: "GEMINI_API_KEY environment variable is not set.")
        }

        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw Abort(.internalServerError, reason: "Invalid Gemini API URL.")
        }

        let prompt = """
        Analyze this receipt image and extract all data into the following JSON structure.
        Return ONLY valid JSON, no markdown fences, no commentary.

        {
          "items": [
            {
              "name": "Item name as shown on receipt",
              "price": 0.00,
              "quantity": 1,
              "isShared": false
            }
          ],
          "subtotal": 0.00,
          "tax": 0.00,
          "tip": 0.00,
          "total": 0.00
        }

        Rules:
        - "price" is the total price for that line (quantity × unit price).
        - "quantity" defaults to 1 if not explicitly stated.
        - "isShared" should be true for items that are typically shared among a group
          (appetizers, pitchers, family-style dishes, shared plates, bread baskets, etc.).
          Individual entrees, drinks, and desserts should be false.
        - If tax is not visible, set it to 0.
        - If tip is not visible, set it to 0.
        - All prices must be non-negative numbers.
        """

        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        [
                            "text": prompt
                        ],
                        [
                            "inline_data": [
                                "mime_type": "image/jpeg",
                                "data": base64Image
                            ]
                        ]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.1,
                "maxOutputTokens": 4096
            ]
        ]

        let jsonBody = try JSONSerialization.data(withJSONObject: requestBody)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonBody
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw Abort(.internalServerError, reason: "Invalid response from Gemini API.")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<unreadable>"
            app.logger.error("Gemini API error (\(httpResponse.statusCode)): \(body)")
            throw Abort(.internalServerError, reason: "Gemini API returned status \(httpResponse.statusCode).")
        }

        // Extract the text content from the Gemini response envelope
        let geminiResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard
            let candidates = geminiResponse?["candidates"] as? [[String: Any]],
            let firstCandidate = candidates.first,
            let content = firstCandidate["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]],
            let text = parts.first?["text"] as? String
        else {
            throw Abort(.internalServerError, reason: "Failed to parse Gemini response structure.")
        }

        // Strip markdown code fences if present
        let cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonData = cleaned.data(using: .utf8) else {
            throw Abort(.internalServerError, reason: "Gemini returned non-UTF8 text.")
        }

        return jsonData
    }

    // MARK: - Pure-Swift Parsing & Normalization

    /// Raw shape decoded from the model's JSON output.
    private struct RawExtraction: Decodable {
        struct RawItem: Decodable {
            let name: String?
            let price: Double?
            let quantity: Int?
            let isShared: Bool?
        }
        let items: [RawItem]?
        let subtotal: Double?
        let tax: Double?
        let tip: Double?
        let total: Double?
    }

    private static func parseAndNormalize(json: Data, referenceId: String) throws -> ExtractedReceipt {
        let raw: RawExtraction
        do {
            let decoder = JSONDecoder()
            raw = try decoder.decode(RawExtraction.self, from: json)
        } catch {
            throw Abort(.unprocessableEntity, reason: "AI returned invalid JSON: \(error.localizedDescription)")
        }

        // Normalize items
        let normalizedItems: [ReceiptItem] = (raw.items ?? []).compactMap { rawItem in
            guard let name = rawItem.name, !name.trimmingCharacters(in: .whitespaces).isEmpty else {
                return nil
            }
            let price = max(rawItem.price ?? 0, 0)
            let quantity = max(rawItem.quantity ?? 1, 1)
            let isShared = rawItem.isShared ?? false

            // Title-case the name: capitalize first letter of each word
            let titleCased = name
                .trimmingCharacters(in: .whitespaces)
                .split(separator: " ")
                .map { word in
                    word.prefix(1).uppercased() + word.dropFirst().lowercased()
                }
                .joined(separator: " ")

            return ReceiptItem(
                name: titleCased,
                price: price,
                quantity: quantity,
                isShared: isShared
            )
        }

        let tax = max(raw.tax ?? 0, 0)
        let tip = max(raw.tip ?? 0, 0)

        // Recompute subtotal from items if the model's subtotal diverges by more than 1%
        let itemSum = normalizedItems.reduce(0.0) { $0 + $1.price }
        var subtotal = max(raw.subtotal ?? 0, 0)
        if subtotal == 0 || abs(subtotal - itemSum) / max(itemSum, 1) > 0.01 {
            subtotal = itemSum
        }

        // Total = subtotal + tax + tip (use model total only if it's close)
        let computedTotal = subtotal + tax + tip
        var total = max(raw.total ?? 0, 0)
        if total == 0 || abs(total - computedTotal) / max(computedTotal, 1) > 0.02 {
            total = computedTotal
        }

        // Round all monetary values to 2 decimal places
        let roundedSubtotal = (subtotal * 100).rounded() / 100
        let roundedTax = (tax * 100).rounded() / 100
        let roundedTip = (tip * 100).rounded() / 100
        let roundedTotal = (total * 100).rounded() / 100

        return ExtractedReceipt(
            referenceId: referenceId,
            items: normalizedItems.map {
                ReceiptItem(
                    name: $0.name,
                    price: ($0.price * 100).rounded() / 100,
                    quantity: $0.quantity,
                    isShared: $0.isShared
                )
            },
            subtotal: roundedSubtotal,
            tax: roundedTax,
            tip: roundedTip,
            total: roundedTotal
        )
    }
}
