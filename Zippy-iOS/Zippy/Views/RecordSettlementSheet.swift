// MARK: - RecordSettlementSheet.swift

import SwiftUI

struct RecordSettlementSheet: View {
    let group: PersistentGroup
    let onRecord: (UUID, UUID, Double, String?) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var payerId: UUID
    @State private var payeeId: UUID
    @State private var amountText: String = ""
    @State private var note: String = ""

    init(group: PersistentGroup, onRecord: @escaping (UUID, UUID, Double, String?) -> Void) {
        self.group = group
        self.onRecord = onRecord
        let first = group.members.first?.id ?? UUID()
        let second = group.members.count > 1 ? group.members[1].id : first
        _payerId = State(initialValue: first)
        _payeeId = State(initialValue: second)
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

                // Amount Field
                VStack(alignment: .leading, spacing: 6) {
                    Text("SETTLEMENT AMOUNT ($)")
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
        onRecord(payerId, payeeId, amount, trimmedNote.isEmpty ? nil : trimmedNote)
        dismiss()
    }
}
