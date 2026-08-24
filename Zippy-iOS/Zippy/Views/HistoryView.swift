// MARK: - HistoryView.swift

import SwiftUI

/// Minimalist black-and-white history & search screen.
/// Uses the single black-and-white context selector (Restaurants, Trips, Roommates, Everyday purchases)
/// and search filters to explore past receipts and splits without altering the visual language.
struct HistoryView: View {
    @State private var selectedCategory: ReceiptCategory? = nil
    @State private var searchQuery: String = ""
    @State private var historyItems: [HistoryItem] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // MARK: - Search Field
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(Color(white: 0.5))

                    TextField("Search receipts or splits...", text: $searchQuery)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.white)
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
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(Color(white: 0.5))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(white: 0.08))
                .overlay(Rectangle().stroke(Color(white: 0.2), lineWidth: 0.5))
                .padding(.horizontal, 20)
                .padding(.top, 12)

                // MARK: - Context Selector Filter
                ContextSelectorView(
                    selectedCategory: $selectedCategory,
                    isDarkBackground: true,
                    headerTitle: "FILTER BY CONTEXT",
                    onSelectionChanged: { _ in
                        loadHistory()
                    }
                )
                .padding(.horizontal, 20)
                .padding(.top, 12)

                divider()
                .padding(.top, 6)

                // MARK: - Results List
                if isLoading {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                    Text("Loading history...")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(Color(white: 0.6))
                        .padding(.top, 8)
                    Spacer()
                } else if historyItems.isEmpty {
                    Spacer()
                    VStack(spacing: 8) {
                        Text("NO ENTRIES FOUND")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(white: 0.5))
                        if selectedCategory != nil || !searchQuery.isEmpty {
                            Text("Try adjusting your context filter or search term")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(Color(white: 0.35))
                        }
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(historyItems) { item in
                                historyItemRow(item)
                                divider()
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Color(white: 0.7))
                        .padding(.vertical, 8)
                        .padding(.horizontal, 20)
                }
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("History & Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundColor(.white)
                        .font(.system(.body, design: .monospaced))
                }
            }
            .task {
                loadHistory()
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
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)

                    if let category = item.parsedCategory {
                        Text(category.displayName.uppercased())
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white)
                    } else {
                        Text("UNCATEGORIZED")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(Color(white: 0.4))
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
                    .foregroundColor(.white)

                    if item.isSettled {
                        Text("SETTLED")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .border(Color.white, width: 0.5)
                    }
                }
            }

            if let itemsSummary = item.itemsSummary, !itemsSummary.isEmpty {
                Text(itemsSummary.joined(separator: " · "))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color(white: 0.5))
                    .lineLimit(1)
            }

            if let date = item.createdAt {
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color(white: 0.35))
            }
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    // MARK: - Helpers

    @ViewBuilder
    private func divider() -> some View {
        Rectangle()
            .fill(Color(white: 0.2))
            .frame(height: 0.5)
    }

    private func loadHistory() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let items = try await ReceiptService.fetchHistory(
                    category: selectedCategory,
                    search: searchQuery
                )
                self.historyItems = items
            } catch {
                self.errorMessage = "Failed to load history: \(error.localizedDescription)"
            }
            self.isLoading = false
        }
    }
}
