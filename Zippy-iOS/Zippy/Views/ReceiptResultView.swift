// MARK: - ReceiptResultView.swift

import SwiftUI

struct ReceiptResultView: View {
    let receipt: ExtractedReceiptResponse
    
    /// Controls whether shared items are split evenly or assigned manually.
    @State private var splitSharedEvenly: Bool = true
    @State private var showingSplit: Bool = false
    @State private var settlementStatus: SettlementStatus = .unpaid
    @State private var selectedPaymentMethod: String? = nil
    @State private var selectedCategory: ReceiptCategory?

    init(receipt: ExtractedReceiptResponse) {
        self.receipt = receipt
        _selectedCategory = State(initialValue: receipt.parsedCategory)
    }

    private var receiptWithSelectedCategory: ExtractedReceiptResponse {
        var updated = receipt
        updated.category = selectedCategory?.rawValue
        return updated
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header
                thinDivider()

                // MARK: - Black & White Context Selector
                ContextSelectorView(
                    selectedCategory: $selectedCategory,
                    isDarkBackground: true,
                    headerTitle: "CONTEXT",
                    onSelectionChanged: { newCategory in
                        if let receiptId = receipt.id {
                            Task {
                                try? await ReceiptService.updateReceiptCategory(
                                    receiptId: receiptId,
                                    category: newCategory?.rawValue
                                )
                            }
                        }
                    }
                )
                .padding(.vertical, 12)

                thinDivider()
                
                // Shared cost mode selector (only shown if any shared items exist)
                if receipt.items.contains(where: { $0.isShared }) {
                    sharedModeRow()
                    thinDivider()
                }
                
                // Line items
                ForEach(receipt.items) { item in
                    itemRow(item)
                    thinDivider()
                }
                
                // Subtotal
                summaryRow(label: "Subtotal", amount: receipt.subtotal)
                thinDivider()
                
                // Tax
                summaryRow(label: "Tax", amount: receipt.tax)
                thinDivider()
                
                // Tip
                summaryRow(label: "Tip", amount: receipt.tip)
                thinDivider()
                
                // Total
                totalRow(label: "Total", amount: receipt.total)
                thinDivider()

                // External Payment Methods Section
                ExternalPaymentMethodsView(
                    participantId: receipt.id ?? UUID(),
                    participantName: "Bill Total",
                    amount: receipt.total,
                    token: nil,
                    settlementStatus: settlementStatus,
                    selectedMethod: selectedPaymentMethod,
                    onMethodSelected: { method in
                        selectedPaymentMethod = method
                        settlementStatus = .pendingConfirmation
                    },
                    onConfirmManual: {
                        settlementStatus = .settled
                    }
                )
                .padding(.vertical, 16)
                
                thinDivider()
                
                // Split button
                splitButton()
                thinDivider()
            }
            .padding(.horizontal, 20)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationDestination(isPresented: $showingSplit) {
            SplitView(receipt: receiptWithSelectedCategory)
        }
    }
    
    // MARK: - Row Components
    
    @ViewBuilder
    private func itemRow(_ item: ReceiptItem) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white)
                
                if item.quantity > 1 {
                    Text("qty \(item.quantity)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(Color(white: 0.5))
                }
                
                if item.isShared {
                    Text(splitSharedEvenly ? "(shared · split evenly)" : "(shared · assign manually)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(Color(white: 0.5))
                }
            }
            
            Spacer()
            
            Text(formatPrice(item.price))
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.white)
        }
        .padding(.vertical, 12)
    }
    
    @ViewBuilder
    private func summaryRow(label: String, amount: Double) -> some View {
        HStack {
            Text(label)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(Color(white: 0.7))
            
            Spacer()
            
            Text(formatPrice(amount))
                .font(.system(.body, design: .monospaced))
                .foregroundColor(Color(white: 0.7))
        }
        .padding(.vertical, 12)
    }
    
    @ViewBuilder
    private func totalRow(label: String, amount: Double) -> some View {
        HStack {
            Text(label)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Spacer()
            
            Text(formatPrice(amount))
                .font(.system(.body, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(.white)
        }
        .padding(.vertical, 14)
    }
    
    @ViewBuilder
    private func sharedModeRow() -> some View {
        HStack {
            Text("Shared items")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(Color(white: 0.5))
            
            Spacer()
            
            Button(action: {
                splitSharedEvenly.toggle()
            }) {
                Text(splitSharedEvenly ? "Split evenly" : "Assign manually")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .overlay(
                        RoundedRectangle(cornerRadius: 0)
                            .stroke(Color(white: 0.3), lineWidth: 0.5)
                    )
            }
        }
        .padding(.vertical, 10)
    }
    
    @ViewBuilder
    private func splitButton() -> some View {
        Button(action: {
            showingSplit = true
        }) {
            HStack {
                Image(systemName: "person.2")
                    .font(.system(.body, design: .monospaced))
                Text("Split this bill")
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .overlay(
                RoundedRectangle(cornerRadius: 0)
                    .stroke(Color(white: 0.3), lineWidth: 0.5)
            )
        }
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private func thinDivider() -> some View {
        Rectangle()
            .fill(Color(white: 0.2))
            .frame(height: 0.5)
    }
    
    // MARK: - Helpers
    
    private func formatPrice(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }
}
