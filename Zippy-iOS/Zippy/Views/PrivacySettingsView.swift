// MARK: - PrivacySettingsView.swift

import SwiftUI

/// Privacy and data controls screen.
/// Renders a minimalist black-and-white settings list of plain text toggles
/// and a single "Delete all data" button.
/// Each action triggers an authenticated DELETE or PATCH on the Vapor API
/// that permanently removes the associated records and object-storage files.
struct PrivacySettingsView: View {
    @StateObject private var viewModel = PrivacySettingsViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top boundary hairline
                Rectangle()
                    .fill(Color.black)
                    .frame(height: 1.0)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Section Header
                        sectionHeader("DATA STORAGE & OBJECT RETENTION")
                            .padding(.top, 20)
                            .padding(.horizontal, 20)

                        // Plain text toggles
                        plainTextToggleRow(
                            title: "Store receipt image files",
                            subtitle: "Keep uploaded receipt photos in object storage after AI text extraction",
                            isOn: viewModel.storeReceiptImages,
                            key: .storeReceiptImages
                        )

                        hairlineDivider()

                        plainTextToggleRow(
                            title: "Retain receipt history",
                            subtitle: "Save parsed receipt items, subtotals, and timestamps in PostgreSQL",
                            isOn: viewModel.retainReceiptHistory,
                            key: .retainReceiptHistory
                        )

                        hairlineDivider()

                        plainTextToggleRow(
                            title: "Retain split sessions",
                            subtitle: "Save item assignments, custom shares, and guest settlement links",
                            isOn: viewModel.retainSplitSessions,
                            key: .retainSplitSessions
                        )

                        hairlineDivider()

                        plainTextToggleRow(
                            title: "Retain group ledgers",
                            subtitle: "Maintain append-only ledger transaction history and recurring templates",
                            isOn: viewModel.retainGroupLedgers,
                            key: .retainGroupLedgers
                        )

                        // Section Header
                        sectionHeader("NOTIFICATIONS & DIAGNOSTICS")
                            .padding(.top, 28)
                            .padding(.horizontal, 20)

                        plainTextToggleRow(
                            title: "Automated payment reminders",
                            subtitle: "Allow background worker to record reminder logs and trigger notifications",
                            isOn: viewModel.allowAutomatedReminders,
                            key: .allowAutomatedReminders
                        )

                        hairlineDivider()

                        plainTextToggleRow(
                            title: "Anonymous telemetry",
                            subtitle: "Help improve AI receipt extraction performance with anonymized diagnostics",
                            isOn: viewModel.telemetryAndAnalytics,
                            key: .telemetryAndAnalytics
                        )

                        hairlineDivider()

                        // Information Box
                        VStack(alignment: .leading, spacing: 6) {
                            Text("SECURITY & DELETION POLICY")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.black)

                            Text("Disabling any toggle immediately issues an authenticated PATCH to the Vapor backend, permanently erasing all associated database rows and purging underlying receipt image files from object storage.")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(Color(white: 0.35))
                                .lineSpacing(3)
                        }
                        .padding(16)
                        .background(Color(white: 0.96))
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 1.0))
                        .padding(.horizontal, 20)
                        .padding(.top, 28)

                        // Single "Delete all data" button
                        VStack(alignment: .leading, spacing: 10) {
                            sectionHeader("ACCOUNT WIPE")

                            Button(action: {
                                viewModel.requestDeleteAllData()
                            }) {
                                HStack {
                                    Image(systemName: "trash")
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    Text("Delete all data")
                                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.black)
                            }
                            .disabled(viewModel.isProcessing)

                            Text("Permanently removes all receipts, object-storage images, split sessions, group ledgers, payment logs, and your subscription record. This cannot be undone.")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(Color(white: 0.45))
                                .lineSpacing(2)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 28)
                        .padding(.bottom, 40)
                    }
                }

                // Processing & Status Banner
                if viewModel.isProcessing || viewModel.isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.black)
                            .scaleEffect(0.8)
                        Text("UPDATING PRIVACY CONTROLS...")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.black)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color(white: 0.92))
                    .border(Color.black, width: 1.0)
                } else if let message = viewModel.statusMessage {
                    HStack {
                        Text(message.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(viewModel.statusIsError ? Color.black : Color.black)
                            .lineLimit(2)
                        Spacer()
                        Button(action: { viewModel.statusMessage = nil }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.black)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(white: 0.94))
                    .border(Color.black, width: 1.0)
                }

                // Bottom boundary hairline
                Rectangle()
                    .fill(Color.black)
                    .frame(height: 1.0)
            }
            .background(Color.white.ignoresSafeArea())
            .navigationTitle("Privacy & Data Controls")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundColor(.black)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                }

                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        Task { await viewModel.loadControls() }
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.black)
                    }
                }
            }
            // Confirmation alert for toggling OFF destructive retention settings
            .alert("Confirm Deletion", isPresented: $viewModel.showToggleOffConfirmation) {
                Button("Delete & Disable", role: .destructive) {
                    viewModel.confirmToggleOff()
                }
                Button("Cancel", role: .cancel) {
                    viewModel.cancelToggleOff()
                }
            } message: {
                if let target = viewModel.pendingToggleTarget {
                    Text(target.warningMessage)
                }
            }
            // Confirmation alert for "Delete all data"
            .alert("Delete All Data?", isPresented: $viewModel.showDeleteAllConfirmation) {
                Button("Permanently Delete Everything", role: .destructive) {
                    viewModel.confirmDeleteAllData()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This action will immediately and irreversibly delete all your receipts, object-storage images, groups, splits, and reminder records from the server.")
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(Color(white: 0.45))
            .padding(.bottom, 10)
    }

    @ViewBuilder
    private func hairlineDivider() -> some View {
        Rectangle()
            .fill(Color.black.opacity(0.12))
            .frame(height: 0.5)
            .padding(.horizontal, 20)
    }

    /// Plain text toggle row styled strictly in black-and-white
    @ViewBuilder
    private func plainTextToggleRow(
        title: String,
        subtitle: String,
        isOn: Bool,
        key: PrivacySettingsViewModel.ToggleKey
    ) -> some View {
        Button(action: {
            viewModel.handleToggleChange(for: key, newValue: !isOn)
        }) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(.black)

                    Text(subtitle)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color(white: 0.45))
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                // Plain text toggle badge
                Text(isOn ? "[ ON ]" : "[ OFF ]")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(isOn ? .white : .black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(isOn ? Color.black : Color.white)
                    .border(Color.black, width: 1.0)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isProcessing)
    }
}
