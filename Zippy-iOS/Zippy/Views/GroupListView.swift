// MARK: - GroupListView.swift

import SwiftUI

/// A minimalist black-and-white list of persistent groups on pure white rows.
/// Each row displays strictly and only the group title and a single monochrome balance figure.
/// Selecting a group navigates to its append-only ledger history loaded from the backend.
struct GroupListView: View {
    @StateObject private var viewModel = GroupListViewModel()
    @State private var showingCreateGroupSheet = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top border line
                Rectangle()
                    .fill(Color.black)
                    .frame(height: 1)

                if viewModel.isLoading && viewModel.groups.isEmpty {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.black)
                    Text("Loading groups...")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.black)
                        .padding(.top, 8)
                    Spacer()
                } else if viewModel.groups.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Text("NO GROUPS YET")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.black)

                        Text("Create a group to track shared expenses and running balances.")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(Color(white: 0.4))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)

                        Button(action: { showingCreateGroupSheet = true }) {
                            Text("+ NEW GROUP")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(Color.black)
                        }
                        .padding(.top, 8)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(viewModel.groups) { group in
                                NavigationLink(destination: GroupLedgerDetailView(group: group)) {
                                    groupRow(group)
                                }
                                .buttonStyle(.plain)

                                // Crisp black-and-white hairline divider
                                Rectangle()
                                    .fill(Color.black.opacity(0.12))
                                    .frame(height: 0.5)
                            }
                        }
                    }
                    .refreshable {
                        viewModel.loadGroups()
                    }
                }

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.red)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                }

                // Bottom border line
                Rectangle()
                    .fill(Color.black)
                    .frame(height: 1)
            }
            .background(Color.white.ignoresSafeArea())
            .navigationTitle("Groups")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(.black)
                }

                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingCreateGroupSheet = true }) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(.black)
                    }
                }
            }
            .sheet(isPresented: $showingCreateGroupSheet) {
                CreateGroupSheet { name, members in
                    Task {
                        _ = await viewModel.createGroup(name: name, members: members)
                    }
                }
            }
            .onAppear {
                viewModel.loadGroups()
            }
        }
    }

    // MARK: - Group Row
    // Pure white row showing ONLY the group title and a single monochrome balance figure.
    @ViewBuilder
    private func groupRow(_ group: PersistentGroup) -> some View {
        HStack(alignment: .center) {
            // Group Title
            Text(group.name)
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundColor(.black)
                .lineLimit(1)

            Spacer()

            // Single Monochrome Balance Figure
            Text(group.formattedBalance)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(.black)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(Color.white)
        .contentShape(Rectangle())
    }
}

// MARK: - Create Group Sheet
struct CreateGroupSheet: View {
    let onSave: (String, [Participant]) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var groupName: String = ""
    @State private var memberName: String = ""
    @State private var members: [Participant] = [
        Participant(name: "Me")
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Group Name Input
                VStack(alignment: .leading, spacing: 6) {
                    Text("GROUP NAME")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(white: 0.3))

                    TextField("e.g. Apartment 4B, Road Trip", text: $groupName)
                        .font(.system(size: 15, design: .monospaced))
                        .foregroundColor(.black)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .background(Color.white)
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)

                // Member Roster
                VStack(alignment: .leading, spacing: 8) {
                    Text("MEMBERS")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(white: 0.3))

                    HStack(spacing: 8) {
                        TextField("Add member name", text: $memberName)
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundColor(.black)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(Color.white)
                            .overlay(Rectangle().stroke(Color.black.opacity(0.5), lineWidth: 1))

                        Button(action: addMember) {
                            Text("ADD")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Color.black)
                        }
                        .disabled(memberName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    // Members List
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(members) { member in
                                HStack {
                                    Text(member.name)
                                        .font(.system(size: 14, design: .monospaced))
                                        .foregroundColor(.black)

                                    Spacer()

                                    if members.count > 1 {
                                        Button(action: {
                                            members.removeAll(where: { $0.id == member.id })
                                        }) {
                                            Image(systemName: "xmark")
                                                .font(.system(size: 12, design: .monospaced))
                                                .foregroundColor(Color(white: 0.5))
                                        }
                                    }
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(Color.white)
                                .overlay(Rectangle().stroke(Color.black.opacity(0.2), lineWidth: 0.5))
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)

                Spacer()

                // Action Buttons
                Button(action: save) {
                    Text("CREATE GROUP")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : Color.black)
                }
                .disabled(groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .background(Color.white.ignoresSafeArea())
            .navigationTitle("New Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(.black)
                }
            }
        }
    }

    private func addMember() {
        let trimmed = memberName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        members.append(Participant(name: trimmed))
        memberName = ""
    }

    private func save() {
        let trimmedName = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        onSave(trimmedName, members)
        dismiss()
    }
}
