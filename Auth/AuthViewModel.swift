//
//  AuthViewModel.swift
//  HealthBar
//
//  Created by Vishnu Nathan on 1/19/26.
//
//  Shared ViewModel driving both LoginView and SignUpView.
//  All auth logic lives here — Views are purely reactive.
//

import Foundation
import Observation

// MARK: - AuthViewModel

/// Drives the entire authentication flow — login, sign-up, and logout.
///
/// Injected with an `AuthService` at initialization, never referencing
/// `LocalAuthService` directly. This allows seamless backend swapping
/// (e.g., dropping in `FirebaseAuthService`) without touching this file.
///
/// **Error type separation:**
/// - `emailError`, `passwordError`, `confirmPasswordError` → field-level input
///   problems (wrong format, too short, mismatch). Shown inline beneath each field.
/// - `authError` → backend-level failures (wrong password, account not found,
///   duplicate email). Shown in the auth error banner above the submit button.
@Observable
@MainActor
final class AuthViewModel {

    // MARK: - Input Fields

    var displayName: String = ""
    var email: String = ""
    var password: String = ""
    var confirmPassword: String = ""

    // MARK: - UI State

    /// True while an async auth operation is in progress.
    var isLoading: Bool = false

    // MARK: - Per-Field Validation Errors

    /// Set when the display name field fails validation on sign-up submission.
    var displayNameError: String? = nil

    /// Set when the email field fails format validation on submission.
    var emailError: String? = nil

    /// Set when the password field fails length or numeric validation on submission.
    var passwordError: String? = nil

    /// Set when confirm password doesn't match password (sign-up only).
    var confirmPasswordError: String? = nil

    // MARK: - Auth-Level Error

    /// Set when the backend rejects the credentials (wrong password, no account, etc.).
    /// Displayed in the error banner separate from field errors.
    var authError: String? = nil

    // MARK: - Injected Service

    // The protocol type (not the concrete LocalAuthService) — this is the
    // boundary that makes backend swapping possible without touching Views.
    private let authService: any AuthService

    /// Resolves usernames to login emails pre-auth via the public
    /// loginHandles mapping. Defaulted so existing call sites compile unchanged.
    private let firestoreService: FirestoreService

    // MARK: - Initialization

    /// - Parameter authService: The auth backend to use.
    ///   Pass `LocalAuthService.shared` during development.
    ///   Replace with `FirebaseAuthService.shared` when ready.
    init(
        authService: any AuthService,
        firestoreService: FirestoreService = FirestoreServiceImpl.shared
    ) {
        self.authService = authService
        self.firestoreService = firestoreService
    }

    // MARK: - Submit Guards

    /// Disable the login button when fields are empty or a request is in-flight.
    var isLoginSubmittable: Bool {
        !isLoading
            && !email.trimmingCharacters(in: .whitespaces).isEmpty
            && !password.isEmpty
    }

    /// Disable the sign-up button when any field is empty or a request is in-flight.
    var isSignUpSubmittable: Bool {
        !isLoading
            && !displayName.trimmingCharacters(in: .whitespaces).isEmpty
            && !email.trimmingCharacters(in: .whitespaces).isEmpty
            && !password.isEmpty
            && !confirmPassword.isEmpty
    }

    // MARK: - Actions

    /// Validates login fields and, if valid, authenticates via the service.
    ///
    /// On success: `authService.isLoggedIn` flips to `true`, triggering
    /// ContentView to switch from the auth flow to the main TabView.
    ///
    /// **userId propagation:** Once `authService.login` succeeds,
    /// `authService.currentUserEmail` is immediately set to the authenticated
    /// user's email. DataManager reads this value **live** via its `currentUserId`
    /// computed property — no explicit "pass userId" call is needed here.
    /// All subsequent DataManager queries are automatically scoped to this user.
    ///
    /// TODO: When Firebase is integrated in Phase 3, `currentUserEmail` will be
    /// replaced by a stable Firebase UID (`currentUserUID`). No changes to this
    /// method will be required — only AuthService and DataManager need updating.
    func login() async {
        clearErrors()
        guard validateLoginFields() else { return }

        isLoading = true
        defer { isLoading = false }

        // The login field accepts an email OR a username. Usernames can never
        // contain "@" except as an optional leading prefix, so any input that
        // is not email-shaped is resolved through the public loginHandles
        // mapping before the normal email sign-in.
        let input = email.trimmingCharacters(in: .whitespaces)
        let loginEmail: String

        if isEmailInput(input) {
            loginEmail = input
        } else {
            let handle = input.hasPrefix("@") ? String(input.dropFirst()) : input
            guard let handleKey = try? DataManager.normalizeAndValidateUsername(handle) else {
                emailError = "Please enter a valid email or username."
                return
            }

            let resolved: String?
            do {
                resolved = try await firestoreService.lookupLoginEmail(forHandleKey: handleKey)
            } catch {
                authError = "Network error. Please check your connection."
                return
            }
            guard let resolved, !resolved.isEmpty else {
                authError = "No account found with that username. Try signing in with your email."
                return
            }
            loginEmail = resolved
        }

        do {
            try await authService.login(email: loginEmail, password: password)
            // userId is now live in authService.currentUserEmail.
            // DataManager picks it up automatically on the next data access.
        } catch let error as AuthError {
            authError = error.errorDescription
        } catch {
            authError = AuthError.unknown(error.localizedDescription).errorDescription
        }
    }

