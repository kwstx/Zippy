// MARK: - PaywallSheetView.swift

import SwiftUI
import StoreKit

/// Presentation sheet wrapper for PaywallCardView with a minimal close button.
struct PaywallSheetView: View {
    @ObservedObject var subscriptionManager = SubscriptionManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PaywallCardView(subscriptionManager: subscriptionManager)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            dismiss()
                        }
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(.black)
                    }
                }
        }
    }
}

/// View modifier for gating views behind Pro tier.
struct ProGatedModifier: ViewModifier {
    @ObservedObject var subscriptionManager = SubscriptionManager.shared
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                PaywallSheetView(subscriptionManager: subscriptionManager)
            }
    }
}

extension View {
    func paywallSheet(isPresented: Binding<Bool>) -> some View {
        self.modifier(ProGatedModifier(isPresented: isPresented))
    }
}
