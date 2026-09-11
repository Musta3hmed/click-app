//
//  GoogleAuthProvider.swift
//  Click
//
//  Google sign-in via ASWebAuthenticationSession + OAuth 2.0 PKCE (S256).
//  Deliberately NOT the GoogleSignIn SDK — keeps the zero-dependency rule.
//  Fully implemented but unused until AuthConfig.googleClientID is set;
//  the reversed client ID must also be registered as a URL scheme
//  (INFOPLIST_KEY_... build setting) at that point.
//

import Foundation
import UIKit
import AuthenticationServices
import CryptoKit

final class GoogleAuthProvider: NSObject, AuthProvider {
    let kind: AuthProviderKind = .google

    private let clientID: String
    /// e.g. clientID "123-abc.apps.googleusercontent.com" →
    /// scheme "com.googleusercontent.apps.123-abc".
    private var redirectScheme: String {
        clientID.split(separator: ".").reversed().joined(separator: ".")
    }
    private var redirectURI: String { "\(redirectScheme):/oauth2redirect" }

    init(clientID: String) {
        self.clientID = clientID
    }

    func signIn() async throws -> AuthResult {
        let verifier = Self.randomURLSafeString(bytes: 32)
        let challenge = Self.s256(verifier)
        let state = Self.randomURLSafeString(bytes: 16)

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: "openid email profile"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state)
        ]

        let callbackURL = try await authenticate(url: components.url!, scheme: redirectScheme)

        let query = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard query.first(where: { $0.name == "state" })?.value == state else {
            throw AuthError.invalidResponse("OAuth state mismatch")
        }
        guard let code = query.first(where: { $0.name == "code" })?.value else {
            throw AuthError.invalidResponse("No authorization code returned")
        }

        return try await exchange(code: code, verifier: verifier)
    }

    // MARK: - Web session

    @MainActor
    private func authenticate(url: URL, scheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else if let error = error as? ASWebAuthenticationSessionError,
                          error.code == .canceledLogin {
                    continuation.resume(throwing: AuthError.cancelled)
                } else {
                    continuation.resume(throwing: AuthError.invalidResponse(
                        error?.localizedDescription ?? "Unknown web auth failure"
                    ))
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }

    // MARK: - Token exchange

    private struct TokenResponse: Decodable {
        let access_token: String
        let id_token: String?
    }

    private struct IDTokenClaims: Decodable {
        let sub: String
        let email: String?
        let name: String?
    }

    private func exchange(code: String, verifier: String) async throws -> AuthResult {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = [
            "client_id=\(clientID)",
            "code=\(code)",
            "code_verifier=\(verifier)",
            "grant_type=authorization_code",
            "redirect_uri=\(redirectURI)"
        ].joined(separator: "&").data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw AuthError.invalidResponse("Token exchange rejected")
        }

        let tokens = try JSONDecoder().decode(TokenResponse.self, from: data)
        guard let idToken = tokens.id_token,
              let claims = Self.decodeJWTClaims(idToken, as: IDTokenClaims.self) else {
            throw AuthError.invalidResponse("Missing or unreadable ID token")
        }

        return AuthResult(
            providerUserID: claims.sub,
            provider: .google,
            token: tokens.access_token,
            name: claims.name,
            email: claims.email
        )
    }

    // MARK: - Crypto helpers

    private static func randomURLSafeString(bytes count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return base64URL(Data(bytes))
    }

    private static func s256(_ verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Decode the payload segment of a JWT without verifying the signature —
    /// acceptable here because the token came straight from Google over TLS.
    private static func decodeJWTClaims<T: Decodable>(_ jwt: String, as type: T.Type) -> T? {
        let segments = jwt.split(separator: ".")
        guard segments.count >= 2 else { return nil }
        var base64 = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

extension GoogleAuthProvider: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        return scene?.keyWindow ?? ASPresentationAnchor()
    }
}
