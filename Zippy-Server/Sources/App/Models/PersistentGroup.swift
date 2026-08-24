import Vapor
import Fluent
import Foundation

/// Persisted group model with a roster of members.
final class PersistentGroup: Model, Content, @unchecked Sendable {
    static let schema = "persistent_groups"

    @ID(key: .id)
    var id: UUID?

    /// Title or name of the group (e.g., "Apartment 4B", "Road Trip", "Friday Dinners").
    @Field(key: "name")
    var name: String

    /// The list of members belonging to this group.
    @Field(key: "members")
    var members: [ParticipantDTO]

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        name: String,
        members: [ParticipantDTO]
    ) {
        self.id = id
        self.name = name
        self.members = members
    }
}
