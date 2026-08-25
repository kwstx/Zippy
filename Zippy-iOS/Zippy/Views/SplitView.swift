// MARK: - SplitView.swift

import SwiftUI

extension Int: @retroactive Identifiable {
    public var id: Int { self }
}

/// Full-screen bill-splitting view with flexible split methods (Equal, Itemized, Percentage, Shares, Exact),
/// instant client-side calculation, backend synchronization, and in-place monochrome totals refresh.
struct SplitView: View {
    @StateObject private var viewModel: SplitViewModel
    @State private var newParticipantName: String = ""
    @State private var selectedItemIndex: Int?
    @State private var showingAddParticipant: Bool = false
    @State private var isLinkCopied: Bool = false
    @State private var expandedParticipantId: UUID?
    @State private var showingSimplifiedPayments: Bool = false
    @State private var showingStatusScreen: Bool = false

    init(receipt: ExtractedReceiptResponse) {
        _viewModel = StateObject(wrappedValue: SplitViewModel(receipt: receipt))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                thinDivider()

                // MARK: - Context Selector Section
                ContextSelectorView(
                    selectedCategory: $viewModel.selectedCategory,
                    isDarkBackground: true,
                    headerTitle: "CONTEXT",
                    onSelectionChanged: { newCategory in
                        viewModel.updateCategory(newCategory)
                    }
                )
                .padding(.vertical, 12)

                thinDivider()

                // MARK: - Split Method Segmented Control (Pure Text Labels)
                SplitMethodSegmentedControl(
                    selectedMethod: $viewModel.selectedSplitMethod,
                    onMethodChanged: { newMethod in
                        viewModel.setSplitMethod(newMethod)
                    }
                )
                .padding(.vertical, 12)

                thinDivider()

                // MARK: - Participants Section
                participantsSection()
                thinDivider()

                // MARK: - Method Controls Section (Equal / Itemized / Percentage / Shares / Exact)
                SplitMethodControlsView(
                    viewModel: viewModel,
                    selectedItemIndex: $selectedItemIndex
                )

                thinDivider()

                // MARK: - Summary Rows
                summaryRow(label: "Subtotal", amount: viewModel.receipt.subtotal)
                thinDivider()
                summaryRow(label: "Tax", amount: viewModel.receipt.tax)
                thinDivider()
                summaryRow(label: "Tip", amount: viewModel.receipt.tip)
                thinDivider()
                summaryRow(label: "Total", amount: viewModel.receipt.total, isBold: true)
                thinDivider()

                // MARK: - Who Owes What (Monochrome Totals Refreshed In Place)
                if let result = viewModel.splitResult, !result.balances.isEmpty {
                    balancesSection(result: result)
                }

                // MARK: - Finalize & Share
                if !viewModel.participants.isEmpty {
                    finalizeSection()
                }
            }
            .padding(.horizontal, 20)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Split")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingStatusScreen = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 13, design: .monospaced))
                        Text("Status")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .task {
            // Background polling loop if session is finalized
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                await viewModel.refreshStatus()
            }
        }
        .sheet(item: $selectedItemIndex) { index in
            ItemAssignmentSheet(
                item: viewModel.receipt.items[index],
                itemIndex: index,
                viewModel: viewModel
            )
        }
        .sheet(isPresented: $showingSimplifiedPayments) {
            SimplifiedPaymentsView(
                transfers: viewModel.simplifiedPayments,
                currency: viewModel.receipt.effectiveCurrency
            )
        }
        .sheet(isPresented: $showingStatusScreen) {
            PaymentStatusView(
                token: viewModel.shareableURL?.components(separatedBy: "/s/").last,
                invoiceTitle: (viewModel.receipt.merchantName?.isEmpty ?? true) ? "Trip Invoice – Japan Summer 2025" : "Trip Invoice – \(viewModel.receipt.merchantName!)",
                initialBalances: viewModel.splitResult?.balances ?? []
            )
        }
        .alert("Add Person", isPresented: $showingAddParticipant) {
            TextField("Name", text: $newParticipantName)
            Button("Add") {
                viewModel.addParticipant(name: newParticipantName)
                newParticipantName = ""
            }
            Button("Cancel", role: .cancel) {
                newParticipantName = ""
            }
        }
    }

    // MARK: - Participants

    @ViewBuilder
    private func participantsSection() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PEOPLE")
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(Color(white: 0.4))
                .padding(.top, 14)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.participants) { participant in
                        participantChip(participant)
                    }

                    // Add button
                    Button(action: { showingAddParticipant = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(.caption, design: .monospaced))
                            Text("Add")
                                .font(.system(.caption, design: .monospaced))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 0)
                                .stroke(Color(white: 0.3), lineWidth: 0.5)
                        )
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private func participantChip(_ participant: Participant) -> some View {
        HStack(spacing: 8) {
            Text(participant.name)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.white)

            Button(action: { viewModel.removeParticipant(id: participant.id) }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color(white: 0.5))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(white: 0.1))
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(Color(white: 0.25), lineWidth: 0.5)
        )
    }

    // MARK: - Summary

    @ViewBuilder
    private func summaryRow(label: String, amount: Double, isBold: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.system(.body, design: .monospaced))
                .fontWeight(isBold ? .bold : .regular)
                .foregroundColor(isBold ? .white : Color(white: 0.7))
            Spacer()
            CurrencyText(
                amount,
                currency: viewModel.receipt.effectiveCurrency,
                font: .system(.body, design: .monospaced),
                amountWeight: isBold ? .bold : .regular,
                codeWeight: .light
            )
            .foregroundColor(isBold ? .white : Color(white: 0.7))
        }
        .padding(.vertical, isBold ? 14 : 10)
    }

    // MARK: - Balances Section

    @ViewBuilder
    private func balancesSection(result: SplitResult) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("WHO OWES WHAT")
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(Color(white: 0.4))
                .padding(.top, 16)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                ForEach(result.balances) { balance in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if expandedParticipantId == balance.participantId {
                                expandedParticipantId = nil
                            } else {
                                expandedParticipantId = balance.participantId
                            }
                        }
                    }) {
                        HStack {
                            Text(balance.name)
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            Spacer()
                            if balance.isPaid || balance.settlementStatus == .settled {
                                Text("PAID")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.white)
                            } else if balance.settlementStatus == .pendingConfirmation || balance.paymentMethod != nil {
                                Text("AWAITING CONFIRMATION")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .overlay(Rectangle().stroke(Color.white, lineWidth: 0.5))
                            }
                            Image(systemName: expandedParticipantId == balance.participantId ? "chevron.up" : "chevron.down")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(Color(white: 0.5))
                        }
                        .padding(.top, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    // Breakdown
                    balanceRow(label: "Items", amount: balance.itemsSubtotal, currency: balance.currency)
                    balanceRow(label: "Tax", amount: balance.taxShare, currency: balance.currency)
                    balanceRow(label: "Tip", amount: balance.tipShare, currency: balance.currency)

                    // Person total (Monochrome high-contrast display with lighter weight currency)
                    HStack {
                        Text("Total")
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        Spacer()
                        CurrencyText(
                            balance.total,
                            currency: balance.currency,
                            font: .system(.body, design: .monospaced),
                            amountWeight: .bold,
                            codeWeight: .light
                        )
                        .foregroundColor(.white)
                    }
                    .padding(.vertical, 8)

                    // Surface external payment methods stack if expanded
                    if expandedParticipantId == balance.participantId {
                        ExternalPaymentMethodsView(
                            participantId: balance.participantId,
                            participantName: balance.name,
                            amount: balance.total,
                            currency: balance.currency,
                            token: viewModel.shareableURL?.components(separatedBy: "/s/").last,
                            settlementStatus: balance.settlementStatus,
                            selectedMethod: balance.paymentMethod,
                            onMethodSelected: { method in
                                Task {
                                    _ = await viewModel.selectPaymentMethod(participantId: balance.participantId, method: method)
                                }
                            },
                            onConfirmManual: {
                                Task {
                                    await viewModel.confirmSettlement(participantId: balance.participantId)
                                }
                            }
                        )
                        .padding(.vertical, 12)
                    }

                    thinDivider()
                }
            }

            // Payment Status Screen Button (Minimalist White Screen)
            Button(action: {
                showingStatusScreen = true
            }) {
                HStack {
                    Image(systemName: "circle.inset.filled")
                        .font(.system(size: 11, design: .monospaced))
                    Text("PAYMENT STATUS")
                        .font(.system(.caption2, design: .monospaced))
                        .fontWeight(.bold)
                    Spacer()
                    Text("→")
                        .font(.system(.caption, design: .monospaced))
                }
                .foregroundColor(.white)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            thinDivider()

            // Simplified Payments Button
            Button(action: {
                Task {
                    await viewModel.fetchSimplifiedPayments()
                    showingSimplifiedPayments = true
                }
            }) {
                HStack {
                    Image(systemName: "arrow.triangle.swap")
                        .font(.system(size: 11, design: .monospaced))
                    Text("SIMPLIFIED PAYMENTS")
                        .font(.system(.caption2, design: .monospaced))
                        .fontWeight(.bold)
                    Spacer()
                    Text("→")
                        .font(.system(.caption, design: .monospaced))
                }
                .foregroundColor(.white)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            thinDivider()
        }
    }

    @ViewBuilder
    private func balanceRow(label: String, amount: Double, currency: String) -> some View {
        HStack {
            Text(label)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(Color(white: 0.5))
            Spacer()
            CurrencyText(
                amount,
                currency: currency,
                font: .system(.caption, design: .monospaced),
                amountWeight: .regular,
                codeWeight: .light
            )
            .foregroundColor(Color(white: 0.5))
        }
        .padding(.vertical, 4)
        .padding(.leading, 16)
    }

    // MARK: - Finalize

    @ViewBuilder
    private func finalizeSection() -> some View {
        VStack(spacing: 12) {
            if viewModel.isFinalizing {
                ProgressView()
                    .tint(.white)
                    .padding(.vertical, 16)
            } else if let url = viewModel.shareableURL {
                VStack(spacing: 8) {
                    Text("SHAREABLE LINK")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(Color(white: 0.4))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 14)

                    HStack {
                        Text(url)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.white)
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
                            Text(isLinkCopied ? "Copied" : "Copy")
                                .font(.system(.caption, design: .monospaced))
                                .fontWeight(.bold)
                                .foregroundColor(.black)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.white)
                        }
                    }
                    .padding(12)
                    .background(Color(white: 0.1))
                    .overlay(
                        Rectangle().stroke(Color(white: 0.3), lineWidth: 0.5)
                    )
                }
            } else {
                Button(action: {
                    Task {
                        await viewModel.finalize()
                    }
                }) {
                    HStack {
                        Image(systemName: "link")
                            .font(.system(.body, design: .monospaced))
                        Text("Finalize & Get Share Link")
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
                .padding(.top, 16)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(Color(white: 0.7))
                    .padding(.top, 4)
            }
        }
        .padding(.bottom, 24)
    }

    @ViewBuilder
    private func thinDivider() -> some View {
        Rectangle()
            .fill(Color(white: 0.2))
            .frame(height: 0.5)
    }
}
