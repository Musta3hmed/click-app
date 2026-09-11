//
//  MockAuthProviders.swift
//  Click
//
//  Stand-in providers used until the paid Apple Developer account and the
//  Google OAuth client ID exist. Clearly surfaced as demo mode in the UI
//  (see WelcomeView) — do not ship these enabled.
//

import Foundation

struct MockAuthProvider: AuthProvider {
    let kind: AuthProviderKind

    func signIn() async throws -> AuthResult {
        // A short pause so the button's in-progress state is visible and the
        // flow exercises the same async path as the real providers.
        try await Task.sleep(for: .milliseconds(600))

        return AuthResult(
            providerUserID: "mock-\(kind.rawValue)-user",
            provider: kind,
            token: UUID().uuidString,
            name: nil,
            email: nil
        )
    }
}
