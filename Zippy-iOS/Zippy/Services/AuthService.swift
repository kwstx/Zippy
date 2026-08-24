// MARK: - AuthService.swift

import Foundation
import SwiftUI
import Combine

/// Observable service managing optional lightweight organizer accounts,
/// Sign in with Apple, magic-link emails, and group associations.
@MainActor
final class AuthService: ObservableObject {
    static let shared = AuthService()

    static let baseURL = "http://localhost:8080/api/auth"

    @Published var currentUser: UserAccount? = nil
    @Published var isAuthenticated: Bool = false
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    private let userDefaultsKey = "zippy_organizer_account"
    private let tokenDefaultsKey = "zippy_organizer_token"

    private static var jsonDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static var jsonEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    init() {
        loadStoredSession()
    }

    // MARK: - Auth Headers

    /// HTTP headers injecting active session credentials.
    var authHeaders: [String: String] {
        var headers: [String: String] = [:]
        if let token = currentUser?.sessionToken, !token.isEmpty {
            headers["Authorization"] = "Bearer \(token)"
            headers["X-Session-Token"] = token
        }
        if let userId = currentUser?.id {
            headers["X-User-Id"] = userId.uuidString
        }
        return headers
    }

    // MARK: - Sign in with Apple

    /// Authenticates with backend using Apple ID credentials and associates local groups.
    func signInWithApple(
        appleUserId: String,
        identityToken: String? = nil,
        authorizationCode: String? = nil,
        email: String? = nil,
        fullName: String? = nil,
        claimGroupIds: [UUID]? = nil
    ) async throws -> UserAccount {
        guard let url = URL(string: "\(Self.baseURL)/apple") else {
            throw URLError(.badURL)
        }

        isLoading = true
        errorMessage = nil

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = AppleSignInPayload(
            appleUserId: appleUserId,
            identityToken: identityToken,
            authorizationCode: authorizationCode,
            email: email,
            fullName: fullName,
            claimGroupIds: claimGroupIds
        )
        request.httpBody = try Self.jsonEncoder.encode(payload)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                let errorText = String(data: data, encoding: .utf8) ?? "Apple Sign In failed"
                throw NSError(domain: "AuthService", code: (response as? HTTPURLResponse)?.statusCode ?? 0, userInfo: [NSLocalizedDescriptionKey: errorText])
            }

            let account = try Self.jsonDecoder.decode(UserAccount.self, from: data)
            saveSession(account)
            self.isLoading = false
            return account
        } catch {
            self.isLoading = false
            self.errorMessage = error.localizedDescription
            throw error
        }
    }

    // MARK: - Magic Link Email

    /// Requests a magic link sign-in email.
    func requestMagicLink(email: String) async throws -> AuthMessageResponse {
        guard let url = URL(string: "\(Self.baseURL)/magic-link/request") else {
            throw URLError(.badURL)
        }

        isLoading = true
        errorMessage = nil

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = MagicLinkRequestPayload(email: email, redirectURI: nil)
        request.httpBody = try Self.jsonEncoder.encode(payload)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                let errorText = String(data: data, encoding: .utf8) ?? "Failed to send magic link"
                throw NSError(domain: "AuthService", code: (response as? HTTPURLResponse)?.statusCode ?? 0, userInfo: [NSLocalizedDescriptionKey: errorText])
            }

            let message = try Self.jsonDecoder.decode(AuthMessageResponse.self, from: data)
            self.isLoading = false
            return message
        } catch {
            self.isLoading = false
            self.errorMessage = error.localizedDescription
            throw error
        }
    }

    /// Verifies magic-link token and signs in organizer.
    func verifyMagicLink(token: String, email: String? = nil, claimGroupIds: [UUID]? = nil) async throws -> UserAccount {
        guard let url = URL(string: "\(Self.baseURL)/magic-link/verify") else {
            throw URLError(.badURL)
        }

        isLoading = true
        errorMessage = nil

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = MagicLinkVerifyPayload(token: token, email: email, claimGroupIds: claimGroupIds)
        request.httpBody = try Self.jsonEncoder.encode(payload)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                let errorText = String(data: data, encoding: .utf8) ?? "Invalid magic link"
                throw NSError(domain: "AuthService", code: (response as? HTTPURLResponse)?.statusCode ?? 0, userInfo: [NSLocalizedDescriptionKey: errorText])
            }

            let account = try Self.jsonDecoder.decode(UserAccount.self, from: data)
            saveSession(account)
            self.isLoading = false
            return account
        } catch {
            self.isLoading = false
            self.errorMessage = error.localizedDescription
            throw error
        }
    }

    // MARK: - Group Association

    /// Associates a list of group IDs with the signed in organizer account.
    func claimGroups(groupIds: [UUID]) async throws {
        guard let url = URL(string: "\(Self.baseURL)/claim-groups"), isAuthenticated else {
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in authHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let payload = ClaimGroupsPayload(groupIds: groupIds)
        request.httpBody = try Self.jsonEncoder.encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
            if let updatedAccount = try? Self.jsonDecoder.decode(UserAccount.self, from: data) {
                saveSession(updatedAccount)
            }
        }
    }

    // MARK: - Profile & Session

    /// Refreshes current organizer profile from server.
    func refreshProfile() async {
        guard let url = URL(string: "\(Self.baseURL)/me"), isAuthenticated else {
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (key, value) in authHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        if let (data, response) = try? await URLSession.shared.data(for: request),
           let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode),
           let account = try? Self.jsonDecoder.decode(UserAccount.self, from: data) {
            saveSession(account)
        }
    }

    /// Signs out organizer, clears stored session, and updates state.
    func signOut() {
        if let url = URL(string: "\(Self.baseURL)/signout") {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            for (key, value) in authHeaders {
                request.setValue(value, forHTTPHeaderField: key)
            }
            Task {
                _ = try? await URLSession.shared.data(for: request)
            }
        }

        currentUser = nil
        isAuthenticated = false
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        UserDefaults.standard.removeObject(forKey: tokenDefaultsKey)
    }

    // MARK: - Persistence

    private func saveSession(_ account: UserAccount) {
        self.currentUser = account
        self.isAuthenticated = true
        if let encoded = try? Self.jsonEncoder.encode(account) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        }
        UserDefaults.standard.set(account.sessionToken, forKey: tokenDefaultsKey)
    }

    private func loadStoredSession() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let account = try? Self.jsonDecoder.decode(UserAccount.self, from: data) else {
            self.currentUser = nil
            self.isAuthenticated = false
            return
        }

        self.currentUser = account
        self.isAuthenticated = true

        Task {
            await refreshProfile()
        }
    }
}
