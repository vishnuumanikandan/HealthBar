//
//  AuthService.swift
//  HealthBar
//
//  Created by Vishnu Nathan on 1/19/26.
//
//  Protocol definition for the authentication service layer.
//
//  This abstraction ensures that Views and ViewModels never depend on a
//  specific auth backend. To add Firebase, Google Sign-In, or phone number
//  auth, create a new conforming type and swap it at the injection site in
//  ContentView — no ViewModel or View code changes are needed.
//

import Foundation

// MARK: - AuthError

/// Authentication-level errors surfaced from the backend.
///
/// These are distinct from field validation errors (which live in AuthViewModel).
/// Each case maps to a human-readable message shown in the `authError` banner.
///
/// - `invalidCredentials`: Email/password combination is incorrect.
/// - `accountNotFound`: No account exists for this email address.
/// - `emailAlreadyRegistered`: An account already exists with this email.
/// - `unknown`: Catch-all for unexpected or unmapped failures.
enum AuthError: LocalizedError {
    case invalidCredentials
    case accountNotFound
    case emailAlreadyRegistered
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Incorrect email or password. Please try again."
        case .accountNotFound:
            return "No account found with this email. Please sign up first."
        case .emailAlreadyRegistered:
            return "An account with this email already exists. Please log in."
        case .unknown(let message):
            return "Something went wrong: \(message)"
        }
    }
}

// MARK: - AuthService Protocol

/// Single abstraction layer between ViewModels and any authentication backend.
///
/// Conforming types own the full authentication lifecycle — session persistence,
/// credential validation, and sign-out. The protocol surface is intentionally
/// minimal so it stays easy to implement for new backends.
///
/// **Planned future conformances:**
/// - `FirebaseAuthService`  — Firebase email/password + session tokens
/// - `GoogleAuthService`    — Google Sign-In via GoogleSignIn SDK
/// - `PhoneAuthService`     — Phone number + OTP via Firebase
///
/// Views and ViewModels must **never** reference `LocalAuthService` (or any
/// concrete conformance) directly. They work only through this protocol.
protocol AuthService {

    /// Whether a user session is currently active.
    var isLoggedIn: Bool { get }

    /// The email address of the currently authenticated user, or `nil` if no
    /// session is active.
    var currentUserEmail: String? { get }

    /// Authenticates an existing account with the provided credentials.
    ///
    /// - Throws: `AuthError.accountNotFound` if no account exists for `email`.
    ///           `AuthError.invalidCredentials` if the password is incorrect.
    func login(email: String, password: String) async throws

    /// Creates a new account with the provided credentials and starts a session.
    ///
    /// - Throws: `AuthError.emailAlreadyRegistered` if an account already exists.
    func signUp(email: String, password: String) async throws

    /// Ends the current session and clears all local session state.
    func logout()
}
