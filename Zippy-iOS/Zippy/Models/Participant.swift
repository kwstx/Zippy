// MARK: - Participant.swift

import Foundation

/// A person participating in splitting a receipt.
struct Participant: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String

    /// First character of the name, uppercased, for avatar display.
    var initial: String {
        String(name.prefix(1)).uppercased()
    }

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}
