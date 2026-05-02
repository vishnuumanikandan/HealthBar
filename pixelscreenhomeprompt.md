

## Claude Code Prompt: Fix Guest Auth Flow — 3 Critical Bugs

### Overview

Three bugs in the guest-mode authentication flow trap users in a broken state. All three stem from navigation/state issues in the auth layer — no data logic changes needed. An Apple reviewer flagged the login button as "unresponsive" because these bugs make it impossible for a guest to ever reach a working login screen.

### Files Modified

- `FirebaseAuthService.swift` — Bug 1 fix
- `ContentView.swift` — Bug 2 fix
- `SignUpView.swift` — Bug 3 fix

### Files NOT Modified

- `AuthService.swift` (protocol unchanged)
- `AuthViewModel.swift` (no changes needed)
- `ProfileView.swift` (no changes needed)
- `AppCoordinator.swift` (no changes needed)
- `LoginView.swift` (no changes needed)
- `DataManager.swift` (no changes needed)
- All model files, all other views

---

### Bug 1: Guest Sign-Out Does Not Navigate Back to Login

**Symptom:** Guest taps Sign Out → confirms destructive dialog → app stays on ProfileView with a dead Sign Out button. User is trapped.

**Root Cause:** `FirebaseAuthService.logout()` sets `isGuest = false`, then calls `Auth.auth().signOut()`. But in guest mode there is **no Firebase user** — the SDK has no auth state to change, so the `addStateDidChangeListener` callback never fires. The method relies entirely on that listener to set `isLoggedIn = false` and `currentUserEmail = nil`. Since the listener never fires, those stored properties keep their guest-mode values (`isLoggedIn = true`, `currentUserEmail = "guest"`). ContentView sees `isLoggedIn == true` and keeps showing `mainTabView`.

**Fix in `FirebaseAuthService.swift` → `logout()`:**

After the existing line `UserDefaults.standard.set(false, forKey: guestModeKey)` and before `try? Auth.auth().signOut()`, add explicit state clearing:

```swift
// Explicitly clear state. In guest mode there is no Firebase user,
// so Auth.auth().signOut() won't trigger the state listener.
// For real users the listener will fire and re-confirm these values.
isLoggedIn = false
currentUserEmail = nil
```

This is safe for authenticated (non-guest) users too — the auth state listener fires immediately after `Auth.auth().signOut()` and sets the same values. The explicit assignment just ensures guest mode doesn't fall through the cracks.

**Verification:** The full `logout()` method should read (in order):
1. `isGuest = false`
2. `isNewUser = false`
3. `pendingMigrationUserId = nil`
4. `UserDefaults.standard.set(false, forKey: guestModeKey)`
5. `isLoggedIn = false` ← NEW
6. `currentUserEmail = nil` ← NEW
7. `try? Auth.auth().signOut()`

---

### Bug 2: Sign-Up From Guest Does Not Dismiss Sheet or Auto-Login

**Symptom:** Guest taps "Create Account" in ProfileView banner → SignUpView appears in a sheet → guest fills out form and taps "Create Account" → account is created, migration runs in the background, but the sheet stays open. User sees a blank or stale SignUpView. They have no way to get into the app with their new account.

**Root Cause:** ContentView presents `SignUpView` inside `.sheet(isPresented: $showSignUpFromGuest)`. After sign-up succeeds:
- `FirebaseAuthService.signUp()` sets `pendingMigrationUserId` (for guest upgrade)
- `.onChange(of: authService.pendingMigrationUserId)` triggers migration
- `completeMigration()` sets `isLoggedIn = true`, `currentUserEmail = realUID`, `isGuest = false`

But **nothing ever sets `showSignUpFromGuest = false`**. The sheet stays presented, covering the now-authenticated main tab view underneath.

**Fix in `ContentView.swift`:**

In the `.onChange(of: authService.pendingMigrationUserId)` closure, inside the `do` block, after the line `coordinator.startFirestoreSyncForCurrentUser()`, add:

```swift
// Dismiss the guest sign-up sheet now that migration is complete.
showSignUpFromGuest = false
```

Also add the same dismissal in the `catch` block, after setting `migrationError`, so the sheet closes even on failure (the error alert will show on the main view):

```swift
showSignUpFromGuest = false
```

**Additionally:** Handle the case where a guest uses the sheet's sign-up flow but signs up as a **non-guest path** somehow (edge case safety). Add an `.onChange` observer on `authService.isGuest` to auto-dismiss:

Actually, strike that — the migration `onChange` handler already covers all paths. Just add the two `showSignUpFromGuest = false` lines (one in `do`, one in `catch`).

**Verification:** The `.onChange(of: authService.pendingMigrationUserId)` block should read:

