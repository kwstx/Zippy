// MARK: - OrganizerAccountSheet.swift

import SwiftUI
import AuthenticationServices

/// Sheet presenting optional organizer account creation (Sign in with Apple, Magic Link email)
/// or account details & sign-out when signed in.
struct OrganizerAccountSheet: View {
    @ObservedObject private var authService = AuthService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var emailInput: String = ""
    @State private var magicLinkSent: Bool = false
    @State private var magicLinkTokenInput: String = ""
    @State private var statusMessage: String? = nil
    @State private var errorMessage: String? = nil
    @State private var devToken: String? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top border line
                Rectangle()
                    .fill(Color.black)
                    .frame(height: 1)

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if authService.isAuthenticated, let user = authService.currentUser {
                            signedInContent(user: user)
                        } else {
                            signedOutContent()
                        }
                    }
                    .padding(24)
                }

                // Bottom border line
                Rectangle()
                    .fill(Color.black)
                    .frame(height: 1)
            }
            .background(Color.white.ignoresSafeArea())
            .navigationTitle(authService.isAuthenticated ? "Organizer Account" : "Sign In / Register")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(.black)
                }
            }
        }
    }

    // MARK: - Signed In View

    @ViewBuilder
    private func signedInContent(user: UserAccount) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Status Header
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.black)
                    .frame(width: 8, height: 8)

                Text("ORGANIZER ACCOUNT ACTIVE")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.black)
            }

            VStack(alignment: .leading, spacing: 14) {
                accountInfoRow(label: "PROVIDER", value: user.authProvider.uppercased())

                if let email = user.email, !email.isEmpty {
                    accountInfoRow(label: "EMAIL", value: email)
                }

                if let appleId = user.appleUserId, !appleId.isEmpty {
                    accountInfoRow(label: "APPLE ID", value: String(appleId.prefix(16)) + "...")
                }

                accountInfoRow(label: "OWNED GROUPS", value: "\(user.ownedGroupCount)")

                accountInfoRow(label: "ACCOUNT ID", value: user.id.uuidString)
            }
            .padding(16)
            .background(Color.white)
            .overlay(Rectangle().stroke(Color.black, lineWidth: 1))

            Text("Your owned groups and receipt splits are automatically associated with this organizer identifier.")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(Color(white: 0.4))
                .lineSpacing(3)

            Spacer().frame(height: 10)

            // Sign Out Button
            Button(action: {
                authService.signOut()
                dismiss()
            }) {
                Text("SIGN OUT")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
            }
        }
    }

    @ViewBuilder
    private func accountInfoRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(Color(white: 0.4))

            Text(value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(.black)
        }
    }

    // MARK: - Signed Out / Auth Form

    @ViewBuilder
    private func signedOutContent() -> some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text("OPTIONAL ORGANIZER ACCOUNT")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.black)

                Text("Sign in to link and manage your created groups across devices. Guest participants never need an account and access links seamlessly.")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Color(white: 0.4))
                    .lineSpacing(3)
            }

            // 1. Sign in with Apple Button
            SignInWithAppleButton(
                .signIn,
                onRequest: { request in
                    request.requestedScopes = [.email, .fullName]
                },
                onCompletion: { result in
                    handleAppleAuthResult(result)
                }
            )
            .signInWithAppleButtonStyle(.black)
            .frame(height: 48)

            // Monochrome Divider with OR
            HStack {
                Rectangle().fill(Color.black.opacity(0.2)).frame(height: 1)
                Text("OR MAGIC LINK")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(white: 0.4))
                    .padding(.horizontal, 8)
                Rectangle().fill(Color.black.opacity(0.2)).frame(height: 1)
            }

            // 2. Magic Link Email Request
            VStack(alignment: .leading, spacing: 8) {
                Text("EMAIL ADDRESS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(white: 0.4))

                HStack(spacing: 8) {
                    TextField("organizer@example.com", text: $emailInput)
                        .font(.system(size: 14, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                        .padding(12)
                        .background(Color.white)
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 1))

                    Button(action: requestMagicLink) {
                        if authService.isLoading {
                            ProgressView()
                                .tint(.white)
                                .frame(width: 60, height: 44)
                                .background(Color.black)
                        } else {
                            Text("SEND")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .frame(height: 44)
                                .background(Color.black)
                        }
                    }
                    .disabled(emailInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || authService.isLoading)
                }
            }

            // Magic Link Code / Token Entry (if sent or testing)
            if magicLinkSent {
                VStack(alignment: .leading, spacing: 8) {
                    Text("VERIFICATION TOKEN / CODE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(white: 0.4))

                    HStack(spacing: 8) {
                        TextField("Paste token from email", text: $magicLinkTokenInput)
                            .font(.system(size: 13, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(12)
                            .background(Color.white)
                            .overlay(Rectangle().stroke(Color.black, lineWidth: 1))

                        Button(action: verifyMagicLink) {
                            Text("VERIFY")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .frame(height: 44)
                                .background(Color.black)
                        }
                        .disabled(magicLinkTokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || authService.isLoading)
                    }

                    if let devToken = devToken {
                        Text("Dev token: \(devToken)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Color(white: 0.5))
                    }
                }
                .padding(.top, 4)
            }

            // Status / Error feedback
            if let status = statusMessage {
                Text(status)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.black)
                    .padding(8)
                    .background(Color(white: 0.95))
            }

            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.black)
                    .padding(8)
                    .border(Color.black, width: 1)
            }
        }
    }

    // MARK: - Actions

    private func handleAppleAuthResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
                let userIdentifier = appleIDCredential.user
                let identityTokenStr = appleIDCredential.identityToken.flatMap { String(data: $0, encoding: .utf8) }
                let authCodeStr = appleIDCredential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
                let email = appleIDCredential.email
                let fullName = [appleIDCredential.fullName?.givenName, appleIDCredential.fullName?.familyName]
                    .compactMap { $0 }
                    .joined(separator: " ")

                Task {
                    do {
                        _ = try await authService.signInWithApple(
                            appleUserId: userIdentifier,
                            identityToken: identityTokenStr,
                            authorizationCode: authCodeStr,
                            email: email,
                            fullName: fullName.isEmpty ? nil : fullName
                        )
                        dismiss()
                    } catch {
                        errorMessage = "Apple Sign In failed: \(error.localizedDescription)"
                    }
                }
            }
        case .failure(let error):
            errorMessage = "Apple Sign In cancelled or failed: \(error.localizedDescription)"
        }
    }

    private func requestMagicLink() {
        let email = emailInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty else { return }

        errorMessage = nil
        statusMessage = nil

        Task {
            do {
                let res = try await authService.requestMagicLink(email: email)
                magicLinkSent = true
                statusMessage = res.message
                if let token = res.devToken {
                    self.devToken = token
                    self.magicLinkTokenInput = token
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func verifyMagicLink() {
        let token = magicLinkTokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = emailInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }

        errorMessage = nil

        Task {
            do {
                _ = try await authService.verifyMagicLink(token: token, email: email.isEmpty ? nil : email)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
