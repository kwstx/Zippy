// MARK: - ImportCSVView.swift

import SwiftUI
import UniformTypeIdentifiers

/// Minimalist black-and-white screen for importing expense data from external tools.
/// Features a single file-picker button labeled "Import CSV", initiates system document selection,
/// uploads to the dedicated backend ingestion endpoint, and navigates directly into the native scan receipt view.
struct ImportCSVView: View {
    @StateObject private var viewModel = ImportCSVViewModel()
    @State private var showingFilePicker: Bool = false
    @State private var showingResult: Bool = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top boundary hairline
                Rectangle()
                    .fill(Color.black)
                    .frame(height: 1.0)

                Spacer()

                if viewModel.isImporting {
                    // MARK: - Monochrome Loading State
                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.black)
                            .scaleEffect(1.5)

                        Text("Uploading & parsing CSV...")
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                            .foregroundColor(.black)

                        if let fileName = viewModel.selectedFileName {
                            Text(fileName)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(Color(white: 0.4))
                        }
                    }
                    .transition(.opacity)

                } else {
                    // MARK: - Single File-Picker Button Screen
                    VStack(spacing: 32) {
                        // Minimalist Icon & Context Heading
                        VStack(spacing: 12) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 64, weight: .light))
                                .foregroundColor(.black)

                            Text("IMPORT FROM OTHER TOOLS")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .tracking(1.5)
                                .foregroundColor(.black)

                            Text("Supports CSV exports from Splitwise, Mint, YNAB, Expensify, bank exports, and spreadsheet templates.")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(Color(white: 0.4))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }

                        // The single file-picker button labeled "Import CSV"
                        Button(action: {
                            showingFilePicker = true
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "arrow.up.doc.fill")
                                    .font(.system(size: 16, design: .monospaced))
                                Text("Import CSV")
                                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.black)
                            .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                        }
                        .padding(.horizontal, 48)
                        .disabled(viewModel.isImporting)
                    }
                }

                // MARK: - Error Banner
                if let errorMessage = viewModel.errorMessage {
                    VStack(spacing: 8) {
                        Text(errorMessage)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)

                        Button(action: {
                            viewModel.errorMessage = nil
                        }) {
                            Text("DISMISS")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.black)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .overlay(Rectangle().stroke(Color.black, lineWidth: 0.8))
                        }
                    }
                    .padding(.top, 24)
                }

                Spacer()

                // Bottom boundary hairline
                Rectangle()
                    .fill(Color.black)
                    .frame(height: 1.0)
            }
            .background(Color.white.ignoresSafeArea())
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [
                    .commaSeparatedText,
                    .plainText,
                    .text,
                    UTType(filenameExtension: "csv") ?? .commaSeparatedText
                ],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let selectedURL = urls.first {
                        Task {
                            await viewModel.handlePickedFile(result: .success(selectedURL))
                        }
                    }
                case .failure(let error):
                    viewModel.errorMessage = error.localizedDescription
                }
            }
            .onChange(of: viewModel.importedReceipt) { receipt in
                if receipt != nil {
                    showingResult = true
                }
            }
            .navigationDestination(isPresented: $showingResult) {
                if let receipt = viewModel.importedReceipt {
                    ReceiptResultView(receipt: receipt)
                        .navigationBarBackButtonHidden(false)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                            Text("Close")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                        }
                        .foregroundColor(.black)
                    }
                }
            }
        }
    }
}
