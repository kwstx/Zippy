// MARK: - UserAccount.swift

import Vapor
import Fluent
import Foundation

/// Represents an optional lightweight organizer account.
final class UserAccount: Model, Content, @unchecked Sendable {
    static let schema = "user_accounts"

    @ID(key: .id)
    var id: UUID?

    /// User's email address if registered via Magic Link or shared during Apple Sign In.
    @OptionalField(key: "email")
    var email: String?

    /// Apple unique user identifier (sub) from Apple ID credential.
    @OptionalField(key: "apple_user_id")
    var appleUserId: String?

    /// Optional display name (e.g. given name / nickname).
    @OptionalField(key: "display_name")
    var displayName: String?

    /// Authentication provider: "apple", "magic_link", or "anonymous".
    @Field(key: "auth_provider")
    var authProvider: String

    /// One-time secure token for magic-link email authentication.
    @OptionalField(key: "magic_link_token")
    var magicLinkToken: String?

    /// Expiration date for the current magic link token.
    @OptionalField(key: "magic_link_expires_at")
    var magicLinkExpiresAt: Date?

    /// Active session bearer token for authenticated requests.
    @OptionalField(key: "session_token")
    var sessionToken: String?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        email: String? = nil,
        appleUserId: String? = nil,
        displayName: String? = nil,
        authProvider: String,
        magicLinkToken: String? = nil,
        magicLinkExpiresAt: Date? = nil,
        sessionToken: String? = nil
    ) {
        self.id = id
        self.email = email?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        self.appleUserId = appleUserId
        self.displayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.authProvider = authProvider
        self.magicLinkToken = magicLinkToken
        self.magicLinkExpiresAt = magicLinkExpiresAt
        self.sessionToken = sessionToken
    }
}

// MARK: - Auth DTOs

/// Payload received from frontend for Sign in with Apple.
struct AppleSignInRequestDTO: Content {
    let appleUserId: String
    let identityToken: String?
    let authorizationCode: String?
    let email: String?
    let fullName: String?
    let claimGroupIds: [UUID]?
}

/// Payload to request a magic link email.
struct MagicLinkRequestDTO: Content {
    let email: String
    let redirectURI: String?
}

/// Payload to verify a magic link token.
struct MagicLinkVerifyDTO: Content {
    let token: String
    let email: String?
    let claimGroupIds: [UUID]?
}

/// Payload to claim/associate group IDs with an organizer account.
struct ClaimGroupsRequestDTO: Content {
    let groupIds: [UUID]
}

/// Standard response returning user account details and session token.
struct UserAccountResponseDTO: Content {
    let id: UUID
    let email: String?
    let appleUserId: String?
    let displayName: String?
    let authProvider: String
    let sessionToken: String
    let ownedGroupCount: Int
    let createdAt: Date?
}

/// Generic message response for auth operations.
struct AuthMessageResponseDTO: Content {
    let success: Bool
    let message: String
    let magicLinkURL: String?
    let devToken: String?
}
