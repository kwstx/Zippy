// MARK: - GroupLedgerDetailView.swift

import SwiftUI

/// Displays the persistent group detail and loads its append-only ledger history
/// of every expense and settlement from backend ledger tables.
struct GroupLedgerDetailView: View {
    let initialGroup: PersistentGroup
    @StateObject private var viewModel: GroupLedgerViewModel

    @State private var showingAddExpenseSheet = false
    @State private var showingRecordSettlementSheet = false
    @State private var showingSimplifiedPaymentsSheet = false
    @State private var showingRecurringTemplatesSheet = false
    @State private var showingAddRecurringExpenseSheet = false

    init(group: PersistentGroup) {
        self.initialGroup = group
        _viewModel = StateObject(wrappedValue: GroupLedgerViewModel(groupId: group.id, initialGroup: group))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top border
            Rectangle()
                .fill(Color.black)
                .frame(height: 1)

            if viewModel.isLoading && viewModel.events.isEmpty {
                Spacer()
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.black)
                Text("Loading ledger stream from backend...")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.black)
                    .padding(.top, 8)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // MARK: - Group Overview Header
                        groupHeaderView
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            .background(Color.white)

                        Rectangle()
                            .fill(Color.black)
                            .frame(height: 1)

                        // MARK: - Continuous Debt Simplification
                        simplifiedPaymentsSection
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)
                            .background(Color.white)

                        Rectangle()
                            .fill(Color.black.opacity(0.15))
                            .frame(height: 1)

                        // MARK: - Member Balances Breakdown
                        if !viewModel.memberBalances.isEmpty {
                            memberBalancesSection
                                .padding(.horizontal, 20)
                                .padding(.vertical, 14)
                                .background(Color.white)

                            Rectangle()
                                .fill(Color.black.opacity(0.15))
                                .frame(height: 1)
                        }

                        // MARK: - Append-Only Event Stream History
                        eventStreamSection
                    }
                }
                .refreshable {
                    viewModel.loadHistory()
                    viewModel.loadRecurringTemplates()
                }
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.black)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 20)
            }

            // MARK: - Bottom Action Bar
            bottomActionBar
        }
        .background(Color.white.ignoresSafeArea())
        .navigationTitle(viewModel.group?.name ?? initialGroup.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 12) {
                    Button(action: { showingRecurringTemplatesSheet = true }) {
                        Image(systemName: "clock.arrow.2.circlepath")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundColor(.black)
                    }

                    Button(action: {
                        viewModel.loadHistory()
                        viewModel.loadRecurringTemplates()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundColor(.black)
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddExpenseSheet) {
            if let activeGroup = viewModel.group ?? Optional(initialGroup) {
                AddLedgerExpenseSheet(group: activeGroup) { title, amount, currency, payerId, splitIds, note in
                    Task {
                        _ = await viewModel.addExpense(
                            title: title,
                            amount: amount,
                            currency: currency,
                            payerId: payerId,
                            splitMemberIds: splitIds,
                            note: note
                        )
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddRecurringExpenseSheet) {
            if let activeGroup = viewModel.group ?? Optional(initialGroup) {
                AddRecurringExpenseSheet(group: activeGroup) { title, amount, currency, payerId, splitIds, freq, note, startDate in
                    Task {
                        _ = await viewModel.addRecurringExpense(
                            title: title,
                            amount: amount,
                            currency: currency,
                            payerId: payerId,
                            splitMemberIds: splitIds,
                            frequency: freq,
                            note: note,
                            startDate: startDate
                        )
                    }
                }
            }
        }
        .sheet(isPresented: $showingRecurringTemplatesSheet) {
            if let activeGroup = viewModel.group ?? Optional(initialGroup) {
                RecurringTemplatesListView(group: activeGroup, viewModel: viewModel)
            }
        }
        .sheet(isPresented: $showingRecordSettlementSheet) {
            if let activeGroup = viewModel.group ?? Optional(initialGroup) {
                RecordSettlementSheet(group: activeGroup) { payerId, payeeId, amount, currency, note in
                    Task {
                        _ = await viewModel.addSettlement(
                            payerId: payerId,
                            payeeId: payeeId,
                            amount: amount,
                            currency: currency,
                            note: note
                        )
                    }
                }
            }
        }
        .sheet(isPresented: $showingSimplifiedPaymentsSheet) {
            NavigationStack {
                SimplifiedPaymentsView(
                    lines: viewModel.simplifiedLines,
                    currency: viewModel.groupCurrency
                )
            }
        }
        .onAppear {
            viewModel.loadHistory()
            viewModel.loadRecurringTemplates()
        }
    }

    // MARK: - Group Header
    @ViewBuilder
    private var groupHeaderView: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.group?.name ?? initialGroup.name)
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundColor(.black)

                let count = viewModel.group?.members.count ?? initialGroup.members.count
                let eventCount = viewModel.events.count
                Text("\(count) MEMBERS · \(eventCount) EVENTS · BASE: \(viewModel.groupCurrency)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(white: 0.4))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("RUNNING BALANCE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(white: 0.4))

                let balance = viewModel.group?.runningBalance ?? initialGroup.runningBalance
                CurrencyText(
                    balance,
                    currency: viewModel.groupCurrency,
                    font: .system(size: 22, weight: .bold, design: .monospaced),
                    amountWeight: .bold,
                    codeWeight: .light
                )
                .foregroundColor(.black)
            }
        }
    }

    // MARK: - Continuous Debt Simplification Section
    @ViewBuilder
    private var simplifiedPaymentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text("SIMPLIFIED PAYMENTS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(white: 0.4))

                Spacer()

                Button(action: { showingSimplifiedPaymentsSheet = true }) {
                    HStack(spacing: 4) {
                        Text(viewModel.simplifiedTransfers.isEmpty ? "SETTLED" : "\(viewModel.simplifiedTransfers.count) DIRECT TRANSFERS")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 0.8))
                }
            }

            if viewModel.simplifiedTransfers.isEmpty {
                HStack {
                    Text("All balances are settled. No transfers needed.")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(white: 0.4))
                        .padding(.vertical, 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 6) {
                    ForEach(viewModel.simplifiedTransfers) { transfer in
                        HStack {
                            Text(transfer.fromName)
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundColor(.black)

                            Text("pays")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(Color(white: 0.4))

                            Text(transfer.toName)
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundColor(.black)

                            Spacer()

                            CurrencyText(
                                transfer.amount,
                                currency: transfer.currency,
                                font: .system(size: 14, weight: .bold, design: .monospaced),
                                amountWeight: .bold,
                                codeWeight: .light
                            )
                            .foregroundColor(.black)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white)
                        .overlay(Rectangle().stroke(Color.black.opacity(0.2), lineWidth: 0.5))
                    }
                }
            }
        }
    }

    // MARK: - Member Balances
    @ViewBuilder
    private var memberBalancesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MEMBER BALANCES")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(Color(white: 0.4))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(viewModel.memberBalances) { member in
                    HStack {
                        Text(member.name)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(.black)
                            .lineLimit(1)

                        Spacer()

                        CurrencyText(
                            member.balance,
                            currency: member.currency,
                            font: .system(size: 13, weight: .bold, design: .monospaced),
                            amountWeight: .bold,
                            codeWeight: .light
                        )
                        .foregroundColor(.black)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black.opacity(0.2), lineWidth: 0.5))
                }
            }
        }
    }

    // MARK: - Append-Only Event Stream Section
    @ViewBuilder
    private var eventStreamSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("APPEND-ONLY EVENT STREAM")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(white: 0.4))

                Spacer()

                Text("REPLAY ENGINE ACTIVE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.black)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(white: 0.96))

            Rectangle()
                .fill(Color.black.opacity(0.1))
                .frame(height: 0.5)

            if viewModel.events.isEmpty {
                VStack(spacing: 8) {
                    Text("NO EVENTS RECORDED")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(white: 0.4))
                        .padding(.top, 40)

                    Text("Add an expense or settlement to begin the append-only ledger.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color(white: 0.5))
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 40)
                }
                .frame(maxWidth: .infinity)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.events) { event in
                        ledgerEventRow(event)

                        Rectangle()
                            .fill(Color.black.opacity(0.12))
                            .frame(height: 0.5)
                    }
                }
            }
        }
    }

    // MARK: - Ledger Event Row
    @ViewBuilder
    private func ledgerEventRow(_ event: LedgerEvent) -> some View {
        let isRecurring = (event.note?.contains("[Recurring") == true)

        VStack(alignment: .leading, spacing: 8) {
            // Header: Type badge, Date, Amount
            HStack(alignment: .center) {
                if event.isExpense {
                    HStack(spacing: 4) {
                        Text("EXPENSE")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.black)

                        if isRecurring {
                            Text("RECURRING")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.black)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color(white: 0.92))
                                .overlay(Rectangle().stroke(Color.black, lineWidth: 0.8))
                        }
                    }
                } else {
                    Text("SETTLEMENT")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .border(Color.black, width: 1)
                }

                if let date = event.createdAt {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Color(white: 0.4))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    CurrencyText(
                        event.amount,
                        currency: event.effectiveCurrency,
                        font: .system(size: 16, weight: .bold, design: .monospaced),
                        amountWeight: .bold,
                        codeWeight: .light
                    )
                    .foregroundColor(.black)

                    if let converted = event.convertedAmount, event.effectiveCurrency != event.effectiveTargetCurrency {
                        HStack(spacing: 2) {
                            Text("≈")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(Color(white: 0.4))
                            CurrencyText(
                                converted,
                                currency: event.effectiveTargetCurrency,
                                font: .system(size: 10, weight: .medium, design: .monospaced),
                                amountWeight: .medium,
                                codeWeight: .light
                            )
                            .foregroundColor(Color(white: 0.4))
                        }
                    }
                }
            }

            // Title and Details
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(.black)

                if event.isExpense {
                    HStack(spacing: 4) {
                        Text("Paid by \(event.payerName)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Color(white: 0.3))

                        if !event.splits.isEmpty {
                            Text("·")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(Color(white: 0.4))
                            Text("Split \(event.splits.count) ways")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(Color(white: 0.4))
                        }
                    }
                } else {
                    if let payee = event.payeeName {
                        Text("\(event.payerName) paid \(payee)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Color(white: 0.3))
                    }
                }

                if let note = event.note, !note.isEmpty {
                    Text("Memo: \(note)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color(white: 0.4))
                        .italic()
                }
            }

            // Running Balance Snapshot
            if let running = event.runningBalanceAfter {
                HStack {
                    Spacer()
                    HStack(spacing: 4) {
                        Text("Running balance after:")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(Color(white: 0.4))
                        CurrencyText(
                            running,
                            currency: event.effectiveTargetCurrency,
                            font: .system(size: 10, weight: .medium, design: .monospaced),
                            amountWeight: .medium,
                            codeWeight: .light
                        )
                        .foregroundColor(Color(white: 0.4))
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.white)
    }

    // MARK: - Bottom Action Bar
    @ViewBuilder
    private var bottomActionBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.black)
                .frame(height: 1)

            HStack(spacing: 8) {
                Button(action: { showingAddExpenseSheet = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text("EXPENSE")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.black)
                }

                Button(action: { showingRecurringTemplatesSheet = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.arrow.2.circlepath")
                            .font(.system(size: 11, weight: .bold))
                        Text("RECURRING")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                }

                Button(action: { showingRecordSettlementSheet = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 11, weight: .bold))
                        Text("SETTLE")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.white)
        }
    }
}
