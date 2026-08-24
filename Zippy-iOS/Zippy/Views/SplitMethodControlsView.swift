// MARK: - SplitMethodControlsView.swift

import SwiftUI

/// Renders interactive allocation controls tailored to the active split method:
/// Equal, Itemized, Percentage, Shares, or Exact.
struct SplitMethodControlsView: View {
    @ObservedObject var viewModel: SplitViewModel
    @Binding var selectedItemIndex: Int?

    var body: some View {
        VStack(spacing: 0) {
            switch viewModel.selectedSplitMethod {
            case .equal:
                equalControls()

            case .itemized:
                itemizedControls()

            case .percentage:
                percentageControls()

            case .shares:
                sharesControls()

            case .exact:
                exactControls()
            }
        }
    }

    // MARK: - 1. Equal Controls

    @ViewBuilder
    private func equalControls() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("EQUAL ALLOCATION")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(white: 0.45))
                    .tracking(1.2)
                Spacer()
                if !viewModel.participants.isEmpty {
                    Text("\(viewModel.participants.count) PEOPLE")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(Color(white: 0.5))
                }
            }
            .padding(.top, 14)

            thinDivider()

            if viewModel.participants.isEmpty {
                Text("Add people above to split equally.")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(Color(white: 0.4))
                    .padding(.vertical, 14)
            } else {
                let perPerson = viewModel.receipt.total / Double(viewModel.participants.count)
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Each person pays")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(Color(white: 0.5))
                        Text(formatPrice(perPerson))
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Bill Total")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(Color(white: 0.4))
                        Text(formatPrice(viewModel.receipt.total))
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.white)
                    }
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .background(Color(white: 0.06))
                .overlay(
                    Rectangle()
                        .stroke(Color(white: 0.2), lineWidth: 0.5)
                )
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - 2. Itemized Controls

    @ViewBuilder
    private func itemizedControls() -> some View {
        VStack(spacing: 0) {
            ForEach(Array(viewModel.receipt.items.enumerated()), id: \.offset) { index, item in
                itemRow(item: item, index: index)
                thinDivider()
            }
        }
    }

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

    // MARK: - 3. Percentage Controls

    @ViewBuilder
    private func percentageControls() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("PERCENTAGE ALLOCATION")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(white: 0.45))
                    .tracking(1.2)
                Spacer()
                Button(action: { viewModel.resetPercentagesToEqual() }) {
                    Text("RESET TO EQUAL")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(white: 0.6))
                        .underline()
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 14)

            // Total indicator
            let totalPct = viewModel.totalAssignedPercentage
            HStack {
                Text(String(format: "Total: %.1f%%", totalPct))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(abs(totalPct - 100.0) < 0.1 ? .white : Color(white: 0.6))
                Spacer()
                if abs(totalPct - 100.0) >= 0.1 {
                    Text("Auto-normalized to 100%")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(Color(white: 0.4))
                }
            }
            .padding(.vertical, 4)

            thinDivider()

            if viewModel.participants.isEmpty {
                Text("Add people above to assign percentages.")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(Color(white: 0.4))
                    .padding(.vertical, 14)
            } else {
                ForEach(viewModel.participants) { participant in
                    percentageParticipantRow(participant)
                    thinDivider()
                }
            }
        }
    }

    @ViewBuilder
    private func percentageParticipantRow(_ participant: Participant) -> some View {
        let currentPct = viewModel.percentageAllocations[participant.id] ?? (100.0 / Double(max(1, viewModel.participants.count)))

        HStack {
            HStack(spacing: 8) {
                Text(participant.initial)
                    .font(.system(.caption2, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(.black)
                    .frame(width: 20, height: 20)
                    .background(Color.white)
                    .clipShape(Circle())

                Text(participant.name)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white)
            }

            Spacer()

            HStack(spacing: 6) {
                Button(action: { viewModel.adjustPercentage(for: participant.id, delta: -5) }) {
                    Text("-5%")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white)
                        .frame(width: 34, height: 26)
                        .background(Color(white: 0.12))
                        .overlay(Rectangle().stroke(Color(white: 0.3), lineWidth: 0.5))
                }
                .buttonStyle(.plain)

                Text(String(format: "%.0f%%", currentPct))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(width: 44, alignment: .center)

                Button(action: { viewModel.adjustPercentage(for: participant.id, delta: 5) }) {
                    Text("+5%")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white)
                        .frame(width: 34, height: 26)
                        .background(Color(white: 0.12))
                        .overlay(Rectangle().stroke(Color(white: 0.3), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 10)
    }

    // MARK: - 4. Shares Controls

    @ViewBuilder
    private func sharesControls() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SHARES ALLOCATION")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(white: 0.45))
                    .tracking(1.2)
                Spacer()
                Button(action: { viewModel.resetSharesToEqual() }) {
                    Text("RESET TO 1 EACH")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(white: 0.6))
                        .underline()
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 14)

            let totalShares = viewModel.totalAssignedShares
            HStack {
                Text(String(format: "Total Shares: %.1f", totalShares))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                Spacer()
                Text("Proportional weights")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Color(white: 0.4))
            }
            .padding(.vertical, 4)

            thinDivider()

            if viewModel.participants.isEmpty {
                Text("Add people above to assign shares.")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(Color(white: 0.4))
                    .padding(.vertical, 14)
            } else {
                ForEach(viewModel.participants) { participant in
                    sharesParticipantRow(participant, totalShares: totalShares)
                    thinDivider()
                }
            }
        }
    }

    @ViewBuilder
    private func sharesParticipantRow(_ participant: Participant, totalShares: Double) -> some View {
        let currentShares = viewModel.shareAllocations[participant.id] ?? 1.0
        let effectivePct = totalShares > 0 ? (currentShares / totalShares * 100) : 0.0

        HStack {
            HStack(spacing: 8) {
                Text(participant.initial)
                    .font(.system(.caption2, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(.black)
                    .frame(width: 20, height: 20)
                    .background(Color.white)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(participant.name)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.white)

                    Text(String(format: "%.1f%% of total", effectivePct))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(Color(white: 0.5))
                }
            }

            Spacer()

            HStack(spacing: 6) {
                Button(action: { viewModel.adjustShares(for: participant.id, delta: -1.0) }) {
                    Text("-1")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white)
                        .frame(width: 30, height: 26)
                        .background(Color(white: 0.12))
                        .overlay(Rectangle().stroke(Color(white: 0.3), lineWidth: 0.5))
                }
                .buttonStyle(.plain)

                Text(String(format: "%.0f", currentShares))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(width: 32, alignment: .center)

                Button(action: { viewModel.adjustShares(for: participant.id, delta: 1.0) }) {
                    Text("+1")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white)
                        .frame(width: 30, height: 26)
                        .background(Color(white: 0.12))
                        .overlay(Rectangle().stroke(Color(white: 0.3), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 10)
    }

    // MARK: - 5. Exact Controls

    @ViewBuilder
    private func exactControls() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("EXACT ALLOCATION")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(white: 0.45))
                    .tracking(1.2)
                Spacer()
                Button(action: { viewModel.resetExactToEqual() }) {
                    Text("RESET TO EQUAL")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(white: 0.6))
                        .underline()
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 14)

            // Balance tracker
            let remaining = viewModel.exactRemainingBalance
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total Allocated: \(formatPrice(viewModel.totalAssignedExact)) / \(formatPrice(viewModel.receipt.total))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Color(white: 0.6))

                    if abs(remaining) > 0.01 {
                        Text(remaining > 0 ? "Remaining to allocate: \(formatPrice(remaining))" : "Over-allocated by: \(formatPrice(-remaining))")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(remaining > 0 ? Color(white: 0.8) : Color.white)
                    } else {
                        Text("Fully allocated (100%)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 4)

            thinDivider()

            if viewModel.participants.isEmpty {
                Text("Add people above to assign exact amounts.")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(Color(white: 0.4))
                    .padding(.vertical, 14)
            } else {
                ForEach(viewModel.participants) { participant in
                    exactParticipantRow(participant)
                    thinDivider()
                }
            }
        }
    }

    @ViewBuilder
    private func exactParticipantRow(_ participant: Participant) -> some View {
        let currentAmount = viewModel.exactAllocations[participant.id] ?? (viewModel.receipt.total / Double(max(1, viewModel.participants.count)))

        HStack {
            HStack(spacing: 8) {
                Text(participant.initial)
                    .font(.system(.caption2, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(.black)
                    .frame(width: 20, height: 20)
                    .background(Color.white)
                    .clipShape(Circle())

                Text(participant.name)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white)
            }

            Spacer()

            HStack(spacing: 6) {
                Button(action: { viewModel.setExactAmount(for: participant.id, amount: max(0, currentAmount - 5.0)) }) {
                    Text("-$5")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 26)
                        .background(Color(white: 0.12))
                        .overlay(Rectangle().stroke(Color(white: 0.3), lineWidth: 0.5))
                }
                .buttonStyle(.plain)

                Text(formatPrice(currentAmount))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(width: 60, alignment: .center)

                Button(action: { viewModel.setExactAmount(for: participant.id, amount: currentAmount + 5.0) }) {
                    Text("+$5")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 26)
                        .background(Color(white: 0.12))
                        .overlay(Rectangle().stroke(Color(white: 0.3), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 10)
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
