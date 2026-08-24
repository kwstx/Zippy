// MARK: - RecordSettlementSheet.swift

import SwiftUI

struct RecordSettlementSheet: View {
    let group: PersistentGroup
    let onRecord: (UUID, UUID, Double, String, String?) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var payerId: UUID
    @State private var payeeId: UUID
    @State private var amountText: String = ""
    @State private var currency: String
    @State private var note: String = ""
    @State private var showingCurrencyPicker = false

    init(group: PersistentGroup, onRecord: @escaping (UUID, UUID, Double, String, String?) -> Void) {
        self.group = group
        self.onRecord = onRecord
        let first = group.members.first?.id ?? UUID()
        let second = group.members.count > 1 ? group.members[1].id : first
        _payerId = State(initialValue: first)
        _payeeId = State(initialValue: second)
        _currency = State(initialValue: group.currency)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                // Payer Field
                VStack(alignment: .leading, spacing: 6) {
                    Text("FROM (PAYER)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(white: 0.3))

                    Picker("From", selection: $payerId) {
                        ForEach(group.members) { member in
                            Text(member.name).tag(member.id)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // Payee Field
                VStack(alignment: .leading, spacing: 6) {
                    Text("TO (RECIPIENT)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(white: 0.3))

                    Picker("To", selection: $payeeId) {
                        ForEach(group.members) { member in
                            Text(member.name).tag(member.id)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // Currency Row
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SETTLEMENT CURRENCY")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(white: 0.3))

                        HStack(spacing: 6) {
                            Text(currency)
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundColor(.black)

                            Text(CurrencyRateService.name(for: currency))
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
                .padding(.vertical, 2)

                // Amount Field
                VStack(alignment: .leading, spacing: 6) {
                    Text("SETTLEMENT AMOUNT (\(currency))")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(white: 0.3))

                    TextField("0.00", text: $amountText)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundColor(.black)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .background(Color.white)
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                }

                // Note Field
                VStack(alignment: .leading, spacing: 6) {
                    Text("MEMO / NOTE (OPTIONAL)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(white: 0.3))

                    TextField("e.g. Venmo transfer, cash", text: $note)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.black)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color.white)
                        .overlay(Rectangle().stroke(Color.black.opacity(0.5), lineWidth: 1))
                }

                Spacer()

                // Submit Button
                Button(action: save) {
                    Text("RECORD SETTLEMENT")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(isValid ? Color.black : Color.gray)
                }
                .disabled(!isValid)
            }
            .padding(20)
            .background(Color.white.ignoresSafeArea())
            .navigationTitle("Record Settlement")
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
        guard let amount = Double(amountText),
              amount > 0,
              payerId != payeeId else {
            return false
        }
        return true
    }

    private func save() {
        guard let amount = Double(amountText), amount > 0, payerId != payeeId else { return }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        onRecord(payerId, payeeId, amount, currency, trimmedNote.isEmpty ? nil : trimmedNote)
        dismiss()
    }
}
