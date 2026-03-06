//
//  LocalAuthService.swift
//  HealthBar
//
//  Created by Vishnu Nathan on 1/19/26.
//
//  UserDefaults-backed AuthService for local development and pre-Firebase use.
//
//  Credentials are stored as a JSON-encoded [email: SHA-256(password)] dictionary.
//  Multiple accounts can coexist; sign-up never overwrites an existing account.
//  Session state is restored on launch, mirroring @AppStorage behavior for
//  service-layer objects (which cannot use the SwiftUI @AppStorage property wrapper).
//
//  ─────────────────────────────────────────────────────────────────────────────
//  FIREBASE MIGRATION POINT
//
//  When adding Firebase Auth, create `FirebaseAuthService: AuthService` that wraps
//  the Firebase SDK calls. In ContentView, replace `LocalAuthService.shared` with
//  `FirebaseAuthService.shared` (or inject via environment).
//
//  All ViewModel and View code remains unchanged — they only see `AuthService`.
//  ─────────────────────────────────────────────────────────────────────────────
//

import Foundation
import CryptoKit
import Observation

// MARK: - LocalAuthService

/// UserDefaults-backed implementation of `AuthService`.
///
/// Uses `UserDefaults.standard` directly — the service-layer equivalent of
/// SwiftUI's `@AppStorage`. Marked `@Observable` so that SwiftUI views that
/// hold a reference can react to `isLoggedIn` and `currentUserEmail` changes.
@Observable
final class LocalAuthService: AuthService {

    // MARK: - Singleton

    /// Shared instance. All injection sites use this — never create new instances.
    static let shared = LocalAuthService()

    // MARK: - Observable State

    /// Whether a session is currently active. Drives auth-gating in ContentView.
    private(set) var isLoggedIn: Bool = false

    /// Email of the currently logged-in user. Nil when no session is active.
    private(set) var currentUserEmail: String? = nil

    // MARK: - UserDefaults Keys

    // Using UserDefaults directly — service-layer equivalent of @AppStorage.
    private let defaults = UserDefaults.standard

    /// Key for the JSON-encoded [email: hashedPassword] credentials dictionary.
    private let usersKey = "hb_auth_users_v1"

    /// Key for the currently active session's email address.
    private let sessionKey = "hb_auth_current_user"

    // MARK: - Initialization

    private init() {
        // Restore session from UserDefaults on launch.
        // This mirrors @AppStorage persistence behavior across app launches.
        let savedEmail = defaults.string(forKey: sessionKey)
        currentUserEmail = savedEmail
        isLoggedIn = savedEmail != nil
    }

    // MARK: - AuthService Conformance

    /// Validates the provided credentials against stored accounts and starts a session.
    ///
    /// Uses `Task.sleep` to simulate async latency, keeping the UX consistent with
    /// future network-backed implementations (Firebase, etc.).
    func login(email: String, password: String) async throws {
        // Simulate async backend latency (remove when replacing with real network call)
        try await Task.sleep(nanoseconds: 600_000_000) // 0.6 s

        let normalizedEmail = email.lowercased().trimmingCharacters(in: .whitespaces)
        let users = loadUsers()

        guard let storedHash = users[normalizedEmail] else {
            throw AuthError.accountNotFound
        }

        guard hash(password) == storedHash else {
            throw AuthError.invalidCredentials
        }

        // Persist session and update observable state
        defaults.set(normalizedEmail, forKey: sessionKey)
        currentUserEmail = normalizedEmail
        isLoggedIn = true
    }

    /// Creates a new account if no account already exists for this email.
    ///
    /// Automatically starts a session on successful sign-up (no separate login needed).
    func signUp(email: String, password: String) async throws {
        // Simulate async backend latency (remove when replacing with real network call)
        try await Task.sleep(nanoseconds: 800_000_000) // 0.8 s

        let normalizedEmail = email.lowercased().trimmingCharacters(in: .whitespaces)
        var users = loadUsers()

        guard users[normalizedEmail] == nil else {
            throw AuthError.emailAlreadyRegistered
        }

        // Store hashed password, then start session immediately
        users[normalizedEmail] = hash(password)
        saveUsers(users)
        defaults.set(normalizedEmail, forKey: sessionKey)
        currentUserEmail = normalizedEmail
        isLoggedIn = true
    }

    /// Clears the active session from UserDefaults and resets observable state.
    func logout() {
        defaults.removeObject(forKey: sessionKey)
        currentUserEmail = nil
        isLoggedIn = false
    }

    // MARK: - Private: Persistence

    /// Loads all stored user credentials from UserDefaults.
    /// Returns an empty dictionary if no accounts have been created yet.
    private func loadUsers() -> [String: String] {
        guard
            let data = defaults.data(forKey: usersKey),
            let users = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return [:]
        }
        return users
    }

    /// Persists the full credentials dictionary to UserDefaults.
    private func saveUsers(_ users: [String: String]) {
        guard let data = try? JSONEncoder().encode(users) else { return }
        defaults.set(data, forKey: usersKey)
    }

    // MARK: - Private: Hashing

    /// Produces a SHA-256 hex digest of the given password string.
    ///
    /// Passwords are never stored in plaintext. When migrating to Firebase,
    /// Firebase Auth handles credential storage — this helper is not needed.
    private func hash(_ password: String) -> String {
        let data = Data(password.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
