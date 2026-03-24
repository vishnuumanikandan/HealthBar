//
//  FirebaseAuthService.swift
//  HealthBar
//
//  Created by Claude on 3/23/26.
//
//  Firebase Authentication implementation of AuthService.
//
//  Swap in place of LocalAuthService at the injection site in ContentView.
//  All Views and ViewModels depend only on the AuthService protocol — no
//  code changes are needed outside of ContentView and this file.
//
//  Key behaviours:
//  - isLoggedIn / currentUserEmail are stored vars (not computed), which is
//    required for @Observable reactivity to work correctly with SwiftUI.
//  - Auth state is driven by Firebase's addStateDidChangeListener, so the UI
//    updates automatically on login, logout, and cold-launch token restoration.
//  - currentUserEmail returns Auth.auth().currentUser?.uid (the Firebase UID),
//    NOT the user's email address. This UID flows into DataManager as userId.
//  - All Firebase callbacks are dispatched to the MainActor before touching
//    observable state (Firebase callbacks are not guaranteed to be on main thread).
//

import Foundation
import Observation
import FirebaseAuth

// MARK: - FirebaseAuthService

/// Firebase-backed implementation of `AuthService`.
///
/// Session persistence is handled automatically by the Firebase SDK —
/// tokens are stored in the Keychain and restored on each app launch.
/// No manual persistence code is needed.
@Observable
final class FirebaseAuthService: AuthService {

    // MARK: - Singleton

    static let shared = FirebaseAuthService()

    // MARK: - Observable State

    /// Whether a Firebase session is currently active.
    ///
    /// Stored var (not computed) so @Observable can track changes and
    /// trigger SwiftUI re-renders when auth state flips.
    var isLoggedIn: Bool = false

    /// Firebase UID used as userId — replaces email-based identifier from LocalAuthService.
    ///
    /// Returns `Auth.auth().currentUser?.uid`, NOT the user's email address.
    /// DataManager reads this live on every query via `authService.currentUserEmail`.
    var currentUserEmail: String? = nil

    // MARK: - Private

    /// Handle for the Firebase auth state listener. Stored so it can be
    /// removed in `deinit` to prevent a retain cycle.
    private var listenerHandle: AuthStateDidChangeListenerHandle?

    // MARK: - Initialization

    private init() {
        // Seed initial state from any persisted Firebase session so the UI
        // starts in the correct state before the listener fires.
        let current = Auth.auth().currentUser
        isLoggedIn = current != nil
        currentUserEmail = current?.uid

        // Register the auth state listener. Firebase calls this once immediately
        // on registration (confirming the current state), then again on any
        // subsequent login, logout, or token refresh.
        listenerHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            // Firebase callbacks may arrive on a background thread.
            // All @Observable mutations must happen on the MainActor.
            Task { @MainActor [weak self] in
                self?.isLoggedIn = user != nil
                self?.currentUserEmail = user?.uid
            }
        }
    }

    deinit {
        if let handle = listenerHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    // MARK: - AuthService

    func login(email: String, password: String) async throws {
        do {
            try await Auth.auth().signIn(withEmail: email, password: password)
            // isLoggedIn / currentUserEmail updated by auth state listener
        } catch {
            throw Self.mapError(error)
        }
    }

    func signUp(email: String, password: String) async throws {
        do {
            try await Auth.auth().createUser(withEmail: email, password: password)
            // isLoggedIn / currentUserEmail updated by auth state listener
        } catch {
            throw Self.mapError(error)
        }
    }

    func logout() {
        try? Auth.auth().signOut()
        // isLoggedIn / currentUserEmail updated by auth state listener
    }

    // MARK: - Error Mapping

    /// Maps Firebase `AuthErrorCode` errors to the app's `AuthError` enum.
    ///
    /// `AuthViewModel` catches `AuthError` specifically, so Firebase errors
    /// must be re-thrown as `AuthError` for the correct banner messages to appear.
    private static func mapError(_ error: Error) -> AuthError {
        guard let errorCode = AuthErrorCode(rawValue: (error as NSError).code) else {
            return .unknown("Something went wrong. Please try again.")
        }

        switch errorCode {
        case .wrongPassword, .invalidCredential:
            return .invalidCredentials

        case .userNotFound:
            return .accountNotFound

        case .emailAlreadyInUse:
            return .emailAlreadyRegistered

        case .networkError:
            return .unknown("Network error. Please check your connection.")

        case .tooManyRequests:
            return .unknown("Too many attempts. Please try again later.")

        default:
            return .unknown("Something went wrong. Please try again.")
        }
    }
}
