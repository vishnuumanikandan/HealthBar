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
import FirebaseFirestore

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
    /// Returns "guest" when in guest mode. DataManager reads this live on every query.
    var currentUserEmail: String? = nil

    /// The display name of the currently authenticated Firebase user.
    var currentUserDisplayName: String? {
        Auth.auth().currentUser?.displayName
    }

    /// The real email address of the current Firebase user (currentUserEmail is the UID).
    var currentUserActualEmail: String? {
        Auth.auth().currentUser?.email
    }

    /// True when the user is running an anonymous guest session.
    /// Persisted across app launches via UserDefaults.
    var isGuest: Bool = false

    /// True immediately after account creation; cleared after first successful data load.
    var isNewUser: Bool = false

    /// Non-nil only during the migration window when a guest user just signed up.
    /// ContentView observes this to trigger SwiftData migration before Firestore sync.
    var pendingMigrationUserId: String? = nil

    // MARK: - Private

    /// Handle for the Firebase auth state listener. Stored so it can be
    /// removed in `deinit` to prevent a retain cycle.
    private var listenerHandle: AuthStateDidChangeListenerHandle?

    /// UserDefaults key for persisting guest mode across app launches.
    private let guestModeKey = "com.healthbar.isGuestMode"

    // MARK: - Initialization

    private init() {
        // Detect fresh install: UserDefaults is cleared on uninstall but the
        // Firebase auth token lives in the Keychain and survives reinstalls.
        // Sign out on first launch so a reinstalled app always shows login.
        let launchedKey = "hb_hasLaunchedBefore"
        if !UserDefaults.standard.bool(forKey: launchedKey) {
            try? Auth.auth().signOut()
            UserDefaults.standard.set(true, forKey: launchedKey)
        }

        // Restore persisted guest mode before seeding any other state.
        let wasGuest = UserDefaults.standard.bool(forKey: guestModeKey)
        if wasGuest {
            isGuest = true
            isLoggedIn = true
            currentUserEmail = "guest"
        } else {
            // Seed initial state from any persisted Firebase session so the UI
            // starts in the correct state before the listener fires.
            let current = Auth.auth().currentUser
            isLoggedIn = current != nil
            currentUserEmail = current?.uid
        }

        // Register the auth state listener. Firebase calls this once immediately
        // on registration (confirming the current state), then again on any
        // subsequent login, logout, or token refresh.
        listenerHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            // Firebase callbacks may arrive on a background thread.
            // All @Observable mutations must happen on the MainActor.
            Task { @MainActor [weak self] in
                guard let self else { return }

                // Guest mode: maintain guest state regardless of Firebase user.
                // Suppress listener if migration is pending (completeMigration will update).
                if self.isGuest {
                    if self.pendingMigrationUserId != nil {
                        // Migration in progress — do not touch state.
                        return
                    }
                    self.isLoggedIn = true
                    self.currentUserEmail = "guest"
                    return
                }

                // Normal Firebase auth flow.
                // M6: a PASSIVE sign-out (token revocation / password change on another device)
                // fires this listener with user == nil but never routes through logout(), so the
                // Firestore sync (listeners + pending-id sets + currentSyncUserId) would keep
                // running on a dead session — on same-account re-login shouldRegisterListener sees
                // stale registrations ("already listening") and the session runs with no
                // cross-device sync until relaunch. Tear it down on a real signed-in → signed-out
                // transition. currentUserEmail still holds the PRIOR uid here (nil on the
                // cold-launch callback; the guest branch above already returned), so this never
                // fires at launch or for guests; logout() nils currentUserEmail before signOut()
                // → no double teardown.
                let previousUid = self.currentUserEmail
                if user == nil, previousUid != nil {
                    FirestoreServiceImpl.shared.stopAllListeners()
                }
                self.isLoggedIn = user != nil
                self.currentUserEmail = user?.uid
            }
        }
    }

    deinit {
        if let handle = listenerHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    // MARK: - AuthService

    func continueAsGuest() {
        // Stop any active Firestore listeners before entering guest mode.
        FirestoreServiceImpl.shared.stopAllListeners()
        isGuest = true
        UserDefaults.standard.set(true, forKey: guestModeKey)
        isLoggedIn = true
        currentUserEmail = "guest"
    }

    func completeMigration(newUserId: String) {
        // Migration succeeded — drop guest mode and adopt the real identity.
        isGuest = false
        isNewUser = false
        pendingMigrationUserId = nil
        UserDefaults.standard.set(false, forKey: guestModeKey)
        isLoggedIn = true
        currentUserEmail = newUserId
    }

    func cancelMigration() {
        // Migration failed. signUp() already created AND signed in the real Firebase account
        // (createUser signs in), so clearing pendingMigrationUserId alone stranded a signed-in
        // orphan account under a guest UI — review finding M7. Restore a fully consistent guest
        // state (the same flags continueAsGuest / the launch guest-restore path use) so a cold
        // launch lands in the same place, THEN sign the orphan account out best-effort (its token
        // must not survive in the keychain as a live session). Guest state is set before signOut()
        // so the auth-state listener's guest branch handles the sign-out callback (no M6 teardown,
        // no flicker). ContentView still surfaces the migration error to the signup sheet.
        isGuest = true
        isLoggedIn = true
        currentUserEmail = "guest"
        UserDefaults.standard.set(true, forKey: guestModeKey)
        pendingMigrationUserId = nil
        try? Auth.auth().signOut()
        // TODO(auth): retry-migration path for a created-but-unmigrated account
    }

    func login(email: String, password: String) async throws {
        let wasGuest = isGuest
        if wasGuest {
            isGuest = false
            UserDefaults.standard.set(false, forKey: guestModeKey)
        }
        do {
            try await Auth.auth().signIn(withEmail: email, password: password)
        } catch {
            if wasGuest {
                isGuest = true
                UserDefaults.standard.set(true, forKey: guestModeKey)
            }
            throw Self.mapError(error)
        }
    }

    /// Creates a new account, sets displayName on Firebase Auth, and writes account/info to Firestore.
    /// If the Firestore write fails, sign-up still succeeds — startFirestoreSync retries on next login.
    /// When called from guest mode, sets pendingMigrationUserId and keeps guest state active
    /// until ContentView completes SwiftData migration and calls completeMigration(newUserId:).
    func signUp(email: String, password: String, displayName: String) async throws {
        let wasGuest = isGuest
        do {
            let authResult = try await Auth.auth().createUser(withEmail: email, password: password)

            // Set displayName on Firebase Auth profile
            let changeRequest = authResult.user.createProfileChangeRequest()
            changeRequest.displayName = displayName.trimmingCharacters(in: .whitespaces)
            try await changeRequest.commitChanges()

            // Mark as new user so the first profile load suppresses false errors.
            isNewUser = true

            if wasGuest {
                // Guest upgrading to an account: signal migration needed.
                // Keep isGuest=true, isLoggedIn=true, currentUserEmail="guest" until migration.
                // The auth state listener is suppressed while pendingMigrationUserId is non-nil.
                pendingMigrationUserId = authResult.user.uid

                // Write account/info to Firestore — after migration completes, not now.
                // (Data Manager Firestore guards are still active while isGuest=true.)
                let uid = authResult.user.uid
                let info = AccountInfoDTO(
                    displayName: displayName.trimmingCharacters(in: .whitespaces),
                    email: email.lowercased().trimmingCharacters(in: .whitespaces),
                    createdAt: Date()
                )
                Task {
                    try? await FirestoreServiceImpl.shared.writeAccountInfo(info, userId: uid)
                }
            } else {
                // Normal (non-guest) sign-up: write account/info, let listener update state.
                let uid = authResult.user.uid
                let info = AccountInfoDTO(
                    displayName: displayName.trimmingCharacters(in: .whitespaces),
                    email: email.lowercased().trimmingCharacters(in: .whitespaces),
                    createdAt: Date()
                )
                Task {
                    try? await FirestoreServiceImpl.shared.writeAccountInfo(info, userId: uid)
                }
                // isLoggedIn / currentUserEmail updated by auth state listener
            }
        } catch {
            throw Self.mapError(error)
        }
    }

    func logout() {
        // Stop all Firestore listeners BEFORE revoking auth (same as
        // continueAsGuest). Otherwise the sign-out kills every active listener
        // with permission-denied while FirestoreServiceImpl still holds their
        // handles and currentSyncUserId — so logging back into the SAME account
        // mid-session skips re-registration ("already listening") and the whole
        // session runs with dead listeners until the app is relaunched.
        FirestoreServiceImpl.shared.stopAllListeners()
        isGuest = false
        isNewUser = false
        pendingMigrationUserId = nil
        UserDefaults.standard.set(false, forKey: guestModeKey)
        // Explicitly clear state. In guest mode there is no Firebase user,
        // so Auth.auth().signOut() won't trigger the state listener.
        isLoggedIn = false
        currentUserEmail = nil
        try? Auth.auth().signOut()
    }

    // MARK: - Account Management

    /// Updates the Firebase Auth display name.
    func updateDisplayName(_ name: String) async throws {
        guard let user = Auth.auth().currentUser else {
            throw AuthError.unknown("Not authenticated.")
        }
        let changeRequest = user.createProfileChangeRequest()
        changeRequest.displayName = name.trimmingCharacters(in: .whitespaces)
        do {
            try await changeRequest.commitChanges()
        } catch {
            throw Self.mapError(error)
        }
    }

    /// Re-authenticates then sends a verification email to the new address.
    /// Firebase only updates the email after the user taps the verification link.
    func updateEmail(currentPassword: String, newEmail: String) async throws {
        try await reAuthenticate(password: currentPassword)
        guard let user = Auth.auth().currentUser else {
            throw AuthError.unknown("Not authenticated.")
        }
        do {
            try await user.sendEmailVerification(beforeUpdatingEmail: newEmail)
        } catch {
            throw Self.mapError(error)
        }
    }

    /// Re-authenticates then updates the password.
    func updatePassword(currentPassword: String, newPassword: String) async throws {
        try await reAuthenticate(password: currentPassword)
        guard let user = Auth.auth().currentUser else {
            throw AuthError.unknown("Not authenticated.")
        }
        do {
            try await user.updatePassword(to: newPassword)
        } catch {
            throw Self.mapError(error)
        }
    }

    /// Re-authenticates the current user with their password.
    /// Called internally before sensitive operations (email change, password change, delete).
    func reAuthenticate(password: String) async throws {
        guard let user = Auth.auth().currentUser,
              let email = user.email else {
            throw AuthError.unknown("Not authenticated.")
        }
        let credential = EmailAuthProvider.credential(withEmail: email, password: password)
        do {
            try await user.reauthenticate(with: credential)
        } catch {
            // Map wrongPassword specifically to "Incorrect password"
            let mapped = Self.mapError(error)
            if case .invalidCredentials = mapped {
                throw AuthError.unknown("Incorrect password.")
            }
            throw mapped
        }
    }

    /// Deletes the Firebase Auth account. Call AFTER Firestore data has been deleted.
    func deleteAuthAccount() async throws {
        guard let user = Auth.auth().currentUser else {
            throw AuthError.unknown("Not authenticated.")
        }
        do {
            try await user.delete()
        } catch {
            throw Self.mapError(error)
        }
    }

    // MARK: - Error Mapping

    /// Maps Firebase `AuthErrorCode` errors to the app's `AuthError` enum.
    ///
    /// `AuthViewModel` catches `AuthError` specifically, so Firebase errors
    /// must be re-thrown as `AuthError` for the correct banner messages to appear.
    static func mapError(_ error: Error) -> AuthError {
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
