// MARK: - PaymentStatusView.swift

import SwiftUI

/// Pixel-perfect payment status screen featuring an ATM receipt dispenser slit,
/// a realistically dispensed trip invoice with participant statuses, timeline indicator,
/// reminder triggers, invoice downloads, and integrated Pay Now action.
struct PaymentStatusView: View {
    @StateObject private var viewModel: PaymentStatusViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingShareSheet: Bool = false
    @State private var showingDownloadAlert: Bool = false

    init(
        token: String? = nil,
        sessionId: UUID? = nil,
        invoiceTitle: String? = nil,
        initialBalances: [PersonBalance] = []
    ) {
        _viewModel = StateObject(
            wrappedValue: PaymentStatusViewModel(
                token: token,
                sessionId: sessionId,
                invoiceTitle: invoiceTitle,
                initialBalances: initialBalances
            )
        )
    }

    var body: some View {
        ZStack {
            // Screen Background
            Color(red: 0.965, green: 0.969, blue: 0.976)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - Top Custom Navigation Bar
                customNavigationBar()
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // MARK: - ATM Dispenser Slot & Emerged Receipt
                        dispenserAndReceiptView()
                            .padding(.horizontal, 20)

                        // MARK: - Bottom Details (Payment Method & Pay Now)
                        bottomPaymentDetails()
                            .padding(.horizontal, 20)
                            .padding(.top, 18)
                            .padding(.bottom, 32)
                    }
                }
            }
        }
        .task {
            // Background polling loop for live payment status updates
            while !Task.isCancelled {
                await viewModel.refreshStatus()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ZippySilentPaymentStatusSync"))) { notification in
            if let userInfo = notification.userInfo,
               let participantId = userInfo["participantId"] as? UUID,
               let isSettled = userInfo["isSettled"] as? Bool {
                viewModel.handleSilentPush(participantId: participantId, isSettled: isSettled)
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(activityItems: [
                "\(viewModel.invoiceTitle)\nTotal: \(viewModel.formattedTotal)\nStatus: \(viewModel.isFullySettled ? "PAID" : "UNPAID")"
            ])
        }
        .alert("Invoice Downloaded", isPresented: $showingDownloadAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Trip invoice for \(viewModel.invoiceTitle) has been generated successfully.")
        }
    }

    // MARK: - Top Custom Navigation Bar

    @ViewBuilder
    private func customNavigationBar() -> some View {
        HStack {
            // Left Circular Back Button
            Button(action: {
                dismiss()
            }) {
                Circle()
                    .fill(Color.white)
                    .frame(width: 40, height: 40)
                    .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
                    .overlay(
                        Image(systemName: "arrow.left")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Color(red: 0.12, green: 0.14, blue: 0.18))
                    )
            }

            Spacer()

            // Center Title
            Text("Payment Status")
                .font(.system(size: 19, weight: .bold))
                .foregroundColor(Color(red: 0.11, green: 0.13, blue: 0.17))

            Spacer()

            // Right Circular Share Button
            Button(action: {
                showingShareSheet = true
            }) {
                Circle()
                    .fill(Color.white)
                    .frame(width: 40, height: 40)
                    .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
                    .overlay(
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Color(red: 0.12, green: 0.14, blue: 0.18))
                            .offset(y: -1)
                    )
            }
        }
    }

    // MARK: - Dispenser Slot & Receipt

    @ViewBuilder
    private func dispenserAndReceiptView() -> some View {
        ZStack(alignment: .top) {
            // White Receipt Card (Sliding out from slot)
            receiptCardContent()
                .padding(.top, 24)

            // Dark Dispenser Slot at Top (ATM printer head)
            dispenserSlotHead()
        }
    }

    // MARK: - Dispenser Slot Head (Dark ATM slot)

    @ViewBuilder
    private func dispenserSlotHead() -> some View {
        ZStack(alignment: .bottom) {
            // Main dark rounded dispenser housing
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.22, green: 0.24, blue: 0.28),
                            Color(red: 0.15, green: 0.17, blue: 0.20)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .shadow(color: Color.black.opacity(0.18), radius: 10, x: 0, y: 5)

            // Inner dark recess slit where the paper emerges
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(red: 0.07, green: 0.08, blue: 0.10))
                .frame(maxWidth: .infinity)
                .frame(height: 12)
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
        }
    }

    // MARK: - Receipt Card Content (The Paper Invoice)

    @ViewBuilder
    private func receiptCardContent() -> some View {
        VStack(spacing: 0) {
            // Realistic top shadow cast by the slit over the emerging paper
            LinearGradient(
                colors: [
                    Color.black.opacity(0.35),
                    Color.black.opacity(0.12),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 28)

            VStack(spacing: 0) {
                // Top Dashed Line
                DashedDivider()
                    .padding(.top, 4)

                // Invoice Title (Monospaced)
                Text(viewModel.invoiceTitle)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundColor(Color(red: 0.22, green: 0.25, blue: 0.30))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 7)

                // Bottom Dashed Line
                DashedDivider()

                // Total & Per Person
                VStack(spacing: 8) {
                    HStack {
                        Text("Total")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(Color(red: 0.45, green: 0.48, blue: 0.53))
                        Spacer()
                        Text(viewModel.formattedTotal)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Color(red: 0.10, green: 0.12, blue: 0.16))
                    }

                    HStack {
                        Text("Per Person")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(Color(red: 0.45, green: 0.48, blue: 0.53))
                        Spacer()
                        Text(viewModel.formattedPerPerson)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Color(red: 0.10, green: 0.12, blue: 0.16))
                    }
                }
                .padding(.top, 16)
                .padding(.bottom, 18)

                // Participants List
                VStack(spacing: 14) {
                    ForEach(viewModel.participants) { participant in
                        participantRow(participant)
                    }
                }
                .padding(.bottom, 18)

                // Inner Payment Status Box & Progress Timeline
                paymentStatusInnerCard()

                // Status message notice if present
                if let msg = viewModel.reminderStatusMessage {
                    Text(msg)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(red: 0.10, green: 0.65, blue: 0.45))
                        .padding(.top, 10)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 22)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.10), radius: 20, x: 0, y: 10)
    }

    // MARK: - Participant Row

    @ViewBuilder
    private func participantRow(_ participant: PaymentStatusViewModel.ParticipantStatus) -> some View {
        HStack(alignment: .center, spacing: 12) {
            // Illustrated Avatar
            ParticipantAvatarView(style: participant.avatarStyle, name: participant.name)

            // Name
            Text(participant.name)
                .font(.system(size: 14.5, weight: .medium))
                .foregroundColor(Color(red: 0.13, green: 0.15, blue: 0.19))

            Spacer()

            // Status Pill Badge (Paid / Unpaid)
            if participant.isSettled {
                paidBadgeView()
            } else {
                unpaidBadgeView()
            }
        }
        .contentShape(Rectangle())
    }

    // MARK: - Badges

    @ViewBuilder
    private func paidBadgeView() -> some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Color(red: 0.13, green: 0.74, blue: 0.49))

            Text("Paid")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(red: 0.22, green: 0.26, blue: 0.32))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4.5)
        .background(Color.white)
        .overlay(
            Capsule()
                .stroke(Color(red: 0.89, green: 0.91, blue: 0.94), lineWidth: 1)
        )
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func unpaidBadgeView() -> some View {
        HStack(spacing: 5) {
            Image(systemName: "clock.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Color(red: 0.96, green: 0.45, blue: 0.18))

            Text("Unpaid")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(red: 0.22, green: 0.26, blue: 0.32))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4.5)
        .background(Color.white)
        .overlay(
            Capsule()
                .stroke(Color(red: 0.89, green: 0.91, blue: 0.94), lineWidth: 1)
        )
        .clipShape(Capsule())
    }

    // MARK: - Payment Status Inner Card

    @ViewBuilder
    private func paymentStatusInnerCard() -> some View {
        VStack(spacing: 14) {
            // Header Row
            HStack {
                Text("Payment Status")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(Color(red: 0.35, green: 0.38, blue: 0.43))

                Spacer()

                Text(viewModel.isFullySettled ? "PAID" : "UNPAID")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(red: 0.11, green: 0.13, blue: 0.17))
            }

            // Timeline / Step Progress Tracker
            statusTimelineBar()
                .padding(.vertical, 4)

            // Action Buttons (Send Reminder / Download Invoice)
            HStack(spacing: 12) {
                // Send Reminder Button
                Button(action: {
                    Task {
                        await viewModel.triggerReminders()
                    }
                }) {
                    HStack(spacing: 6) {
                        if viewModel.isTriggeringReminders {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                                .scaleEffect(0.7)
                        }
                        Text("Send Reminder")
                            .font(.system(size: 12.5, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(Color(red: 0.14, green: 0.16, blue: 0.21))
                    .clipShape(Capsule())
                }

                // Download Invoice Button
                Button(action: {
                    showingDownloadAlert = true
                }) {
                    Text("Download Invoice")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(Color(red: 0.14, green: 0.16, blue: 0.21))
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(Color.white)
                        .overlay(
                            Capsule()
                                .stroke(Color(red: 0.88, green: 0.89, blue: 0.92), lineWidth: 1)
                        )
                        .clipShape(Capsule())
                }
            }
        }
        .padding(14)
        .background(Color(red: 0.98, green: 0.98, blue: 0.99))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(red: 0.91, green: 0.92, blue: 0.95), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Status Timeline Bar

    @ViewBuilder
    private func statusTimelineBar() -> some View {
        HStack(spacing: 0) {
            // Node 1 (Green Checkmark)
            timelineCheckNode()

            // Bar 1 (Thick Dark Line)
            timelineDarkBar()

            // Node 2 (Green Checkmark)
            timelineCheckNode()

            // Bar 2 (Thick Dark Line)
            timelineDarkBar()

            // Node 3 (Green Checkmark)
            timelineCheckNode()

            // Bar 3 (Thick Dark Line)
            timelineDarkBar()

            // Node 4 (Active Dark Dot)
            timelineDarkNode()

            // Bar 4 (Light Gray Line)
            timelineLightBar()

            // Node 5 (Download / Invoice Icon)
            timelineDownloadNode()
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func timelineCheckNode() -> some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.13, green: 0.74, blue: 0.49).opacity(0.18))
                .frame(width: 22, height: 22)

            Circle()
                .fill(Color(red: 0.13, green: 0.74, blue: 0.49))
                .frame(width: 17, height: 17)

            Image(systemName: "checkmark")
                .font(.system(size: 8.5, weight: .bold))
                .foregroundColor(.white)
        }
    }

    @ViewBuilder
    private func timelineDarkNode() -> some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.14, green: 0.16, blue: 0.21).opacity(0.15))
                .frame(width: 22, height: 22)

            Circle()
                .fill(Color(red: 0.10, green: 0.12, blue: 0.16))
                .frame(width: 17, height: 17)
        }
    }

    @ViewBuilder
    private func timelineDownloadNode() -> some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: 22, height: 22)
                .overlay(
                    Circle()
                        .stroke(Color(red: 0.88, green: 0.89, blue: 0.92), lineWidth: 1)
                )

            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color(red: 0.35, green: 0.38, blue: 0.43))
        }
    }

    @ViewBuilder
    private func timelineDarkBar() -> some View {
        Rectangle()
            .fill(Color(red: 0.10, green: 0.12, blue: 0.16))
            .frame(height: 3.5)
            .clipShape(Capsule())
    }

    @ViewBuilder
    private func timelineLightBar() -> some View {
        Rectangle()
            .fill(Color(red: 0.88, green: 0.89, blue: 0.92))
            .frame(height: 2)
    }

    // MARK: - Bottom Payment Details (Payment Method & Pay Now Button)

    @ViewBuilder
    private func bottomPaymentDetails() -> some View {
        VStack(spacing: 14) {
            // Payment Method Row
            HStack {
                Text("Payment Method")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundColor(Color(red: 0.45, green: 0.48, blue: 0.53))

                Spacer()

                HStack(spacing: 8) {
                    Text(viewModel.paymentMethodText)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundColor(Color(red: 0.22, green: 0.26, blue: 0.32))

                    // Blue Visa Card Icon
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(red: 0.08, green: 0.24, blue: 0.78))
                        .frame(width: 28, height: 18)
                        .overlay(
                            Text("VISA")
                                .font(.system(size: 6.5, weight: .black, design: .rounded))
                                .italic()
                                .foregroundColor(.white)
                        )
                }
            }

            // Big Pay Now Action Button
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    viewModel.markCurrentUserPaid()
                }
            }) {
                Text("Pay Now")
                    .font(.system(size: 15.5, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color(red: 0.17, green: 0.19, blue: 0.24))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
            }
        }
    }
}

