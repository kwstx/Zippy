// MARK: - SplitView.swift

import SwiftUI

/// Full-screen bill-splitting view with instant client-side calculation.
struct SplitView: View {
    @StateObject private var viewModel: SplitViewModel
    @State private var newParticipantName: String = ""
    @State private var selectedItemIndex: Int?
    @State private var showingAddParticipant: Bool = false
    @State private var isLinkCopied: Bool = false
    @State private var expandedParticipantId: UUID?

    init(receipt: ExtractedReceiptResponse) {
        _viewModel = StateObject(wrappedValue: SplitViewModel(receipt: receipt))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                thinDivider()

                // MARK: - Participants Section
                participantsSection()
                thinDivider()

                // MARK: - Items Section
                ForEach(Array(viewModel.receipt.items.enumerated()), id: \.offset) { index, item in
                    itemRow(item: item, index: index)
                    thinDivider()
                }

                // MARK: - Summary
                summaryRow(label: "Subtotal", amount: viewModel.receipt.subtotal)
                thinDivider()
                summaryRow(label: "Tax", amount: viewModel.receipt.tax)
                thinDivider()
                summaryRow(label: "Tip", amount: viewModel.receipt.tip)
                thinDivider()

                // MARK: - Who Owes What
                if let result = viewModel.splitResult, !result.balances.isEmpty {
                    balancesSection(result: result)
                }

                // MARK: - Finalize
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
            }
            .padding(.bottom, 14)
        }
    }

    @ViewBuilder
    private func participantChip(_ participant: Participant) -> some View {
        HStack(spacing: 6) {
            Text(participant.initial)
                .font(.system(.caption2, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(.black)
                .frame(width: 22, height: 22)
                .background(Color.white)
                .clipShape(Circle())

            Text(participant.name)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.white)

            Button(action: { viewModel.removeParticipant(id: participant.id) }) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Color(white: 0.4))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(Color(white: 0.3), lineWidth: 0.5)
        )
    }

    // MARK: - Item Rows

    @ViewBuilder
    private func itemRow(item: ReceiptItem, index: Int) -> some View {
        Button(action: { selectedItemIndex = index }) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.white)

                    if item.quantity > 1 {
                        Text("qty \(item.quantity)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(Color(white: 0.5))
                    }

                    // Assigned participants
                    let assigned = viewModel.assignees(for: index)
                    if assigned.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 10))
                            Text("unassigned")
                                .font(.system(.caption2, design: .monospaced))
                        }
                        .foregroundColor(Color(white: 0.4))
                    } else {
                        HStack(spacing: 4) {
                            ForEach(assigned) { person in
                                Text(person.initial)
                                    .font(.system(size: 9, design: .monospaced))
                                    .fontWeight(.bold)
                                    .foregroundColor(.black)
                                    .frame(width: 18, height: 18)
                                    .background(Color.white)
                                    .clipShape(Circle())
                            }
                            if assigned.count > 1 {
                                Text("÷\(assigned.count)")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundColor(Color(white: 0.5))
                            }
                        }
                    }
                }

                Spacer()

                Text(formatPrice(item.price))
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Summary Rows

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

    // MARK: - Balances

    @ViewBuilder
    private func balancesSection(result: SplitResult) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("WHO OWES WHAT")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(Color(white: 0.4))
                Spacer()
                Text("Tap person to pay / settle")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Color(white: 0.4))
            }
            .padding(.vertical, 14)

            thinDivider()

            ForEach(result.balances) { balance in
                VStack(spacing: 0) {
                    // Clickable Person Header
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
                    balanceRow(label: "Items", amount: balance.itemsSubtotal)
                    balanceRow(label: "Tax", amount: balance.taxShare)
                    balanceRow(label: "Tip", amount: balance.tipShare)

                    // Person total
                    HStack {
                        Text("Total")
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                        Spacer()
                        Text(formatPrice(balance.total))
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                    }
                    .padding(.vertical, 8)

                    // Surface external payment methods stack if expanded
                    if expandedParticipantId == balance.participantId {
                        ExternalPaymentMethodsView(
                            participantId: balance.participantId,
                            participantName: balance.name,
                            amount: balance.total,
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
        }
    }

    @ViewBuilder
    private func balanceRow(label: String, amount: Double) -> some View {
        HStack {
            Text(label)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(Color(white: 0.5))
            Spacer()
            Text(formatPrice(amount))
                .font(.system(.caption, design: .monospaced))
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
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .padding(.vertical, 20)
            } else if let url = viewModel.shareableURL {
                VStack(spacing: 16) {
                    Text(url)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.black)
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)

                    Button(action: {
                        UIPasteboard.general.string = url
                        isLinkCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            isLinkCopied = false
                        }
                    }) {
                        Text(isLinkCopied ? "Copied" : "Copy")
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                            .foregroundColor(.black)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 8)
                            .overlay(
                                Rectangle()
                                    .stroke(Color.black, lineWidth: 0.5)
                            )
                    }
                }
                .padding(.vertical, 24)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
                .background(Color.white)
                .padding(.vertical, 20)
            } else {
                Button(action: {
                    Task { await viewModel.finalize() }
                }) {
                    Text("Finalize & Share")
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white)
                }
                .padding(.vertical, 20)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.red)
                    .padding(.bottom, 12)
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func thinDivider() -> some View {
        Rectangle()
            .fill(Color(white: 0.2))
            .frame(height: 0.5)
    }

    private func formatPrice(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }
}

// MARK: - Make Int work with sheet(item:)

extension Int: @retroactive Identifiable {
    public var id: Int { self }
}
