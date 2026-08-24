// MARK: - AuthController.swift

import Vapor
import Fluent
import Foundation

/// Controller handling lightweight organizer account authentication (Apple Sign In, Magic Link email)
/// and group ownership association.
struct AuthController {

    /// Handles Sign in with Apple authentication, profile creation, and group claim association.
    @Sendable
    func signInWithApple(req: Request) async throws -> UserAccountResponseDTO {
        let payload = try req.content.decode(AppleSignInRequestDTO.self)
        let appleUserId = payload.appleUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !appleUserId.isEmpty else {
            throw Abort(.badRequest, reason: "Missing Apple user identifier.")
        }

        let email = payload.email?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = payload.fullName?.trimmingCharacters(in: .whitespacesAndNewlines)

        // Find existing user by apple_user_id or email
        var user: UserAccount?
        if let existing = try await UserAccount.query(on: req.db)
            .filter(\.$appleUserId == appleUserId)
            .first() {
            user = existing
        } else if let email = email, !email.isEmpty,
                  let existing = try await UserAccount.query(on: req.db)
            .filter(\.$email == email)
            .first() {
            user = existing
            user?.appleUserId = appleUserId
        }

        let sessionToken = UUID().uuidString.replacingOccurrences(of: "-", with: "") + UUID().uuidString.replacingOccurrences(of: "-", with: "")

        if let existingUser = user {
            if let email = email, !email.isEmpty {
                existingUser.email = email
            }
            if let displayName = displayName, !displayName.isEmpty {
                existingUser.displayName = displayName
            }
            existingUser.sessionToken = sessionToken
            try await existingUser.save(on: req.db)
            user = existingUser
        } else {
            let newUser = UserAccount(
                email: email,
                appleUserId: appleUserId,
                displayName: displayName ?? "Organizer",
                authProvider: "apple",
                sessionToken: sessionToken
            )
            try await newUser.save(on: req.db)
            user = newUser
        }

        guard let account = user, let userId = account.id else {
            throw Abort(.internalServerError, reason: "Failed to persist user account.")
        }

        // Associate any specified initial or local groups
        if let groupIds = payload.claimGroupIds, !groupIds.isEmpty {
            try await claimGroupsInternal(groupIds: groupIds, userId: userId, db: req.db, logger: req.logger)
        }

        let ownedCount = try await PersistentGroup.query(on: req.db)
            .filter(\.$ownerId == userId.uuidString)
            .count()

        req.logger.info("Organizer signed in via Apple: \(userId) (groups owned: \(ownedCount))")

        return UserAccountResponseDTO(
            id: userId,
            email: account.email,
            appleUserId: account.appleUserId,
            displayName: account.displayName,
            authProvider: account.authProvider,
            sessionToken: sessionToken,
            ownedGroupCount: ownedCount,
            createdAt: account.createdAt
        )
    }

    /// Generates and sends a lightweight magic-link email token.
    @Sendable
    func requestMagicLink(req: Request) async throws -> AuthMessageResponseDTO {
        let payload = try req.content.decode(MagicLinkRequestDTO.self)
        let email = payload.email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        guard !email.isEmpty, email.contains("@"), email.contains(".") else {
            throw Abort(.badRequest, reason: "Invalid email address format.")
        }

        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let expiresAt = Date().addingTimeInterval(900) // 15 minutes validity

        // Find or create account
        var account = try await UserAccount.query(on: req.db)
            .filter(\.$email == email)
            .first()

        if let existing = account {
            existing.magicLinkToken = token
            existing.magicLinkExpiresAt = expiresAt
            try await existing.save(on: req.db)
        } else {
            let newAccount = UserAccount(
                email: email,
                displayName: email.components(separatedBy: "@").first?.capitalized ?? "Organizer",
                authProvider: "magic_link",
                magicLinkToken: token,
                magicLinkExpiresAt: expiresAt
            )
            try await newAccount.save(on: req.db)
            account = newAccount
        }

        let baseURL = Environment.get("BASE_URL") ?? "http://localhost:8080"
        let magicLinkURL = "\(baseURL)/api/auth/magic-link/verify?token=\(token)&email=\(email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? email)"

        req.logger.info("Magic link requested for \(email). Token: \(token), URL: \(magicLinkURL)")

        return AuthMessageResponseDTO(
            success: true,
            message: "A sign-in link has been prepared for \(email).",
            magicLinkURL: magicLinkURL,
            devToken: token
        )
    }

