// MARK: - ItemAssignmentSheet.swift

import SwiftUI

/// Bottom sheet for assigning participants to a single receipt item.
struct ItemAssignmentSheet: View {
    let item: ReceiptItem
    let itemIndex: Int
    @ObservedObject var viewModel: SplitViewModel
    @Environment(\.dismiss) private var dismiss

    var currency: String {
        item.originalCurrency ?? viewModel.receipt.effectiveCurrency
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.system(.headline, design: .monospaced))
                        .foregroundColor(.white)
                    CurrencyText(
                        item.price,
                        currency: currency,
                        font: .system(.subheadline, design: .monospaced),
                        amountWeight: .regular,
                        codeWeight: .light
                    )
                    .foregroundColor(Color(white: 0.5))
                }
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(Color(white: 0.5))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 16)

            divider()

            // "Everyone" shortcut
            Button(action: {
                let allAssigned = viewModel.assignees(for: itemIndex).count == viewModel.participants.count
                if allAssigned {
                    viewModel.unassignAll(itemIndex: itemIndex)
                } else {
                    viewModel.assignAll(itemIndex: itemIndex)
                }
            }) {
                HStack {
                    Text("Everyone")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.white)
                    Spacer()
                    if viewModel.assignees(for: itemIndex).count == viewModel.participants.count
                        && !viewModel.participants.isEmpty {
                        Image(systemName: "checkmark")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.white)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }

            divider()

            // Individual participants
            if viewModel.participants.isEmpty {
                Text("Add participants first")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(Color(white: 0.4))
                    .padding(.vertical, 32)
            } else {
                ForEach(viewModel.participants) { participant in
                    Button(action: {
                        viewModel.toggleAssignment(itemIndex: itemIndex, participantId: participant.id)
                    }) {
                        HStack {
                            // Avatar circle
                            Text(participant.initial)
                                .font(.system(.caption, design: .monospaced))
                                .fontWeight(.bold)
                                .foregroundColor(.black)
                                .frame(width: 28, height: 28)
                                .background(Color.white)
                                .clipShape(Circle())

                            Text(participant.name)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.white)
                                .padding(.leading, 8)

                            Spacer()

                            if viewModel.isAssigned(itemIndex: itemIndex, participantId: participant.id) {
                                Image(systemName: "checkmark")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.white)
                            }

                            // Per-person share if assigned
                            let assigneeCount = viewModel.assignees(for: itemIndex).count
                            if viewModel.isAssigned(itemIndex: itemIndex, participantId: participant.id),
                               assigneeCount > 0 {
                                CurrencyText(
                                    item.price / Double(assigneeCount),
                                    currency: currency,
                                    font: .system(.caption, design: .monospaced),
                                    amountWeight: .regular,
                                    codeWeight: .light
                                )
                                .foregroundColor(Color(white: 0.5))
                                .padding(.leading, 8)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                    }
                    divider()
                }
            }

            Spacer()
        }
        .background(Color.black.ignoresSafeArea())
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func divider() -> some View {
        Rectangle()
            .fill(Color(white: 0.2))
            .frame(height: 0.5)
    }
}
