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

    /// Base currency for group accounting and debt simplification (default: "USD").
    @OptionalField(key: "currency")
    var currency: String?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        name: String,
        members: [ParticipantDTO],
        currency: String? = "USD"
    ) {
        self.id = id
        self.name = name
        self.members = members
        self.currency = currency ?? "USD"
    }
}