```swift
.onChange(of: authService.pendingMigrationUserId) { _, newUserId in
    guard let newUserId else { return }
    Task {
        let coordinator = AppCoordinator(
            modelContext: modelContext,
            authService: FirebaseAuthService.shared
        )
        do {
            try await coordinator.migrateGuestData(to: newUserId)
            authService.completeMigration(newUserId: newUserId)
            coordinator.startFirestoreSyncForCurrentUser()
            showSignUpFromGuest = false          // ← NEW
        } catch {
            authService.cancelMigration()
            migrationError = "Failed to migrate data. Please try again."
            showSignUpFromGuest = false          // ← NEW
        }
    }
}
```

---

### Bug 3: "Already have an account? Log In" Is Not Tappable

**Symptom:** On the SignUpView (reached from guest's "Create Account" button), the "Already have an account? Log In" text at the bottom does nothing when tapped. User cannot navigate to a login screen.

**Root Cause:** In `SignUpView.swift` → `actionsSection`, the "Already have an account? / Log In" is rendered as plain `Text` views inside an `HStack`. There is no `Button`, `NavigationLink`, or tap gesture. In the normal auth flow (from `ContentView.authFlow`), this isn't a problem because `SignUpView` is pushed onto a `NavigationStack` and the system back button serves as the "go back to login" action. But when `SignUpView` is presented inside a `.sheet` (the guest upgrade path), there is no back button, and this text is the only visible way to navigate to login. Since it's just text, it's completely dead.

**Fix in `SignUpView.swift`:**

The fix needs to work in **both** presentation contexts:

1. **Normal auth flow** (pushed via NavigationStack): Tapping "Log In" should pop back to LoginView.
2. **Guest sheet** (presented via `.sheet`): Tapping "Log In" should dismiss the sheet. The user returns to the app in guest mode and can then sign out normally to reach the login screen. (Alternatively, dismissing the sheet is the correct behavior — they can sign out from ProfileView to reach the real login flow.)

**Implementation:**

Add `@Environment(\.dismiss) private var dismiss` to `SignUpView` (it doesn't currently have it).

Replace the static `HStack` at the bottom of `actionsSection` with a `Button`:

```swift
Button {
    dismiss()
} label: {
    HStack(spacing: DesignSystem.Spacing.xs) {
        Text("Already have an account?")
            .font(.system(size: DesignSystem.FontSizes.callout, weight: .regular))
            .foregroundColor(DesignSystem.Colors.textSecondary)

        Text("Log In")
            .font(.system(size: DesignSystem.FontSizes.callout, weight: .semibold))
            .foregroundColor(DesignSystem.Colors.primary)
    }
}
.frame(minHeight: 44)
.accessibilityLabel("Already have an account? Log In")
.accessibilityHint("Double-tap to return to the login screen")
```

**Why `dismiss()` works in both contexts:**
- **NavigationStack push (normal auth flow):** `dismiss()` pops the view, returning to LoginView. This is identical to pressing the system back button.
- **Sheet presentation (guest upgrade):** `dismiss()` dismisses the sheet, returning to ProfileView. The user is still in guest mode and can sign out to reach the full login screen.

Remove the old static `HStack` and its existing `accessibilityElement` / `accessibilityLabel` modifiers entirely — they are replaced by the button above.

---

### Edge Cases & Safety

1. **Double-tap on Sign Out during deletion:** The `coordinator.deleteAllGuestData()` is `async` — the confirmation dialog is already dismissed by SwiftUI before the closure runs. No double-tap risk.

2. **Migration failure after sheet dismiss:** If migration fails and `showSignUpFromGuest` is set to `false`, the error alert (`migrationError`) appears on the main tab view. The user is still in guest mode (`cancelMigration()` preserves it). They can retry "Create Account" from the guest banner.

3. **Firebase listener race after guest logout:** After Bug 1 fix, `isLoggedIn` is set to `false` synchronously before `Auth.auth().signOut()`. If the listener somehow fires (it shouldn't for guest-only sessions), it would set `isLoggedIn = false` again — idempotent, no conflict.

4. **Sheet dismiss animation vs. state change:** SwiftUI handles `showSignUpFromGuest = false` as an animated dismissal. The `completeMigration()` state changes (`isLoggedIn`, `currentUserEmail`) happen on the same `@MainActor` task, so the view hierarchy updates atomically — no flash of auth flow between sheet dismiss and state settle.

5. **iPad compatibility:** All three fixes are layout-agnostic. The `.sheet` presentation on iPad uses a form sheet by default — `dismiss()` and state binding dismissal both work identically.

### Testing Checklist

After applying all three fixes, verify:

- [ ] Guest taps Sign Out → confirms → returns to LoginView
- [ ] Guest taps "Create Account" → fills form → taps "Create Account" → sheet dismisses → app shows main tab view with real account
- [ ] Guest taps "Create Account" → taps "Already have an account? Log In" → sheet dismisses → returns to ProfileView in guest mode
- [ ] Normal (non-guest) login still works
- [ ] Normal (non-guest) sign-up still works (from LoginView → SignUpView push)
- [ ] Normal sign-up "Already have an account?" pops back to LoginView
- [ ] Normal sign-out still works
- [ ] Test on iPad (the Apple reviewer used iPad Air 11-inch M3)
