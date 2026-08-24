// MARK: - HistoryView.swift

import SwiftUI

/// Minimalist black-and-white expense history, search, and export screen.
/// Features a signature search bar rendered as a single thin black underline,
/// context-aware category filtering, filtered row retrieval from PostgreSQL,
/// and live pure-Swift CSV/PDF streaming exports.
struct HistoryView: View {
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var selectedCategory: ReceiptCategory? = nil
    @State private var searchQuery: String = ""
    @State private var historyItems: [HistoryItem] = []
    @State private var isLoading: Bool = false
    @State private var isExporting: Bool = false
    @State private var exportFormatLabel: String = ""
    @State private var errorMessage: String? = nil

    // Export sharing & paywall state
    @State private var exportedFileURL: URL? = nil
    @State private var showingShareSheet: Bool = false
    @State private var showingPaywall: Bool = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top boundary hairline
                Rectangle()
                    .fill(Color.black)
                    .frame(height: 1.0)

                // MARK: - Search Bar (A Single Thin Black Underline)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(.black)

                        TextField(
                            "",
                            text: $searchQuery,
                            prompt: Text("Search expenses, items, merchants...")
                                .foregroundColor(Color(white: 0.55))
                                .font(.system(size: 13, design: .monospaced))
                        )
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.black)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: searchQuery) { _ in
                            loadHistory()
                        }

                        if !searchQuery.isEmpty {
                            Button(action: {
                                searchQuery = ""
                                loadHistory()
                            }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(.black)
                                    .padding(4)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)

                    // The signature single thin black underline
                    Rectangle()
                        .fill(Color.black)
                        .frame(height: 1.0)
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)

                // MARK: - Context Selector Filter
                ContextSelectorView(
                    selectedCategory: $selectedCategory,
                    isDarkBackground: false,
                    headerTitle: "FILTER BY CONTEXT",
                    onSelectionChanged: { _ in
                        loadHistory()
                    }
                )
                .padding(.horizontal, 20)
                .padding(.top, 14)

                // MARK: - Export Controls & Metrics Header
                exportBar()
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                // Hairline divider above results
                Rectangle()
                    .fill(Color.black.opacity(0.15))
                    .frame(height: 0.5)

                // MARK: - Results List
                if isLoading && historyItems.isEmpty {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.black)
                    Text("Loading history...")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Color(white: 0.4))
                        .padding(.top, 8)
                    Spacer()
                } else if historyItems.isEmpty {
                    Spacer()
                    VStack(spacing: 8) {
                        Text("NO EXPENSES FOUND")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.black)

                        if selectedCategory != nil || !searchQuery.isEmpty {
                            Text("Try adjusting your context filter or search term")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(Color(white: 0.5))
                        } else {
                            Text("Expenses and split receipts will appear here")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(Color(white: 0.5))
                        }
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(historyItems) { item in
                                historyItemRow(item)

                                // Crisp black-and-white hairline divider
                                Rectangle()
                                    .fill(Color.black.opacity(0.10))
                                    .frame(height: 0.5)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .refreshable {
                        loadHistory()
                    }
                }

                // Error Message banner
                if let error = errorMessage {
                    Text(error)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color(white: 0.3))
                        .padding(.vertical, 8)
                        .padding(.horizontal, 20)
                }

                // Bottom boundary hairline
                Rectangle()
                    .fill(Color.black)
                    .frame(height: 1.0)
            }
            .background(Color.white.ignoresSafeArea())
            .navigationTitle("Expense History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundColor(.black)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                }

                ToolbarItem(placement: .primaryAction) {
                    Button(action: { loadHistory() }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.black)
                    }
                }
            }
            .task {
                loadHistory()
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallSheetView(subscriptionManager: subscriptionManager)
            }
            .sheet(isPresented: $showingShareSheet) {
                if let fileURL = exportedFileURL {
                    ShareSheet(activityItems: [fileURL])
                }
            }
        }
    }

    // MARK: - Export Bar (CSV & Pure-Swift PDF Streaming Triggers)

    @ViewBuilder
    private func exportBar() -> some View {
        HStack(spacing: 8) {
            // Count indicator
            Text("\(historyItems.count) \(historyItems.count == 1 ? "RECORD" : "RECORDS")")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(Color(white: 0.45))

            Spacer()

            if isExporting {
                HStack(spacing: 6) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.black)
                        .scaleEffect(0.7)
                    Text("STREAMING \(exportFormatLabel)...")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.black)
                }
            } else {
                // Export CSV Button
                Button(action: { triggerExport(format: "csv") }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.doc")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                        Text("CSV")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.black)
                }
                .disabled(historyItems.isEmpty || isLoading)

                // Export PDF Button (Pure-Swift generated)
                Button(action: { triggerExport(format: "pdf") }) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                        Text("PDF")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1.0))
                }
                .disabled(historyItems.isEmpty || isLoading)
            }
        }
    }

    // MARK: - History Item Row

    @ViewBuilder
    private func historyItemRow(_ item: HistoryItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.black)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        if let category = item.parsedCategory {
                            Text(category.displayName.uppercased())
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.black)
                        } else {
                            Text("UNCATEGORIZED")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(Color(white: 0.5))
                        }

                        if item.participantCount > 1 {
                            Text("SPLIT (\(item.participantCount))")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.black)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .border(Color.black, width: 0.5)
                        }
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    CurrencyText(
                        item.total,
                        currency: item.currency,
                        font: .system(size: 15, weight: .bold, design: .monospaced),
                        amountWeight: .bold,
                        codeWeight: .light
                    )
                    .foregroundColor(.black)

                    if item.isSettled {
                        Text("SETTLED")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.black)
                    }
                }
            }

            if let itemsSummary = item.itemsSummary, !itemsSummary.isEmpty {
                Text(itemsSummary.joined(separator: " · "))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color(white: 0.45))
                    .lineLimit(1)
            }

            if let date = item.createdAt {
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color(white: 0.5))
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    // MARK: - Actions

    private func loadHistory() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let items = try await ReceiptService.fetchHistory(
                    category: selectedCategory,
                    search: searchQuery
                )
                await MainActor.run {
                    self.historyItems = items
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to load history: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }

    private func triggerExport(format: String) {
        guard !isExporting else { return }

        // PDF export is gated behind Pro subscription
        if format.lowercased() == "pdf" && !subscriptionManager.isPro {
            showingPaywall = true
            return
        }

        isExporting = true
        exportFormatLabel = format.uppercased()
        errorMessage = nil

        Task {
            do {
                let (data, filename, _) = try await ReceiptService.exportHistory(
                    format: format,
                    category: selectedCategory,
                    search: searchQuery
                )

                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                try data.write(to: tempURL)

                await MainActor.run {
                    self.exportedFileURL = tempURL
                    self.isExporting = false
                    self.showingShareSheet = true
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Export failed: \(error.localizedDescription)"
                    self.isExporting = false
                }
            }
        }
    }
}
