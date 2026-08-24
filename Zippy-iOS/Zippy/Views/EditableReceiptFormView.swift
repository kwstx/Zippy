// MARK: - EditableReceiptFormView.swift

import SwiftUI

/// Black-and-white editable form for manual entry and instant AI extraction correction.
/// All text fields feature NO borders except a thin black underline.
/// Every modification is immediately PATCH-ed to the Vapor API, triggering server validation
/// and updating the shareable link state in real time.
struct EditableReceiptFormView: View {
    @StateObject private var viewModel: EditableReceiptViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingSplitView: Bool = false
    @State private var isLinkCopied: Bool = false

    /// Initialize with existing AI-extracted receipt for easy correction.
    init(receipt: ExtractedReceiptResponse) {
        _viewModel = StateObject(wrappedValue: EditableReceiptViewModel(receipt: receipt))
    }

    /// Initialize for manual entry from scratch.
    init() {
        _viewModel = StateObject(wrappedValue: EditableReceiptViewModel())
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header Divider
                blackDivider(height: 1.5)

                // MARK: - Top Bar / Live Sync Status
                headerSyncBar()
                blackDivider()

                // MARK: - Context Category Selector
                ContextSelectorView(
                    selectedCategory: $viewModel.selectedCategory,
                    isDarkBackground: false,
                    headerTitle: "CONTEXT",
                    onSelectionChanged: { newCategory in
                        viewModel.setCategory(newCategory)
                    }
                )
                .padding(.vertical, 14)

                blackDivider()

                // MARK: - Reference & Merchant Identifier
                merchantHeaderSection()
                blackDivider()

                // MARK: - Line Items Section
                lineItemsSection()
                blackDivider()

                // MARK: - Financial Totals (Subtotal, Tax, Tip, Total)
                totalsSection()
                blackDivider()

                // MARK: - Server Re-Validation Report Banner
                if let report = viewModel.validationReport {
                    validationReportSection(report: report)
                    blackDivider()
                }

                // MARK: - Live Shareable Link State Preview
                if let shareURL = viewModel.shareableURL {
                    shareableLinkSection(url: shareURL)
                    blackDivider()
                }

                // MARK: - Action Buttons
                proceedToSplitButton()
                    .padding(.vertical, 24)
            }
            .padding(.horizontal, 20)
        }
        .background(Color.white.ignoresSafeArea())
        .navigationTitle(viewModel.receiptId == nil ? "Manual Entry" : "Edit Receipt")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.light, for: .navigationBar)
        .navigationDestination(isPresented: $showingSplitView) {
            SplitView(receipt: viewModel.asExtractedReceiptResponse)
        }
    }

    // MARK: - Header Sync Bar

    @ViewBuilder
    private func headerSyncBar() -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.receiptId == nil ? "MANUAL RECEIPT" : "AI CORRECTION FORM")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.black)
                    .tracking(0.5)

                Text("Overwritten fields immediately PATCH to Vapor API")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color(white: 0.4))
            }

            Spacer()

            // Real-time Sync Status Badge
            if viewModel.isSyncing {
                HStack(spacing: 4) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.6)
                        .tint(.black)
                    Text("SYNCING")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.black)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
            } else if let report = viewModel.validationReport, report.isMathConsistent {
                Text("✓ VALIDATED")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black)
            } else if let report = viewModel.validationReport, !report.isMathConsistent {
                Text("⚠ MATH NOTICE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
            }
        }
        .padding(.vertical, 12)
    }

    // MARK: - Merchant & Reference Section

    @ViewBuilder
    private func merchantHeaderSection() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            UnderlinedTextField(
                placeholder: "e.g. Acme Cafe / Ref #1234",
                text: $viewModel.referenceId,
                label: "RECEIPT TITLE / REFERENCE",
                underlineColor: .black,
                textColor: .black,
                onChange: { _ in
                    viewModel.scheduleDebouncedPatch()
                }
            )
        }
        .padding(.vertical, 14)
    }

    // MARK: - Line Items Section

    @ViewBuilder
    private func lineItemsSection() -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("LINE ITEMS (\(viewModel.items.count))")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.black)
                    .tracking(0.5)

                Spacer()

                Button(action: {
                    viewModel.autoRecalculateTotals()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "equal.circle")
                            .font(.system(size: 11))
                        Text("AUTO-SUM")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 0.75))
                }
            }
            .padding(.top, 14)

            // Item Headers
            HStack(spacing: 8) {
                Text("ITEM DESCRIPTION")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(white: 0.4))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("QTY")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(white: 0.4))
                    .frame(width: 44, alignment: .center)

                Text("PRICE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(white: 0.4))
                    .frame(width: 72, alignment: .trailing)

                Text("SHARED")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(white: 0.4))
                    .frame(width: 50, alignment: .center)

                Text("")
                    .frame(width: 24)
            }
            .padding(.top, 4)

            // Item List
            ForEach($viewModel.items) { $item in
                itemEditorRow(item: $item)
                blackDivider(height: 0.5)
            }

            // + Add Item Button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    viewModel.addItem()
                }
            }) {
                HStack {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                    Text("ADD LINE ITEM")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
            }
            .padding(.vertical, 8)
        }
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private func itemEditorRow(item: Binding<EditableReceiptItem>) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Item Name (Underlined)
            UnderlinedTextField(
                placeholder: "Item description",
                text: item.name,
                underlineColor: .black,
                textColor: .black,
                onChange: { _ in
                    viewModel.scheduleDebouncedPatch()
                }
            )
            .frame(maxWidth: .infinity)

            // Quantity (Underlined)
            UnderlinedTextField(
                placeholder: "1",
                text: item.quantityString,
                keyboardType: .numberPad,
                alignment: .center,
                underlineColor: .black,
                textColor: .black,
                onChange: { _ in
                    viewModel.autoRecalculateTotals(silent: true)
                    viewModel.scheduleDebouncedPatch()
                }
            )
            .frame(width: 44)

            // Price (Underlined)
            UnderlinedTextField(
                placeholder: "0.00",
                text: item.priceString,
                prefix: "$",
                keyboardType: .decimalPad,
                alignment: .trailing,
                underlineColor: .black,
                textColor: .black,
                onChange: { _ in
                    viewModel.autoRecalculateTotals(silent: true)
                    viewModel.scheduleDebouncedPatch()
                }
            )
            .frame(width: 72)

            // Shared Checkbox Toggle
            Button(action: {
                item.isShared.wrappedValue.toggle()
                viewModel.scheduleDebouncedPatch()
            }) {
                ZStack {
                    Rectangle()
                        .stroke(Color.black, lineWidth: 1)
                        .frame(width: 22, height: 22)

                    if item.isShared.wrappedValue {
                        Rectangle()
                            .fill(Color.black)
                            .frame(width: 14, height: 14)
                    }
                }
            }
            .frame(width: 50, alignment: .center)
            .padding(.bottom, 6)

            // Delete Button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    viewModel.removeItem(id: item.id)
                }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(white: 0.5))
                    .frame(width: 24, height: 28)
            }
            .padding(.bottom, 4)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Financial Totals Section

    @ViewBuilder
    private func totalsSection() -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("FINANCIAL TOTALS")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.black)
                .tracking(0.5)
                .padding(.top, 14)

            // Subtotal Underlined Field
            HStack {
                Text("SUBTOTAL")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.black)
                Spacer()
                UnderlinedTextField(
                    placeholder: "0.00",
                    text: $viewModel.subtotalString,
                    prefix: "$",
                    keyboardType: .decimalPad,
                    alignment: .trailing,
                    underlineColor: .black,
                    textColor: .black,
                    onChange: { _ in
                        viewModel.scheduleDebouncedPatch()
                    }
                )
                .frame(width: 120)
            }

            // Tax Underlined Field
            HStack {
                Text("TAX")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.black)
                Spacer()
                UnderlinedTextField(
                    placeholder: "0.00",
                    text: $viewModel.taxString,
                    prefix: "$",
                    keyboardType: .decimalPad,
                    alignment: .trailing,
                    underlineColor: .black,
                    textColor: .black,
                    onChange: { _ in
                        viewModel.scheduleDebouncedPatch()
                    }
                )
                .frame(width: 120)
            }

            // Tip Underlined Field
            HStack {
                Text("TIP")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.black)
                Spacer()
                UnderlinedTextField(
                    placeholder: "0.00",
                    text: $viewModel.tipString,
                    prefix: "$",
                    keyboardType: .decimalPad,
                    alignment: .trailing,
                    underlineColor: .black,
                    textColor: .black,
                    onChange: { _ in
                        viewModel.scheduleDebouncedPatch()
                    }
                )
                .frame(width: 120)
            }

            blackDivider(height: 1.5)

            // Grand Total Underlined Field
            HStack {
                Text("GRAND TOTAL")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundColor(.black)
                Spacer()
                UnderlinedTextField(
                    placeholder: "0.00",
                    text: $viewModel.totalString,
                    prefix: "$",
                    keyboardType: .decimalPad,
                    alignment: .trailing,
                    isBold: true,
                    underlineColor: .black,
                    textColor: .black,
                    onChange: { _ in
                        viewModel.scheduleDebouncedPatch()
                    }
                )
                .frame(width: 130)
            }
        }
        .padding(.vertical, 14)
    }

    // MARK: - Validation Report Section

    @ViewBuilder
    private func validationReportSection(report: ReceiptValidationReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: report.isMathConsistent ? "checkmark.shield" : "exclamationmark.triangle")
                    .font(.system(size: 13, design: .monospaced))
                Text(report.isMathConsistent ? "SERVER VALIDATION: CONSISTENT" : "SERVER VALIDATION: DISCREPANCIES DETECTED")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.5)
            }
            .foregroundColor(.black)

            if !report.isMathConsistent {
                VStack(alignment: .leading, spacing: 4) {
                    Text("• Computed items sum: $\(String(format: "%.2f", report.computedSubtotal))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Color(white: 0.3))
                    Text("• Computed grand total: $\(String(format: "%.2f", report.computedTotal))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Color(white: 0.3))

                    ForEach(report.warnings, id: \.self) { warning in
                        Text("• \(warning)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.black)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Shareable Link State Preview

    @ViewBuilder
    private func shareableLinkSection(url: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SHAREABLE LINK (LIVE SYNCED)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(white: 0.4))
                    .tracking(0.5)
                Spacer()
                Text("GUEST WEB VIEW")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Color(white: 0.6))
            }

            HStack {
                Text(url)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.black)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Button(action: {
                    UIPasteboard.general.string = url
                    isLinkCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        isLinkCopied = false
                    }
                }) {
                    Text(isLinkCopied ? "COPIED" : "COPY")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black)
                }
            }
            .padding(10)
            .overlay(Rectangle().stroke(Color.black, lineWidth: 1))

            Text("Any edits above automatically update guest breakdown in real-time.")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(Color(white: 0.5))
        }
        .padding(.vertical, 14)
    }

    // MARK: - Proceed to Split Button

    @ViewBuilder
    private func proceedToSplitButton() -> some View {
        Button(action: {
            showingSplitView = true
        }) {
            HStack {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 14))
                Text("SPLIT THIS BILL →")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.black)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func blackDivider(height: CGFloat = 1.0) -> some View {
        Rectangle()
            .fill(Color.black)
            .frame(height: height)
    }
}
