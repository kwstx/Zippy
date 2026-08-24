// MARK: - AccountBadgeView.swift

import SwiftUI

/// A minimal black-and-white account badge displayed ONLY when the organizer is signed in.
/// Conforms to the stark minimalist monochrome aesthetic.
struct AccountBadgeView: View {
    @ObservedObject private var authService = AuthService.shared
    @State private var showingAccountSheet = false

    var body: some View {
        if authService.isAuthenticated, let user = authService.currentUser {
            Button(action: { showingAccountSheet = true }) {
                HStack(spacing: 5) {
                    // Small monochrome indicator dot
                    Circle()
                        .fill(Color.white)
                        .frame(width: 5, height: 5)

                    // Minimal uppercase label
                    Text(user.badgeLabel)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black)
                .overlay(
                    Rectangle()
                        .stroke(Color.black, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showingAccountSheet) {
                OrganizerAccountSheet()
            }
        }
    }
}