// MARK: - Dashed Divider Component

struct DashedDivider: View {
    var body: some View {
        Line()
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .foregroundColor(Color(red: 0.65, green: 0.68, blue: 0.73))
            .frame(height: 1)
    }
}

struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.width, y: rect.midY))
        return path
    }
}

// MARK: - Stylized Participant Avatar View

struct ParticipantAvatarView: View {
    let style: PaymentStatusViewModel.AvatarStyle
    let name: String

    var body: some View {
        ZStack {
            Circle()
                .fill(backgroundColor)
                .frame(width: 36, height: 36)
                .overlay(
                    Circle()
                        .stroke(Color(red: 0.88, green: 0.90, blue: 0.93), lineWidth: 1)
                )

            avatarIllustration()
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .turban:
            return Color(red: 0.98, green: 0.96, blue: 0.92)
        case .greenCap:
            return Color(red: 0.92, green: 0.97, blue: 0.94)
        case .redHair:
            return Color(red: 0.92, green: 0.95, blue: 0.99)
        case .purpleBun:
            return Color(red: 0.97, green: 0.93, blue: 0.98)
        case .purpleJacket:
            return Color(red: 0.94, green: 0.93, blue: 0.98)
        }
    }

    @ViewBuilder
    private func avatarIllustration() -> some View {
        switch style {
        case .turban:
            // "You" avatar: turban / wrap with patterned outfit
            ZStack {
                // Head
                Circle()
                    .fill(Color(red: 0.68, green: 0.45, blue: 0.32))
                    .frame(width: 14, height: 14)
                    .offset(y: -2)

                // Turban
                Ellipse()
                    .fill(Color(red: 0.85, green: 0.65, blue: 0.40))
                    .frame(width: 15, height: 10)
                    .offset(y: -7)

                // Body
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(red: 0.42, green: 0.25, blue: 0.18))
                    .frame(width: 18, height: 12)
                    .offset(y: 11)
            }
            .clipShape(Circle().size(width: 36, height: 36))

        case .greenCap:
            // "Olabode" avatar: Green cap with orange shirt
            ZStack {
                // Head
                Circle()
                    .fill(Color(red: 0.72, green: 0.50, blue: 0.35))
                    .frame(width: 14, height: 14)
                    .offset(y: -2)

                // Cap
                Capsule()
                    .fill(Color(red: 0.18, green: 0.65, blue: 0.38))
                    .frame(width: 16, height: 7)
                    .offset(y: -7)

                // Body / Shirt
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(red: 0.94, green: 0.52, blue: 0.18))
                    .frame(width: 18, height: 12)
                    .offset(y: 11)
            }
            .clipShape(Circle().size(width: 36, height: 36))

