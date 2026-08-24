// MARK: - AuthModels.swift

import Foundation

/// Represents an optional lightweight organizer account.
struct UserAccount: Identifiable, Codable, Equatable {
    let id: UUID
    var email: String?
    var appleUserId: String?
    var displayName: String?
    var authProvider: String
    var sessionToken: String
    var ownedGroupCount: Int
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, email, appleUserId, displayName, authProvider, sessionToken, ownedGroupCount, createdAt
    }

    var isAppleAuth: Bool {
        authProvider.lowercased() == "apple"
    }

    var isMagicLinkAuth: Bool {
        authProvider.lowercased() == "magic_link"
    }

    /// Short minimal identifier for account badge (e.g. "ORGANIZER", "ME", or email initial).
    var badgeLabel: String {
        if let email = email, !email.isEmpty {
            let prefix = email.components(separatedBy: "@").first ?? email
            return prefix.uppercased()
        }
        if let name = displayName, !name.isEmpty {
            return name.uppercased()
        }
        return "ORGANIZER"
    }
}

/// Payload sent for Apple Sign In.
struct AppleSignInPayload: Encodable {
    let appleUserId: String
    let identityToken: String?
    let authorizationCode: String?
    let email: String?
    let fullName: String?
    let claimGroupIds: [UUID]?
}

/// Payload sent to request a magic link email.
struct MagicLinkRequestPayload: Encodable {
    let email: String
    let redirectURI: String?
}

/// Payload sent to verify a magic link token.
struct MagicLinkVerifyPayload: Encodable {
    let token: String
    let email: String?
    let claimGroupIds: [UUID]?
}

/// Response returned from magic link request.
struct AuthMessageResponse: Codable {
    let success: Bool
    let message: String
    let magicLinkURL: String?
    let devToken: String?
}

/// Payload to claim groups with an account.
struct ClaimGroupsPayload: Encodable {
    let groupIds: [UUID]
}
