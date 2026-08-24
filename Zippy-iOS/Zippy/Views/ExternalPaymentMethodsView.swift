// MARK: - ExternalPaymentMethodsView.swift

import SwiftUI

/// Surface for external payment methods surfaced as a vertical stack of plain black text labels.
/// Follows the minimalist black-and-white aesthetic.
struct ExternalPaymentMethodsView: View {
    let participantId: UUID
    let participantName: String
    let amount: Double
    var currency: String = "USD"
    let token: String?
    let settlementStatus: SettlementStatus
    let selectedMethod: String?
    let onMethodSelected: (String) -> Void
    let onConfirmManual: () -> Void

    @State private var showingBankInstructions: Bool = false
    @State private var copiedField: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Stack of plain black text labels inside high-contrast white card
            VStack(alignment: .leading, spacing: 0) {
                // Section Title inside card
                Text("EXTERNAL PAYMENT METHODS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(white: 0.4))
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 8)

                // Vertical stack of plain black text labels
                paymentLabelRow(name: "Venmo") {
                    handleMethodTap("Venmo")
                }
                
                innerDivider()

                paymentLabelRow(name: "PayPal") {
                    handleMethodTap("PayPal")
                }

                innerDivider()

                paymentLabelRow(name: "Cash App") {
                    handleMethodTap("Cash App")
                }

                innerDivider()

                paymentLabelRow(name: "Bank transfer") {
                    handleMethodTap("Bank transfer")
                }
            }
            .background(Color.white)
            .overlay(
                Rectangle()
                    .stroke(Color.black, lineWidth: 1)
            )

            // Settlement Status Banners
            if settlementStatus == .settled {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.black)
                    Text("SETTLED · \(selectedMethod ?? "CONFIRMED")")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.black)
                    Spacer()
                }
                .padding(12)
                .background(Color.white)
                .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                .padding(.top, 10)
            } else if settlementStatus == .pendingConfirmation || selectedMethod != nil {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "clock")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                        Text("AWAITING CONFIRMATION")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                        Spacer()
                    }

                    Text("Selected: \(selectedMethod ?? "External method"). Awaiting webhook or confirmation.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color(white: 0.7))

                    Button(action: onConfirmManual) {
                        Text("Confirm Settlement Manually")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.white)
                    }
                }
                .padding(14)
                .background(Color(white: 0.15))
                .overlay(Rectangle().stroke(Color(white: 0.3), lineWidth: 0.5))
                .padding(.top, 10)
            }
        }
        .sheet(isPresented: $showingBankInstructions) {
            bankInstructionsSheet()
        }
    }

    // MARK: - Plain Black Text Label Row

    @ViewBuilder
    private func paymentLabelRow(name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(name)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundColor(.black)
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(Color(white: 0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func innerDivider() -> some View {
        Rectangle()
            .fill(Color(white: 0.88))
            .frame(height: 0.5)
            .padding(.horizontal, 16)
    }

    // MARK: - Action Handler

    private func handleMethodTap(_ method: String) {
        onMethodSelected(method)

        let formattedAmount = String(format: "%.2f", amount)
        let tokenPrefix = (token ?? "ZIPPY").prefix(6).uppercased()
        let reference = "ZIP-\(tokenPrefix)"
        let note = "Zippy Bill Split - \(participantName) (\(reference))"
        let encodedNote = note.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? note

        switch method {
        case "Venmo":
            if let venmoURL = URL(string: "venmo://paycharge?txn=pay&amount=\(formattedAmount)&note=\(encodedNote)"),
               UIApplication.shared.canOpenURL(venmoURL) {
                UIApplication.shared.open(venmoURL)
            } else if let webURL = URL(string: "https://venmo.com/") {
                UIApplication.shared.open(webURL)
            }

        case "PayPal":
            if let paypalURL = URL(string: "https://www.paypal.com/paypalme/zippysplit/\(formattedAmount)") {
                UIApplication.shared.open(paypalURL)
            }

        case "Cash App":
            if let cashAppURL = URL(string: "https://cash.app/$zippysplit/\(formattedAmount)") {
                UIApplication.shared.open(cashAppURL)
            }

        case "Bank transfer":
            showingBankInstructions = true

        default:
            break
        }
    }

    // MARK: - Bank Instructions Sheet

    @ViewBuilder
    private func bankInstructionsSheet() -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("DIRECT BANK TRANSFER (ACH / WIRE)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.black)
                        .padding(.top, 8)

                    Text("Transfer \(CurrencyText.plainText(amount, currency: currency)) using the details below. Status will flip to settled upon bank webhook confirmation or manual confirmation.")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(Color(white: 0.3))

                    Divider()

                    instructionRow(label: "Routing Number (ACH)", value: "021000021")
                    instructionRow(label: "Account Number", value: "9876543210")
                    instructionRow(label: "Account Name", value: "Zippy Split Host")
                    instructionRow(label: "Currency", value: currency)
                    instructionRow(label: "Reference Memo", value: "ZIP-\((token ?? "ZIPPY").prefix(6).uppercased())")

                    Divider()

                    Button(action: {
                        onConfirmManual()
                        showingBankInstructions = false
                    }) {
                        Text("I've Initiated This Transfer")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.black)
                    }
                    .padding(.top, 12)
                }
                .padding(20)
            }
            .background(Color.white.ignoresSafeArea())
            .navigationTitle("Bank Transfer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showingBankInstructions = false }
                        .foregroundColor(.black)
                }
            }
        }
    }

    @ViewBuilder
    private func instructionRow(label: String, value: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color(white: 0.4))
                Text(value)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.black)
            }
            Spacer()
            Button(action: {
                UIPasteboard.general.string = value
                copiedField = label
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    if copiedField == label { copiedField = nil }
                }
            }) {
                Text(copiedField == label ? "Copied" : "Copy")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 0.5))
            }
        }
        .padding(.vertical, 4)
    }
}
