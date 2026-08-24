// MARK: - PaywallCardView.swift

import SwiftUI
import StoreKit

/// A single minimalist black-and-white paywall card.
/// Contains strictly and only the text "Pro" and a thin black "Upgrade" button
/// that opens the native StoreKit sheet without any additional visual noise.
struct PaywallCardView: View {
    @ObservedObject var subscriptionManager = SubscriptionManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Single black-and-white card
            VStack(spacing: 48) {
                // Strictly only the words "Pro"
                Text("Pro")
                    .font(.system(size: 44, weight: .bold, design: .monospaced))
                    .foregroundColor(.black)
                    .tracking(2)

                // Thin black "Upgrade" button
                Button(action: {
                    Task {
                        await subscriptionManager.purchasePro()
                    }
                }) {
                    HStack {
                        if subscriptionManager.isPurchasing || subscriptionManager.isLoading {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.black)
                                .scaleEffect(0.8)
                        } else {
                            Text("Upgrade")
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                                .foregroundColor(.black)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white)
                    .overlay(
                        Rectangle()
                            .stroke(Color.black, lineWidth: 1)
                    )
                }
                .disabled(subscriptionManager.isPurchasing || subscriptionManager.isLoading)
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 48)
            .background(Color.white)
            .overlay(
                Rectangle()
                    .stroke(Color.black, lineWidth: 1)
            )
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.ignoresSafeArea())
    }
}

#Preview {
    PaywallCardView()
}
