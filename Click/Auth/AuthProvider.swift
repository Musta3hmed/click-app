//
//  AuthProvider.swift
//  Click
//
//  Provider-agnostic auth surface. Real Apple/Google conformances and the
//  mock providers all return the same AuthResult, so the rest of the app
//  never knows which one ran.
//

import Foundation

enum AuthProviderKind: String, Codable, CaseIterable {
    case apple
    case google
    case mock
}

/// What a completed sign-in hands back to `AuthSession`.
///
/// `name` and `email` are only guaranteed on the FIRST authorization —
/// Apple never re-sends them — so whatever arrives here must be persisted
/// immediately.
struct AuthResult {
    /// Stable per-provider user identifier.
    let providerUserID: String
    let provider: AuthProviderKind
    /// Opaque session token (identity token, access token, or mock UUID).
    let token: String
    let name: String?
    let email: String?
}

enum AuthError: LocalizedError {
    /// The user dismissed the sheet — not an error to show UI for.
    case cancelled
    case network
    case invalidResponse(String)
    case revoked

    var errorDescription: String? {
        switch self {
        case .cancelled: nil
        case .network: "No connection. Check your internet and try again."
        case .invalidResponse(let detail): "Sign-in failed: \(detail)"
        case .revoked: "Your sign-in expired. Please sign in again."
        }
    }
}

protocol AuthProvider {
    var kind: AuthProviderKind { get }
    func signIn() async throws -> AuthResult
}

/// Build-time switches. Both real providers are fully implemented but
/// gated off until the accounts that power them exist.
enum AuthConfig {
    /// Requires a paid Apple Developer Program membership to enable the
    /// Sign in with Apple capability. Flip to true once that exists.
    static let useRealApple = false

    /// Google Cloud OAuth iOS client ID. nil = Google button uses the mock.
    /// When set, also register the reversed client ID as a URL scheme —
    /// the redirect URI below is derived from this value.
    static let googleClientID: String? = nil

    static var isFullyMocked: Bool {
        !useRealApple && googleClientID == nil
    }
}
