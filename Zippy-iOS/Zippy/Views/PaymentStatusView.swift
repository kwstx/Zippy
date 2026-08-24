// MARK: - PaymentStatusView.swift

import SwiftUI

/// Minimalist pure white status screen displaying only a black checkmark or an empty black circle
/// next to each participant name.
struct PaymentStatusView: View {
    @StateObject private var viewModel: PaymentStatusViewModel
    @Environment(\.dismiss) private var dismiss

    init(token: String? = nil, sessionId: UUID? = nil, initialBalances: [PersonBalance] = []) {
        _viewModel = StateObject(
            wrappedValue: PaymentStatusViewModel(
                token: token,
                sessionId: sessionId,
                initialBalances: initialBalances
            )
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top thin black divider
                Rectangle()
                    .fill(Color.black)
                    .frame(height: 1)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Section header
                        HStack {
                            Text("PARTICIPANTS")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(white: 0.4))
                                .padding(.top, 24)
                                .padding(.bottom, 12)
                            Spacer()
                        }
                        .padding(.horizontal, 24)

                        // Participant rows
                        if viewModel.participants.isEmpty {
                            VStack(spacing: 8) {
                                Text("NO PARTICIPANTS")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(Color(white: 0.4))
                                    .padding(.top, 40)
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(viewModel.participants) { participant in
                                    participantStatusRow(participant)

                                    Rectangle()
                                        .fill(Color(white: 0.9))
                                        .frame(height: 0.5)
                                }
                            }
                            .padding(.horizontal, 24)
                        }

                        // Optional reminder feedback message
                        if let msg = viewModel.reminderStatusMessage {
                            Text(msg)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.black)
                                .padding(.top, 20)
                                .padding(.horizontal, 24)
                        }

                        if let err = viewModel.errorMessage {
                            Text(err)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.black)
                                .padding(.top, 20)
                                .padding(.horizontal, 24)
                        }
                    }
                }
                .background(Color.white)
            }
            .background(Color.white.ignoresSafeArea())
            .navigationTitle("Payment Status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.black)
                }

                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        Task {
                            await viewModel.triggerReminders()
                        }
                    }) {
                        if viewModel.isTriggeringReminders {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.black)
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "bell")
                                    .font(.system(size: 12, design: .monospaced))
                                Text("Remind")
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            }
                            .foregroundColor(.black)
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
        }
    }

    // MARK: - Participant Row
    // Displays strictly the participant name and only a black checkmark or empty black circle

    @ViewBuilder
    private func participantStatusRow(_ participant: PaymentStatusViewModel.ParticipantStatus) -> some View {
        HStack(alignment: .center) {
            Text(participant.name)
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundColor(.black)

            Spacer()

            if participant.isSettled {
                // Settled: Black checkmark
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.black)
                    .frame(width: 24, height: 24)
            } else {
                // Unsettled: Empty black circle
                Image(systemName: "circle")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.black)
                    .frame(width: 24, height: 24)
            }
        }
        .padding(.vertical, 16)
        .contentShape(Rectangle())
    }
}
