// MARK: - AddLedgerExpenseSheet.swift

import SwiftUI

struct AddLedgerExpenseSheet: View {
    let group: PersistentGroup
    let onAdd: (String, Double, String, UUID, [UUID]?, String?) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var amountText: String = ""
    @State private var currency: String
    @State private var selectedPayerId: UUID
    @State private var selectedSplitMemberIds: Set<UUID>
    @State private var note: String = ""
    @State private var showingCurrencyPicker = false

    init(group: PersistentGroup, onAdd: @escaping (String, Double, String, UUID, [UUID]?, String?) -> Void) {
        self.group = group
        self.onAdd = onAdd
        let initialPayer = group.members.first?.id ?? UUID()
        _selectedPayerId = State(initialValue: initialPayer)
        _selectedSplitMemberIds = State(initialValue: Set(group.members.map { $0.id }))
        _currency = State(initialValue: group.currency ?? "USD")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Title Field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("DESCRIPTION")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(white: 0.3))

                        TextField("e.g. Groceries, Dinner, Utilities", text: $title)
                            .font(.system(size: 15, design: .monospaced))
                            .foregroundColor(.black)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .background(Color.white)
                            .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                    }

                    // Currency Picker Row
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("EXPENSE CURRENCY")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(white: 0.3))

                            HStack(spacing: 6) {
                                Text(currency)
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    .foregroundColor(.black)

                                Text(CurrencyRateService.symbol(for: currency))
                                    .font(.system(size: 13, weight: .light, design: .monospaced))
                                    .foregroundColor(Color(white: 0.5))
                            }
                        }

                        Spacer()

                        Button(action: { showingCurrencyPicker = true }) {
                            Text("CHANGE")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.black)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                        }
                    }
                    .padding(.vertical, 4)

                    // Amount Field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("AMOUNT (\(currency))")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(white: 0.3))

                        TextField("0.00", text: $amountText)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .foregroundColor(.black)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .background(Color.white)
                            .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                    }

                    // Payer Selection
                    VStack(alignment: .leading, spacing: 6) {
                        Text("PAID BY")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(white: 0.3))

                        Picker("Paid By", selection: $selectedPayerId) {
                            ForEach(group.members) { member in
                                Text(member.name).tag(member.id)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    // Split Members Selection
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("SPLIT EQUALLY WITH")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(white: 0.3))

                            Spacer()

                            Button(action: toggleAll) {
                                Text(selectedSplitMemberIds.count == group.members.count ? "DESELECT ALL" : "SELECT ALL")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(.black)
                            }
                        }

                        VStack(spacing: 6) {
                            ForEach(group.members) { member in
                                Button(action: {
                                    if selectedSplitMemberIds.contains(member.id) {
                                        if selectedSplitMemberIds.count > 1 {
                                            selectedSplitMemberIds.remove(member.id)
                                        }
                                    } else {
                                        selectedSplitMemberIds.insert(member.id)
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: selectedSplitMemberIds.contains(member.id) ? "checkmark.square.fill" : "square")
                                            .font(.system(size: 16))
                                            .foregroundColor(.black)

                                        Text(member.name)
                                            .font(.system(size: 14, design: .monospaced))
                                            .foregroundColor(.black)

                                        Spacer()

                                        if let amount = Double(amountText), amount > 0, selectedSplitMemberIds.contains(member.id) {
                                            let share = amount / Double(selectedSplitMemberIds.count)
                                            CurrencyText(
                                                share,
                                                currency: currency,
                                                font: .system(size: 13, weight: .medium, design: .monospaced),
                                                amountWeight: .medium,
                                                codeWeight: .light
                                            )
                                            .foregroundColor(Color(white: 0.4))
                                        }
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 12)
                                    .background(Color.white)
                                    .overlay(Rectangle().stroke(Color.black.opacity(0.2), lineWidth: 0.5))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Note Field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("NOTE (OPTIONAL)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(white: 0.3))

                        TextField("Add memo...", text: $note)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(.black)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(Color.white)
                            .overlay(Rectangle().stroke(Color.black.opacity(0.5), lineWidth: 1))
                    }

                    // Append to Ledger Button
                    Button(action: save) {
                        Text("RECORD EXPENSE")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(isValid ? Color.black : Color.gray)
                    }
                    .disabled(!isValid)
                    .padding(.top, 10)
                }
                .padding(20)
            }
            .background(Color.white.ignoresSafeArea())
            .navigationTitle("Add Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(.black)
                }
            }
            .sheet(isPresented: $showingCurrencyPicker) {
                currencyPickerSheet()
            }
        }
    }

    @ViewBuilder
    private func currencyPickerSheet() -> some View {
        NavigationStack {
            List {
                ForEach(CurrencyRateService.supportedCurrencies, id: \.self) { code in
                    Button(action: {
                        self.currency = code
                        showingCurrencyPicker = false
                    }) {
                        HStack {
                            Text(code)
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundColor(.black)

                            Text(CurrencyRateService.symbol(for: code))
                                .font(.system(size: 14, weight: .light, design: .monospaced))
                                .foregroundColor(Color(white: 0.5))

                            Spacer()

                            if currency == code {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.black)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Select Currency")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showingCurrencyPicker = false }
                        .foregroundColor(.black)
                }
            }
        }
    }

    private var isValid: Bool {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let amount = Double(amountText),
              amount > 0,
              !selectedSplitMemberIds.isEmpty else {
            return false
        }
        return true
    }

    private func toggleAll() {
        if selectedSplitMemberIds.count == group.members.count {
            if let first = group.members.first?.id {
                selectedSplitMemberIds = [first]
            }
        } else {
            selectedSplitMemberIds = Set(group.members.map { $0.id })
        }
    }

    private func save() {
        guard let amount = Double(amountText), amount > 0 else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        onAdd(
            trimmedTitle,
            amount,
            currency,
            selectedPayerId,
            Array(selectedSplitMemberIds),
            trimmedNote.isEmpty ? nil : trimmedNote
        )
        dismiss()
    }
}
