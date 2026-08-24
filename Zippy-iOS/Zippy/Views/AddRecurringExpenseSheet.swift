// MARK: - AddRecurringExpenseSheet.swift

import SwiftUI

/// Minimalist black-and-white form for defining recurring group expense templates.
/// Features a frequency picker with plain text options, strict monochrome styling,
/// and live split breakdown preview.
struct AddRecurringExpenseSheet: View {
    let group: PersistentGroup
    let onSave: (String, Double, String, UUID, [UUID]?, RecurringFrequency, String?, Date) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var amountText: String = ""
    @State private var currency: String
    @State private var selectedFrequency: RecurringFrequency = .monthly
    @State private var selectedPayerId: UUID
    @State private var selectedSplitMemberIds: Set<UUID>
    @State private var startDate: Date = Date()
    @State private var note: String = ""
    @State private var showingCurrencyPicker = false
    @State private var showingDatePicker = false

    init(
        group: PersistentGroup,
        onSave: @escaping (String, Double, String, UUID, [UUID]?, RecurringFrequency, String?, Date) -> Void
    ) {
        self.group = group
        self.onSave = onSave
        let initialPayer = group.members.first?.id ?? UUID()
        _selectedPayerId = State(initialValue: initialPayer)
        _selectedSplitMemberIds = State(initialValue: Set(group.members.map { $0.id }))
        _currency = State(initialValue: group.currency.isEmpty ? "USD" : group.currency)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header Subtitle Banner
                    VStack(alignment: .leading, spacing: 4) {
                        Text("RECURRING EXPENSE TEMPLATE")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.black)
                        Text("Stored on backend and cloned automatically into group ledger history on schedule.")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Color(white: 0.4))
                    }
                    .padding(.bottom, 4)

                    // 1. Description Field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("DESCRIPTION")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(white: 0.3))

                        TextField("e.g. Rent, Internet, Netflix, Utilities", text: $title)
                            .font(.system(size: 15, design: .monospaced))
                            .foregroundColor(.black)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .background(Color.white)
                            .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                    }

                    // 2. Frequency Picker (Plain Text Options)
                    frequencyPickerSection

                    // 3. Currency & Amount Row
                    HStack(spacing: 12) {
                        // Currency Selector
                        VStack(alignment: .leading, spacing: 6) {
                            Text("CURRENCY")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(white: 0.3))

                            Button(action: { showingCurrencyPicker = true }) {
                                HStack {
                                    Text(currency)
                                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                                        .foregroundColor(.black)

                                    Spacer()

                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.black)
                                }
                                .padding(.vertical, 11)
                                .padding(.horizontal, 10)
                                .background(Color.white)
                                .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                            }
                        }
                        .frame(width: 110)

                        // Amount Field
                        VStack(alignment: .leading, spacing: 6) {
                            Text("AMOUNT (\(currency))")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(white: 0.3))

                            TextField("0.00", text: $amountText)
                                .keyboardType(.decimalPad)
                                .font(.system(size: 18, weight: .bold, design: .monospaced))
                                .foregroundColor(.black)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 12)
                                .background(Color.white)
                                .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                        }
                    }

                    // 4. Start / First Occurrence Date
                    firstOccurrenceSection

                    // 5. Payer Selection
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

                    // 6. Split Members Selection with Live Share Calculation
                    splitMembersSection

                    // 7. Memo / Note (Optional)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("MEMO / NOTE (OPTIONAL)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(white: 0.3))

                        TextField("e.g. Due on the 1st of every month", text: $note)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(.black)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(Color.white)
                            .overlay(Rectangle().stroke(Color.black.opacity(0.5), lineWidth: 1))
                    }

                    // 8. Save Button
                    Button(action: save) {
                        HStack(spacing: 8) {
                            Image(systemName: "clock.arrow.2.circlepath")
                                .font(.system(size: 13, weight: .bold))
                            Text("SAVE RECURRING TEMPLATE")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(isValid ? Color.black : Color.gray)
                    }
                    .disabled(!isValid)
                    .padding(.top, 8)
                }
                .padding(20)
            }
            .background(Color.white.ignoresSafeArea())
            .navigationTitle("New Recurring Expense")
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

    // MARK: - Frequency Picker (Plain Text Options)
    @ViewBuilder
    private var frequencyPickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("FREQUENCY")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(white: 0.3))

                Spacer()

                Text(selectedFrequency.title.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.black)
            }

            // Plain text frequency buttons
            HStack(spacing: 6) {
                ForEach(RecurringFrequency.allCases) { freq in
                    Button(action: {
                        selectedFrequency = freq
                    }) {
                        Text(freq.title)
                            .font(.system(size: 11, weight: selectedFrequency == freq ? .bold : .medium, design: .monospaced))
                            .foregroundColor(selectedFrequency == freq ? .white : .black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(selectedFrequency == freq ? Color.black : Color.white)
                            .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            // Descriptive schedule helper text
            HStack(spacing: 6) {
                Image(systemName: "repeat")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(white: 0.4))

                Text(selectedFrequency.cadenceDescription)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color(white: 0.4))
            }
            .padding(.top, 2)
        }
    }

    // MARK: - First Occurrence Section
    @ViewBuilder
    private var firstOccurrenceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FIRST OCCURRENCE")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(Color(white: 0.3))

            HStack(spacing: 8) {
                // Quick preset: Today
                Button(action: { startDate = Date() }) {
                    Text("TODAY")
                        .font(.system(size: 10, weight: Calendar.current.isDateInToday(startDate) ? .bold : .regular, design: .monospaced))
                        .foregroundColor(Calendar.current.isDateInToday(startDate) ? .white : .black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Calendar.current.isDateInToday(startDate) ? Color.black : Color.white)
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 0.8))
                }
                .buttonStyle(.plain)

                // Quick preset: 1st of next month
                Button(action: setFirstOfNextMonth) {
                    Text("1ST OF NEXT MONTH")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white)
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 0.8))
                }
                .buttonStyle(.plain)

                Spacer()

                // Native Date Picker with plain monochrome styling
                DatePicker("", selection: $startDate, displayedComponents: .date)
                    .labelsHidden()
                    .colorScheme(.light)
            }
        }
    }

    // MARK: - Split Members Section
    @ViewBuilder
    private var splitMembersSection: some View {
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
    }

    // MARK: - Currency Picker Sheet
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
                        .font(.system(size: 14, design: .monospaced))
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

    private func setFirstOfNextMonth() {
        let calendar = Calendar.current
        var comps = calendar.dateComponents([.year, .month], from: Date())
        comps.month = (comps.month ?? 1) + 1
        comps.day = 1
        if let nextDate = calendar.date(from: comps) {
            startDate = nextDate
        }
    }

    private func save() {
        guard let amount = Double(amountText), amount > 0 else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave(
            trimmedTitle,
            amount,
            currency,
            selectedPayerId,
            Array(selectedSplitMemberIds),
            selectedFrequency,
            trimmedNote.isEmpty ? nil : trimmedNote,
            startDate
        )
        dismiss()
    }
}
