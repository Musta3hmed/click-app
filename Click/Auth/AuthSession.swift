//
//  AuthSession.swift
//  Click
//
//  Owns the signed-in state for the whole app. Injected once from ClickApp
//  via .environment; everything else reads it.
//

import Foundation
import AuthenticationServices
import Observation

/// The durable record of who is signed in. Serialized into the Keychain.
struct StoredSession: Codable, Equatable {
    let providerUserID: String
    let provider: AuthProviderKind
    let token: String
    /// Captured at first authorization — Apple never re-sends these.
    var name: String?
    var email: String?
    let createdAt: Date
}

@MainActor
@Observable
final class AuthSession {
    enum State: Equatable {
        /// Restoring from Keychain at launch.
        case restoring
        case signedOut
        case signedIn(StoredSession)
    }

    private(set) var state: State = .restoring
    private(set) var isSigningIn = false
    /// A user-visible failure from the last attempt. Cancellation never lands here.
    var lastErrorMessage: String?

    private static let keychainAccount = "session"

    var current: StoredSession? {
        if case .signedIn(let session) = state { return session }
        return nil
    }

    // MARK: - Launch restore

    /// Load the stored session and, for a real Apple credential, verify it
    /// has not been revoked since last launch.
    func restore() async {
        guard let data = KeychainStore.load(account: Self.keychainAccount),
              let stored = try? JSONDecoder().decode(StoredSession.self, from: data) else {
            state = .signedOut
            return
        }

        if stored.provider == .apple && AuthConfig.useRealApple {
            let credentialState = try? await ASAuthorizationAppleIDProvider()
                .credentialState(forUserID: stored.providerUserID)
            if credentialState == .revoked {
                signOut()
                lastErrorMessage = AuthError.revoked.errorDescription
                return
            }
        }

        state = .signedIn(stored)
    }

    // MARK: - Sign in / out

    func signIn(with kind: AuthProviderKind) async {
        guard !isSigningIn else { return }
        isSigningIn = true
        lastErrorMessage = nil
        defer { isSigningIn = false }

        do {
            let result = try await provider(for: kind).signIn()
            let session = StoredSession(
                providerUserID: result.providerUserID,
                provider: result.provider,
                token: result.token,
                name: result.name,
                email: result.email,
                createdAt: .now
            )
            try persist(session)
            state = .signedIn(session)
            Haptics.notify(.success)
        } catch AuthError.cancelled {
            // The user changed their mind; stay quiet.
        } catch is CancellationError {
            // Task cancelled; equally quiet.
        } catch let error as AuthError {
            lastErrorMessage = error.errorDescription
            Haptics.notify(.error)
        } catch {
            lastErrorMessage = urlErrorIsOffline(error)
                ? AuthError.network.errorDescription
                : "Something went wrong signing in. Try again."
            Haptics.notify(.error)
        }
    }

    func signOut() {
        KeychainStore.delete(account: Self.keychainAccount)
        state = .signedOut
    }

    // MARK: - Plumbing

    private func provider(for kind: AuthProviderKind) -> AuthProvider {
        switch kind {
        case .apple:
            AuthConfig.useRealApple ? AppleAuthProvider() : MockAuthProvider(kind: .apple)
        case .google:
            if let clientID = AuthConfig.googleClientID {
                GoogleAuthProvider(clientID: clientID)
            } else {
                MockAuthProvider(kind: .google)
            }
        case .mock:
            MockAuthProvider(kind: .mock)
        }
    }

    private func persist(_ session: StoredSession) throws {
        let data = try JSONEncoder().encode(session)
        try KeychainStore.save(data, account: Self.keychainAccount)
    }

    private func urlErrorIsOffline(_ error: Error) -> Bool {
        let code = (error as? URLError)?.code
        return code == .notConnectedToInternet || code == .networkConnectionLost
            || code == .timedOut || code == .cannotFindHost
    }
}
