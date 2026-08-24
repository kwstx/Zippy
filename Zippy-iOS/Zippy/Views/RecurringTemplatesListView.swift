// MARK: - RecurringTemplatesListView.swift

import SwiftUI

/// Minimalist black-and-white sheet displaying configured recurring expense templates.
/// Allows pausing/resuming, deleting, manually triggering cron evaluation, and adding new templates.
struct RecurringTemplatesListView: View {
    let group: PersistentGroup
    @ObservedObject var viewModel: GroupLedgerViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showingAddSheet = false
    @State private var isProcessingCron = false
    @State private var statusMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header summary banner
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SCHEDULED TEMPLATES")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(white: 0.3))

                        Text("\(viewModel.recurringTemplates.count) ACTIVE / CONFIGURED")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.black)
                    }

                    Spacer()

                    Button(action: triggerCronJob) {
                        HStack(spacing: 4) {
                            if isProcessingCron {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .scaleEffect(0.6)
                            } else {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 9))
                            }
                            Text("RUN CRON NOW")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                        }
                        .foregroundColor(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                    }
                    .disabled(isProcessingCron)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(Color(white: 0.97))

                Rectangle()
                    .fill(Color.black)
                    .frame(height: 1)

                if let message = statusMessage {
                    Text(message)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.black)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 20)
                        .background(Color(white: 0.92))
                }

                if viewModel.recurringTemplates.isEmpty {
                    emptyTemplatesView
                } else {
                    templatesList
                }

                // Bottom Action: Add Template Button
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.black)
                        .frame(height: 1)

                    Button(action: { showingAddSheet = true }) {
                        HStack {
                            Image(systemName: "plus")
                            Text("NEW RECURRING TEMPLATE")
                        }
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.black)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.white)
                }
            }
            .background(Color.white.ignoresSafeArea())
            .navigationTitle("Recurring Expenses")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(.black)
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddRecurringExpenseSheet(group: group) { title, amount, currency, payerId, splitIds, freq, note, startDate in
                    Task {
                        _ = await viewModel.addRecurringExpense(
                            title: title,
                            amount: amount,
                            currency: currency,
                            payerId: payerId,
                            splitMemberIds: splitIds,
                            frequency: freq,
                            note: note,
                            startDate: startDate
                        )
                    }
                }
            }
            .onAppear {
                viewModel.loadRecurringTemplates()
            }
        }
    }

    // MARK: - Empty State
    @ViewBuilder
    private var emptyTemplatesView: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "clock.arrow.2.circlepath")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(Color(white: 0.4))

            Text("NO RECURRING TEMPLATES")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(.black)

            Text("Define subscriptions, rent, or recurring bills. The backend cron-like job will automatically clone them into new expense records in group history.")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Color(white: 0.4))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Templates List
    @ViewBuilder
    private var templatesList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.recurringTemplates) { template in
                    templateRow(template)

                    Rectangle()
                        .fill(Color.black.opacity(0.15))
                        .frame(height: 0.5)
                }
            }
        }
    }

    // MARK: - Template Row
    @ViewBuilder
    private func templateRow(_ template: RecurringExpenseTemplate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(template.frequencyEnum.shortCode)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(template.isActive ? .white : Color(white: 0.4))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(template.isActive ? Color.black : Color(white: 0.9))
                            .overlay(Rectangle().stroke(Color.black, lineWidth: template.isActive ? 0 : 0.5))

                        Text(template.title)
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(template.isActive ? .black : Color(white: 0.5))
                    }

                    HStack(spacing: 4) {
                        Text("Paid by \(template.payerName)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Color(white: 0.4))

                        Text("·")
                            .foregroundColor(Color(white: 0.4))

                        Text("Next: \(template.nextDueDate.formatted(date: .abbreviated, time: .omitted))")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(Color(white: 0.3))
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    CurrencyText(
                        template.amount,
                        currency: template.currency,
                        font: .system(size: 15, weight: .bold, design: .monospaced),
                        amountWeight: .bold,
                        codeWeight: .light
                    )
                    .foregroundColor(template.isActive ? .black : Color(white: 0.5))

                    Text("\(template.occurrencesGenerated) generated")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(Color(white: 0.5))
                }
            }

            if let note = template.note, !note.isEmpty {
                Text(note)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color(white: 0.4))
                    .italic()
            }

            // Action row (Pause/Resume, Delete)
            HStack(spacing: 12) {
                Button(action: {
                    Task {
                        await viewModel.toggleRecurringExpense(templateId: template.id)
                    }
                }) {
                    Text(template.isActive ? "PAUSE" : "RESUME")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 0.7))
                }

                Button(action: {
                    Task {
                        await viewModel.deleteRecurringExpense(templateId: template.id)
                    }
                }) {
                    Text("DELETE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(white: 0.4))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .overlay(Rectangle().stroke(Color(white: 0.4), lineWidth: 0.7))
                }

                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.white)
    }

    private func triggerCronJob() {
        isProcessingCron = true
        statusMessage = "Executing backend cron clone scan..."
        Task {
            let clonedCount = await viewModel.processRecurringCronJob()
            isProcessingCron = false
            if clonedCount > 0 {
                statusMessage = "Successfully cloned \(clonedCount) expense(s) into history."
            } else {
                statusMessage = "All recurring templates up-to-date. Next run on schedule."
            }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            statusMessage = nil
        }
    }
}