    /// Verifies magic-link token and issues authenticated organizer session.
    @Sendable
    func verifyMagicLink(req: Request) async throws -> UserAccountResponseDTO {
        // Can be passed via JSON body or query parameter (e.g. from browser or deep link)
        let token: String
        var email: String?
        var claimGroupIds: [UUID]?

        if let body = try? req.content.decode(MagicLinkVerifyDTO.self) {
            token = body.token.trimmingCharacters(in: .whitespacesAndNewlines)
            email = body.email?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            claimGroupIds = body.claimGroupIds
        } else if let queryToken = try? req.query.get(String.self, at: "token") {
            token = queryToken.trimmingCharacters(in: .whitespacesAndNewlines)
            email = (try? req.query.get(String.self, at: "email"))?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            throw Abort(.badRequest, reason: "Missing magic link verification token.")
        }

        guard !token.isEmpty else {
            throw Abort(.badRequest, reason: "Invalid token.")
        }

        var query = UserAccount.query(on: req.db)
            .filter(\.$magicLinkToken == token)

        if let email = email, !email.isEmpty {
            query = query.filter(\.$email == email)
        }

        guard let user = try await query.first() else {
            throw Abort(.unauthorized, reason: "Invalid or expired magic link token.")
        }

        if let expiresAt = user.magicLinkExpiresAt, expiresAt < Date() {
            throw Abort(.unauthorized, reason: "Magic link token has expired. Please request a new one.")
        }

        let sessionToken = UUID().uuidString.replacingOccurrences(of: "-", with: "") + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        user.sessionToken = sessionToken
        user.magicLinkToken = nil
        user.magicLinkExpiresAt = nil
        try await user.save(on: req.db)

        guard let userId = user.id else {
            throw Abort(.internalServerError, reason: "Failed to persist user session.")
        }

        if let groupIds = claimGroupIds, !groupIds.isEmpty {
            try await claimGroupsInternal(groupIds: groupIds, userId: userId, db: req.db, logger: req.logger)
        }

        let ownedCount = try await PersistentGroup.query(on: req.db)
            .filter(\.$ownerId == userId.uuidString)
            .count()

        req.logger.info("Organizer signed in via Magic Link: \(userId) (email: \(user.email ?? "n/a"))")

        return UserAccountResponseDTO(
            id: userId,
            email: user.email,
            appleUserId: user.appleUserId,
            displayName: user.displayName,
            authProvider: user.authProvider,
            sessionToken: sessionToken,
            ownedGroupCount: ownedCount,
            createdAt: user.createdAt
        )
    }

    /// Retrieves current signed-in organizer profile and owned group summary.
    @Sendable
    func getMe(req: Request) async throws -> UserAccountResponseDTO {
        let user = try await resolveUser(req: req)
        guard let userId = user.id else {
            throw Abort(.internalServerError, reason: "User ID unavailable.")
        }

        let ownedCount = try await PersistentGroup.query(on: req.db)
            .filter(\.$ownerId == userId.uuidString)
            .count()

        return UserAccountResponseDTO(
            id: userId,
            email: user.email,
            appleUserId: user.appleUserId,
            displayName: user.displayName,
            authProvider: user.authProvider,
            sessionToken: user.sessionToken ?? "",
            ownedGroupCount: ownedCount,
            createdAt: user.createdAt
        )
    }

    /// Associates a list of group IDs with the authenticated organizer's account.
    @Sendable
    func claimGroups(req: Request) async throws -> UserAccountResponseDTO {
        let user = try await resolveUser(req: req)
        guard let userId = user.id else {
            throw Abort(.internalServerError, reason: "User ID unavailable.")
        }

        let payload = try req.content.decode(ClaimGroupsRequestDTO.self)
        try await claimGroupsInternal(groupIds: payload.groupIds, userId: userId, db: req.db, logger: req.logger)

        let ownedCount = try await PersistentGroup.query(on: req.db)
            .filter(\.$ownerId == userId.uuidString)
            .count()

        return UserAccountResponseDTO(
            id: userId,
            email: user.email,
            appleUserId: user.appleUserId,
            displayName: user.displayName,
            authProvider: user.authProvider,
            sessionToken: user.sessionToken ?? "",
            ownedGroupCount: ownedCount,
            createdAt: user.createdAt
        )
    }

    /// Signs out the organizer and invalidates the session token.
    @Sendable
    func signOut(req: Request) async throws -> AuthMessageResponseDTO {
        if let user = try? await resolveUser(req: req) {
            user.sessionToken = nil
            try await user.save(on: req.db)
        }

        return AuthMessageResponseDTO(
            success: true,
            message: "Signed out successfully.",
            magicLinkURL: nil,
            devToken: nil
        )
    }

    // MARK: - Helper Methods

    /// Resolves the authenticated user from bearer token or user ID headers.
    func resolveUser(req: Request) async throws -> UserAccount {
        // Check Authorization Bearer header
        if let authHeader = req.headers.bearerAuthorization {
            let token = authHeader.token
            if let user = try await UserAccount.query(on: req.db)
                .filter(\.$sessionToken == token)
                .first() {
                return user
            }
        }

        // Check custom header X-Session-Token
        if let sessionToken = req.headers.first(name: "X-Session-Token"), !sessionToken.isEmpty {
            if let user = try await UserAccount.query(on: req.db)
                .filter(\.$sessionToken == sessionToken)
                .first() {
                return user
            }
        }

        // Check X-User-Id fallback
        if let userIdStr = req.headers.first(name: "X-User-Id"), let userId = UUID(uuidString: userIdStr) {
            if let user = try await UserAccount.find(userId, on: req.db) {
                return user
            }
        }

        throw Abort(.unauthorized, reason: "Authentication required.")
    }

    /// Internal logic to associate groups with a user ID.
    private func claimGroupsInternal(groupIds: [UUID], userId: UUID, db: Database, logger: Logger) async throws {
        for groupId in groupIds {
            if let group = try await PersistentGroup.find(groupId, on: db) {
                // If group is unassigned or re-claimed by organizer
                group.ownerId = userId.uuidString
                try await group.save(on: db)
                logger.info("Associated group \(groupId) with organizer \(userId)")
            }
        }
    }
}
