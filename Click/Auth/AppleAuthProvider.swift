//
//  AppleAuthProvider.swift
//  Click
//
//  Real Sign in with Apple. Fully implemented but OFF by default
//  (AuthConfig.useRealApple) because the capability needs a paid Apple
//  Developer Program membership. Without the entitlement this flow fails
//  at runtime with error 1000 — the code itself compiles and works the
//  moment the capability is enabled in Signing & Capabilities.
//

import Foundation
import UIKit
import AuthenticationServices

final class AppleAuthProvider: NSObject, AuthProvider {
    let kind: AuthProviderKind = .apple

    private var continuation: CheckedContinuation<AuthResult, Error>?

    func signIn() async throws -> AuthResult {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }
}

extension AppleAuthProvider: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        defer { continuation = nil }

        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            continuation?.resume(throwing: AuthError.invalidResponse("Unexpected credential type"))
            return
        }

        let token = credential.identityToken.flatMap { String(data: $0, encoding: .utf8) } ?? ""

        // fullName/email arrive ONLY on the first authorization for this
        // Apple ID. AuthSession persists them to the Keychain immediately;
        // onboarding copies them into SwiftData.
        let name = credential.fullName.flatMap { components in
            let formatted = PersonNameComponentsFormatter.localizedString(
                from: components, style: .default
            )
            return formatted.isEmpty ? nil : formatted
        }

        continuation?.resume(returning: AuthResult(
            providerUserID: credential.user,
            provider: .apple,
            token: token,
            name: name,
            email: credential.email
        ))
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        defer { continuation = nil }

        if let authError = error as? ASAuthorizationError, authError.code == .canceled {
            continuation?.resume(throwing: AuthError.cancelled)
        } else {
            continuation?.resume(throwing: AuthError.invalidResponse(error.localizedDescription))
        }
    }
}

extension AppleAuthProvider: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // First foreground-active window scene's key window.
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        return scene?.keyWindow ?? ASPresentationAnchor()
    }
}
