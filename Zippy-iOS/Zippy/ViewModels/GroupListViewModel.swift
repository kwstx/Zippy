// MARK: - GroupListViewModel.swift

import Foundation
import SwiftUI

@MainActor
final class GroupListViewModel: ObservableObject {
    @Published var groups: [PersistentGroup] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var isCreatingGroup: Bool = false

    func loadGroups() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let fetched = try await GroupService.fetchGroups()
                self.groups = fetched
                self.isLoading = false
            } catch {
                self.errorMessage = "Failed to load groups: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }

    func createGroup(name: String, members: [Participant], currency: String = "USD") async -> Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            self.errorMessage = "Group name is required."
            return false
        }

        isCreatingGroup = true
        errorMessage = nil

        do {
            let newGroup = try await GroupService.createGroup(name: name, members: members, currency: currency)
            self.groups.insert(newGroup, at: 0)
            self.isCreatingGroup = false
            return true
        } catch {
            self.errorMessage = "Failed to create group: \(error.localizedDescription)"
            self.isCreatingGroup = false
            return false
        }
    }

    func deleteGroup(at indexSet: IndexSet) {
        for index in indexSet {
            let group = groups[index]
            Task {
                do {
                    try await GroupService.deleteGroup(groupId: group.id)
                } catch {
                    print("Error deleting group \(group.id): \(error)")
                }
            }
        }
        groups.remove(atOffsets: indexSet)
    }
}
