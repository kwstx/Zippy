// MARK: - SimplifiedPaymentsView.swift

import SwiftUI

/// Displays the reduced list of transfers calculated by the pure-Swift minimum-cash-flow algorithm running on Vapor.
/// Renders a minimalist pure white screen with black text lines titled “Simplified payments”.
struct SimplifiedPaymentsView: View {
    let lines: [String]
    @Environment(\.dismiss) private var dismiss

    init(lines: [String]) {
        self.lines = lines
    }

    init(transfers: [SimplifiedPayment]) {
        if transfers.isEmpty {
            self.lines = ["All balances are settled. No transfers needed."]
        } else {
            self.lines = transfers.map { $0.formattedText }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Title
                Text("Simplified payments")
                    .font(.system(size: 28, weight: .bold, design: .default))
                    .foregroundColor(.black)
                    .padding(.top, 24)
                    .padding(.bottom, 28)

                // Reduced list of black text lines
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(line)
                                .font(.system(size: 16, weight: .medium, design: .monospaced))
                                .foregroundColor(.black)
                                .padding(.vertical, 16)

                            if index < lines.count - 1 {
                                Rectangle()
                                    .fill(Color(white: 0.92))
                                    .frame(height: 1)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.white.ignoresSafeArea())
        .navigationTitle("Simplified payments")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.light)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    dismiss()
                }
                .foregroundColor(.black)
                .font(.system(.body, design: .monospaced))
            }
        }
    }
}

#Preview {
    NavigationView {
        SimplifiedPaymentsView(lines: [
            "Alice pays Bob $24.50",
            "Charlie pays Bob $18.00",
            "David pays Alice $12.25"
        ])
    }
}