        case .redHair:
            // "Lukmon" avatar: Red hair with blue jacket
            ZStack {
                // Hair
                Circle()
                    .fill(Color(red: 0.85, green: 0.32, blue: 0.20))
                    .frame(width: 16, height: 16)
                    .offset(y: -4)

                // Face
                Circle()
                    .fill(Color(red: 0.96, green: 0.78, blue: 0.66))
                    .frame(width: 12, height: 12)
                    .offset(y: -1)

                // Body / Blue Jacket
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(red: 0.14, green: 0.42, blue: 0.85))
                    .frame(width: 18, height: 12)
                    .offset(y: 11)
            }
            .clipShape(Circle().size(width: 36, height: 36))

        case .purpleBun:
            // "Hope" avatar: Purple hair with bun and coral top
            ZStack {
                // Bun
                Circle()
                    .fill(Color(red: 0.38, green: 0.18, blue: 0.52))
                    .frame(width: 7, height: 7)
                    .offset(y: -11)

                // Hair
                Circle()
                    .fill(Color(red: 0.38, green: 0.18, blue: 0.52))
                    .frame(width: 16, height: 16)
                    .offset(y: -3)

                // Face
                Circle()
                    .fill(Color(red: 0.78, green: 0.55, blue: 0.42))
                    .frame(width: 12, height: 12)
                    .offset(y: -1)

                // Pink/Coral Top
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(red: 0.95, green: 0.52, blue: 0.58))
                    .frame(width: 18, height: 12)
                    .offset(y: 11)
            }
            .clipShape(Circle().size(width: 36, height: 36))

        case .purpleJacket:
            // "Dara" avatar: Dark short hair with royal blue jacket
            ZStack {
                // Hair
                Circle()
                    .fill(Color(red: 0.30, green: 0.20, blue: 0.40))
                    .frame(width: 15, height: 15)
                    .offset(y: -4)

                // Face
                Circle()
                    .fill(Color(red: 0.65, green: 0.42, blue: 0.30))
                    .frame(width: 12, height: 12)
                    .offset(y: -1)

                // Blue Jacket with orange collar
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(red: 0.35, green: 0.35, blue: 0.88))
                    .frame(width: 18, height: 12)
                    .offset(y: 11)
            }
            .clipShape(Circle().size(width: 36, height: 36))
        }
    }
}

