// MARK: - ImportCSVViewModel.swift

import SwiftUI
import Combine
import UniformTypeIdentifiers

@MainActor
final class ImportCSVViewModel: ObservableObject {
    @Published var isImporting: Bool = false
    @Published var importedReceipt: ExtractedReceiptResponse? = nil
    @Published var errorMessage: String? = nil
    @Published var selectedFileName: String? = nil

    /// Handles the result from the file picker, extracts security-scoped data,
    /// and triggers uploading to the dedicated backend CSV ingestion endpoint.
    func handlePickedFile(result: Result<URL, Error>) async {
        switch result {
        case .success(let url):
            await importFile(from: url)
        case .failure(let error):
            self.errorMessage = "Failed to pick file: \(error.localizedDescription)"
        }
    }

    /// Reads data from the selected file URL and initiates upload to the server.
    func importFile(from url: URL) async {
        isImporting = true
        errorMessage = nil
        importedReceipt = nil

        let fileName = url.lastPathComponent
        self.selectedFileName = fileName

        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isSecurityScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            guard !data.isEmpty else {
                throw NSError(
                    domain: "ImportCSVViewModel",
                    code: 400,
                    userInfo: [NSLocalizedDescriptionKey: "The selected CSV file is empty."]
                )
            }

            let receipt = try await ReceiptService.importCSV(csvData: data, filename: fileName)
            self.importedReceipt = receipt
        } catch {
            self.errorMessage = error.localizedDescription
        }

        isImporting = false
    }

    /// Resets the import state for a new file selection.
    func reset() {
        isImporting = false
        importedReceipt = nil
        errorMessage = nil
        selectedFileName = nil
    }
}