    /// Validates all sign-up fields and, if valid, creates a new account.
    ///
    /// On success: the service starts a session, `isLoggedIn` flips to `true`,
    /// and ContentView transitions to the main TabView automatically.
    ///
    /// **userId propagation:** Identical to `login()` — once `authService.signUp`
    /// succeeds, `authService.currentUserEmail` is set and DataManager immediately
    /// scopes all subsequent queries to the newly created user.
    func signUp() async {
        clearErrors()
        guard validateSignUpFields() else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            try await authService.signUp(
                email: email.trimmingCharacters(in: .whitespaces),
                password: password,
                displayName: displayName.trimmingCharacters(in: .whitespaces)
            )
            // userId is now live in authService.currentUserEmail.
            // DataManager picks it up automatically on the next data access.
        } catch let error as AuthError {
            authError = error.errorDescription
        } catch {
            authError = AuthError.unknown(error.localizedDescription).errorDescription
        }
    }

    /// Starts an anonymous guest session. The auth service sets isGuest=true and
    /// isLoggedIn=true, causing ContentView to transition to the main TabView.
    func continueAsGuest() async {
        isLoading = true
        defer { isLoading = false }
        authService.continueAsGuest()
    }

    /// Ends the current session and clears all form state.
    ///
    /// Called from ProfileView via an injected `onLogout` closure.
    /// The auth service flips `isLoggedIn` to false, and ContentView
    /// automatically returns to the LoginView.
    ///
    /// **userId propagation:** `authService.logout()` clears `currentUserEmail`
    /// to nil. DataManager's `currentUserId` computed property reads this live,
    /// so all subsequent queries immediately return empty — no stale user data
    /// is accessible after logout. SwiftData records are NOT deleted; they simply
    /// become inaccessible until that user authenticates again.
    func logout() {
        authService.logout()
        // userId is now nil in authService.currentUserEmail.
        // DataManager will return empty results for all subsequent queries.
        clearFields()
    }

    // MARK: - Private: Field Reset

    /// Resets all input fields (called after logout so the form starts clean).
    private func clearFields() {
        displayName = ""
        email = ""
        password = ""
        confirmPassword = ""
        clearErrors()
    }

    /// Clears all error messages. Called at the start of every submission attempt
    /// so stale errors don't persist alongside new ones.
    private func clearErrors() {
        displayNameError = nil
        emailError = nil
        passwordError = nil
        confirmPasswordError = nil
        authError = nil
    }

    // MARK: - Private: Validation

    /// Validates the email-or-username field and password for login.
    /// Returns `true` if all fields pass.
    @discardableResult
    private func validateLoginFields() -> Bool {
        var isValid = true

        let input = email.trimmingCharacters(in: .whitespaces)
        if isEmailInput(input) {
            if !isValidEmail(input) {
                emailError = "Please enter a valid email address."
                isValid = false
            }
        } else {
            let handle = input.hasPrefix("@") ? String(input.dropFirst()) : input
            if (try? DataManager.normalizeAndValidateUsername(handle)) == nil {
                emailError = "Please enter a valid email or username."
                isValid = false
            }
        }

        if password.count < 8 {
            passwordError = "Password must be at least 8 characters."
            isValid = false
        } else if !containsNumber(password) {
            passwordError = "Password must contain at least one number."
            isValid = false
        }

        return isValid
    }

    /// True when the login input should be treated as an email address.
    /// A leading "@" marks a username (e.g. "@vishnu"); any other "@" means email.
    private func isEmailInput(_ input: String) -> Bool {
        input.contains("@") && !input.hasPrefix("@")
    }

    /// Validates display name, email, password, and confirm password for sign-up.
    /// Returns `true` if all fields pass. Sets per-field errors for each failure.
    @discardableResult
    private func validateSignUpFields() -> Bool {
        var isValid = true

        let trimmedName = displayName.trimmingCharacters(in: .whitespaces)
        if trimmedName.count < 2 || trimmedName.count > 30 {
            displayNameError = "Display name must be 2–30 characters."
            isValid = false
        } else if ProfanityFilter.containsBlockedTerm(trimmedName) {
            // UGC-1b (D9a): reject a disallowed display name on content, after the length gate.
            displayNameError = "That name isn't allowed."
            isValid = false
        }

        if !isValidEmail(email) {
            emailError = "Please enter a valid email address."
            isValid = false
        }

        if password.count < 8 {
            passwordError = "Password must be at least 8 characters."
            isValid = false
        } else if !containsNumber(password) {
            passwordError = "Password must contain at least one number."
            isValid = false
        }

        if confirmPassword != password {
            confirmPasswordError = "Passwords do not match."
            isValid = false
        }

        return isValid
    }

    /// Returns `true` if the trimmed email matches a standard RFC-compliant format.
    private func isValidEmail(_ email: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        let pattern = #"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"#
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }

    /// Returns `true` if the string contains at least one digit character.
    private func containsNumber(_ string: String) -> Bool {
        string.contains(where: \.isNumber)
    }
}
