//
//  AccountView.swift
//  HealthBar
//
//  Created by Claude on 4/8/26.
//

import SwiftUI
import FirebaseAuth

// MARK: - AccountViewModel

@Observable
@MainActor
final class AccountViewModel {

    // MARK: - Display Name

    var displayName: String = ""
    var displayNameError: String? = nil
    var isSavingDisplayName: Bool = false
    var displayNameCooldownEnd: Date? = nil

    // MARK: - Username

    var currentUsername: String = ""
    var newUsername: String = ""
    var usernameError: String? = nil
    var isSavingUsername: Bool = false
    var isEditingUsername: Bool = false
    var usernameCooldownEnd: Date? = nil

    // MARK: - Current Email (read-only)

    var currentEmail: String = ""

    // MARK: - Password Sheet State

    var showPasswordSheet: Bool = false
    var currentPassword: String = ""
    var newPassword: String = ""
    var confirmNewPassword: String = ""
    var passwordError: String? = nil
    var isLoadingPassword: Bool = false

    // MARK: - Delete Sheet State

    var showDeleteSheet: Bool = false
    var currentPasswordForDelete: String = ""
    var deleteConfirmText: String = ""
    var deleteError: String? = nil
    var isLoadingDelete: Bool = false

    // MARK: - Toast

    var toastMessage: String? = nil

    // MARK: - Dependencies

    private let coordinator: AppCoordinator
    private let authService: FirebaseAuthService
    private let firestoreService: FirestoreService

    // MARK: - Initialization

    init(coordinator: AppCoordinator, authService: FirebaseAuthService) {
        self.coordinator = coordinator
        self.authService = authService
        self.firestoreService = FirestoreServiceImpl.shared
    }

    /// UGC-1b (D10): gates the Blocked Users row out of the settings list for guests.
    var isGuest: Bool { coordinator.isGuest }

    // MARK: - Load

    func loadData() async {
        if let profile = try? await coordinator.getUserProfile() {
            displayName = profile.displayName.isEmpty
                ? (authService.currentUserDisplayName ?? "")
                : profile.displayName
        } else {
            displayName = authService.currentUserDisplayName ?? ""
        }
        currentEmail = Auth.auth().currentUser?.email ?? ""

        // Load username + cooldowns
        if let username = await coordinator.currentUsername() {
            currentUsername = username
        }
        usernameCooldownEnd = await coordinator.usernameCooldownEnd()
        displayNameCooldownEnd = await coordinator.displayNameCooldownEnd()
    }

    // MARK: - Save Display Name

    func saveDisplayName() async {
        displayNameError = nil
        let trimmed = displayName.trimmingCharacters(in: .whitespaces)

        guard trimmed.count >= 2, trimmed.count <= 30 else {
            displayNameError = "Display name must be 2–30 characters."
            return
        }

        // UGC-1b (D9b): reject a disallowed display name on CONTENT before the cooldown check —
        // a dirty name should fail on what it is, not burn a "you can change again on…" message.
        guard !ProfanityFilter.containsBlockedTerm(trimmed) else {
            displayNameError = "That name isn't allowed."
            return
        }

        // Enforce 7-day cooldown
        if let cooldownEnd = displayNameCooldownEnd, Date() < cooldownEnd {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            displayNameError = "You can change your display name again on \(formatter.string(from: cooldownEnd))."
            return
        }

        isSavingDisplayName = true
        defer { isSavingDisplayName = false }

        do {
            // 1. Update Firebase Auth profile
            try await authService.updateDisplayName(trimmed)

            // 2. Write account/info with lastDisplayNameChangeAt timestamp
            let userId = authService.currentUserEmail ?? ""
            if !userId.isEmpty {
                let info = AccountInfoDTO(
                    displayName: trimmed,
                    email: currentEmail,
                    createdAt: Date(),
                    lastDisplayNameChangeAt: Date()
                )
                try await firestoreService.writeAccountInfo(info, userId: userId)
            }

            // 3. Update local UserProfile
            try await coordinator.updateUserProfileDisplayName(trimmed)

            // Update local cooldown state
            displayNameCooldownEnd = Calendar.current.date(byAdding: .day, value: 7, to: Date())

            showToast("Display name updated.")
        } catch {
            displayNameError = error.localizedDescription
        }
    }

    // MARK: - Save Username

    func saveUsername() async {
        usernameError = nil

        isSavingUsername = true
        defer { isSavingUsername = false }

        do {
            try await coordinator.changeUsername(to: newUsername)
            let normalized = try DataManager.normalizeAndValidateUsername(newUsername)
            currentUsername = normalized
            newUsername = ""
            isEditingUsername = false
            usernameCooldownEnd = Calendar.current.date(byAdding: .day, value: 30, to: Date())
            showToast("Username updated.")
        } catch let e as UsernameError {
            usernameError = e.errorDescription
        } catch {
            usernameError = UsernameError.network(error.localizedDescription).errorDescription
        }
    }

    var isUsernameSubmittable: Bool {
        guard !isSavingUsername, !newUsername.isEmpty else { return false }
        return (try? DataManager.normalizeAndValidateUsername(newUsername)) != nil
    }

    // MARK: - Change Password

    func changePassword() async {
        passwordError = nil

        let trimmedCurrent = currentPassword.trimmingCharacters(in: .whitespaces)
        guard !trimmedCurrent.isEmpty else {
            passwordError = "Please enter your current password."
            return
        }
        guard newPassword.count >= 8 else {
            passwordError = "New password must be at least 8 characters."
            return
        }
        guard newPassword.contains(where: \.isNumber) else {
            passwordError = "New password must contain at least one number."
            return
        }
        guard newPassword == confirmNewPassword else {
            passwordError = "Passwords do not match."
            return
        }

        isLoadingPassword = true
        defer { isLoadingPassword = false }

        do {
            try await authService.updatePassword(
                currentPassword: trimmedCurrent,
                newPassword: newPassword
            )
            showPasswordSheet = false
            resetPasswordFields()
            showToast("Password updated.")
        } catch {
            passwordError = error.localizedDescription
        }
    }

    // MARK: - Delete Account

    func deleteAccount() async {
        deleteError = nil

        guard deleteConfirmText == "DELETE" else {
            deleteError = "Type DELETE to confirm."
            return
        }
        let trimmedPassword = currentPasswordForDelete.trimmingCharacters(in: .whitespaces)
        guard !trimmedPassword.isEmpty else {
            deleteError = "Please enter your password."
            return
        }

        isLoadingDelete = true
        defer { isLoadingDelete = false }

        do {
            // 1. Re-authenticate
            try await authService.reAuthenticate(password: trimmedPassword)

            // 2. Best-effort: delete Firestore data first.
            // Silenced — orphaned data is inaccessible after auth deletion and
            // doesn't block the user from completing account removal.
            let userId = authService.currentUserEmail ?? ""
            if !userId.isEmpty {
                try? await firestoreService.deleteAllUserData(userId: userId)
            }

            // 3. Delete Firebase Auth account (hard failure — must succeed)
            try await authService.deleteAuthAccount()

            // Auth state listener fires → isLoggedIn = false → ContentView returns to login
        } catch {
            deleteError = error.localizedDescription
        }
    }

    // MARK: - Private Helpers

    private func showToast(_ message: String) {
        toastMessage = message
        Task {
            try? await Task.sleep(for: .seconds(3))
            if toastMessage == message { toastMessage = nil }
        }
    }

    private func resetPasswordFields() {
        currentPassword = ""
        newPassword = ""
        confirmNewPassword = ""
        passwordError = nil
    }

    private func resetDeleteFields() {
        currentPasswordForDelete = ""
        deleteConfirmText = ""
        deleteError = nil
    }
}

// MARK: - AccountView

/// Account management screen: display name, email info, password change, delete account.
///
/// Pushed via NavigationLink from ProfileView's settings section.
struct AccountView: View {

    @State private var viewModel: AccountViewModel
    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }

    /// UGC-1b: retained to construct the Blocked Users subscreen.
    private let coordinator: AppCoordinator

    /// UGC-1b: presents the Blocked Users subscreen. AccountView is itself presented as a
    /// sheet (no ambient NavigationStack), so the subscreen is a sheet too — matching the
    /// password/delete sheets rather than a push that would have no stack to push onto.
    @State private var showBlockedUsers = false

    /// TUT-1a: presents the welcome popup in read-only replay mode as an overlay in this
    /// view's context. Replay is STATELESS — it writes nothing (no step reset, no XP
    /// re-award, no seen mutation); both SKIP and Start simply dismiss.
    @State private var showReplayTutorial = false

    init(coordinator: AppCoordinator, authService: FirebaseAuthService) {
        self.coordinator = coordinator
        self._viewModel = State(
            initialValue: AccountViewModel(coordinator: coordinator, authService: authService)
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            tc.primaryBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: DesignSystem.Spacing.lg) {
                    usernameSection
                    displayNameSection
                    emailSection
                    passwordSection
                    // UGC-1b (D10): hidden for guests (they never block anyone).
                    if !viewModel.isGuest {
                        blockedUsersSection
                    }
                    // TUT-1a: hidden for guests (they have no tutorial); shown to every
                    // other user regardless of tutorial done-ness.
                    if !viewModel.isGuest {
                        tutorialSection
                    }
                    dangerSection
                }
                .padding(DesignSystem.Spacing.lg)
            }

            // Success toast
            if let message = viewModel.toastMessage {
                toastBanner(message)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, DesignSystem.Spacing.sm)
                    .padding(.horizontal, DesignSystem.Spacing.md)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: viewModel.toastMessage)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Account")
                    .font(AppFont.bold(20))
                    .foregroundColor(tc.textPrimary)
            }
        }
        .task { await viewModel.loadData() }
        .sheet(isPresented: $viewModel.showPasswordSheet) {
            passwordSheetView
        }
        .sheet(isPresented: $viewModel.showDeleteSheet) {
            deleteSheetView
        }
        .sheet(isPresented: $showBlockedUsers) {
            BlockedUsersView(coordinator: coordinator)
        }
        .overlay {
            // TUT-1a: replay the welcome popup, read-only (isReplay). Dismiss-only closures
            // ⇒ no state writes of any kind (Decision 11). Greeting handle comes from the
            // already-loaded account VM (no new fetch).
            if showReplayTutorial {
                TutorialWelcomePopup(
                    username: viewModel.currentUsername.isEmpty ? nil : viewModel.currentUsername,
                    isReplay: true,
                    onStart: { showReplayTutorial = false },
                    onSkip: { showReplayTutorial = false }
                )
                .transition(.opacity)
            }
        }
    }

    // MARK: - Username Section

    private var usernameSection: some View {
        sectionCard(title: "Username") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                if viewModel.isEditingUsername {
                    // Edit mode
                    HStack(spacing: 0) {
                        Text("@")
                            .font(AppFont.bold(17))
                            .foregroundColor(tc.textSecondary)
                            .padding(.leading, DesignSystem.Spacing.md)

                        TextField("new_username", text: $viewModel.newUsername)
                            .font(AppFont.regular(DesignSystem.FontSizes.body))
                            .foregroundColor(tc.textPrimary)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(.leading, DesignSystem.Spacing.xs)
                            .padding(.trailing, DesignSystem.Spacing.md)
                            .padding(.vertical, DesignSystem.Spacing.md)
                            .submitLabel(.done)
                            .onSubmit {
                                if viewModel.isUsernameSubmittable {
                                    Task { await viewModel.saveUsername() }
                                }
                            }
                    }
                    .frame(minHeight: 52)
                    .background(tc.cardBackground)
                    .clipShape(AdaptiveCardShapeStyle())
                    .overlay(
                        AdaptiveCardShapeStyle()
                            .stroke(
                                viewModel.usernameError != nil
                                    ? DesignSystem.Colors.danger
                                    : tc.primary.opacity(0.3),
                                lineWidth: viewModel.usernameError != nil ? 2 : 1
                            )
                    )

                    if let error = viewModel.usernameError {
                        Text(error)
                            .font(AppFont.regular(12))
                            .foregroundColor(DesignSystem.Colors.danger)
                    }

                    HStack(spacing: DesignSystem.Spacing.sm) {
                        AppButton(
                            title: "Save",
                            style: .primary,
                            action: { Task { await viewModel.saveUsername() } },
                            isLoading: viewModel.isSavingUsername,
                            isDisabled: !viewModel.isUsernameSubmittable
                        )

                        AppButton(
                            title: "Cancel",
                            style: .secondary,
                            action: {
                                viewModel.isEditingUsername = false
                                viewModel.newUsername = ""
                                viewModel.usernameError = nil
                            }
                        )
                    }
                } else {
                    // Display mode
                    HStack {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                            Text("@\(viewModel.currentUsername)")
                                .font(AppFont.bold(17))
                                .foregroundColor(tc.textPrimary)

                            if let cooldownEnd = viewModel.usernameCooldownEnd, Date() < cooldownEnd {
                                let formatter = {
                                    let f = DateFormatter()
                                    f.dateStyle = .medium
                                    return f
                                }()
                                Text("Can change again on \(formatter.string(from: cooldownEnd))")
                                    .font(AppFont.regular(12))
                                    .foregroundColor(tc.textTertiary)
                            }
                        }

                        Spacer()

                        if viewModel.usernameCooldownEnd == nil || Date() >= (viewModel.usernameCooldownEnd ?? .distantPast) {
                            Button {
                                viewModel.newUsername = ""
                                viewModel.usernameError = nil
                                viewModel.isEditingUsername = true
                            } label: {
                                Text("Change")
                                    .font(AppFont.bold(14))
                                    .foregroundColor(tc.primary)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Display Name Section

    private var displayNameSection: some View {
        sectionCard(title: "Display Name") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                AuthTextField(
                    label: "Name",
                    placeholder: "Your display name",
                    text: $viewModel.displayName,
                    errorMessage: viewModel.displayNameError,
                    submitLabel: .done,
                    onSubmit: { Task { await viewModel.saveDisplayName() } }
                )

                if let cooldownEnd = viewModel.displayNameCooldownEnd, Date() < cooldownEnd {
                    let formatter = {
                        let f = DateFormatter()
                        f.dateStyle = .medium
                        return f
                    }()
                    Text("Can change again on \(formatter.string(from: cooldownEnd))")
                        .font(AppFont.regular(12))
                        .foregroundColor(tc.textTertiary)
                }

                AppButton(
                    title: "Save",
                    style: .primary,
                    action: { Task { await viewModel.saveDisplayName() } },
                    isLoading: viewModel.isSavingDisplayName,
                    isDisabled: viewModel.displayNameCooldownEnd != nil && Date() < (viewModel.displayNameCooldownEnd ?? .distantPast)
                )
            }
        }
    }

    // MARK: - Email Section

    private var emailSection: some View {
        sectionCard(title: "Email") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text(viewModel.currentEmail.isEmpty ? "—" : viewModel.currentEmail)
                    .font(AppFont.bold(16))
                    .foregroundColor(tc.textPrimary)

                Text("To change your email, contact support.")
                    .font(AppFont.regular(14))
                    .foregroundColor(tc.textSecondary)
            }
        }
    }

    // MARK: - Password Section

    private var passwordSection: some View {
        sectionCard(title: "Password") {
            AppButton(
                title: "Change Password",
                style: .secondary,
                action: { viewModel.showPasswordSheet = true }
            )
        }
    }

    // MARK: - Blocked Users Section (UGC-1b)

    private var blockedUsersSection: some View {
        sectionCard(title: "Safety") {
            Button {
                showBlockedUsers = true
            } label: {
                HStack {
                    Text("Blocked Users")
                        .font(AppFont.bold(16))
                        .foregroundColor(tc.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(AppFont.regular(13))
                        .foregroundColor(tc.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    // MARK: - Tutorial Section (TUT-1a)

    /// "Replay tutorial" — presents the welcome popup in read-only replay mode. Matches the
    /// Blocked Users row component style exactly (Button + label + chevron in a sectionCard).
    private var tutorialSection: some View {
        sectionCard(title: "Tutorial") {
            Button {
                showReplayTutorial = true
            } label: {
                HStack {
                    Text("Replay tutorial")
                        .font(AppFont.bold(16))
                        .foregroundColor(tc.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(AppFont.regular(13))
                        .foregroundColor(tc.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    // MARK: - Danger Section

    private var dangerSection: some View {
        sectionCard(title: "Danger Zone", borderColor: .red) {
            AppButton(
                title: "Delete Account",
                style: .secondary,
                action: { viewModel.showDeleteSheet = true }
            )
            .tint(DesignSystem.Colors.danger)
        }
    }

    // MARK: - Password Sheet

    private var passwordSheetView: some View {
        NavigationStack {
            ZStack {
                tc.primaryBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: DesignSystem.Spacing.md) {
                        AuthTextField(
                            label: "Current Password",
                            placeholder: "Enter current password",
                            text: $viewModel.currentPassword,
                            isSecure: true,
                            submitLabel: .next
                        )

                        AuthTextField(
                            label: "New Password",
                            placeholder: "At least 8 chars, 1 number",
                            text: $viewModel.newPassword,
                            isSecure: true,
                            submitLabel: .next
                        )

                        AuthTextField(
                            label: "Confirm New Password",
                            placeholder: "Repeat new password",
                            text: $viewModel.confirmNewPassword,
                            isSecure: true,
                            errorMessage: viewModel.passwordError,
                            submitLabel: .done,
                            onSubmit: { Task { await viewModel.changePassword() } }
                        )

                        AppButton(
                            title: "Update Password",
                            style: .primary,
                            action: { Task { await viewModel.changePassword() } },
                            isLoading: viewModel.isLoadingPassword
                        )
                    }
                    .padding(DesignSystem.Spacing.lg)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Change Password")
                        .font(AppFont.bold(20))
                        .foregroundColor(tc.textPrimary)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button { viewModel.showPasswordSheet = false } label: {
                        Text("Cancel").font(AppFont.regular(16))
                            .foregroundColor(tc.primary)
                    }
                }
            }
        }
    }

    // MARK: - Delete Sheet

    private var deleteSheetView: some View {
        NavigationStack {
            ZStack {
                tc.primaryBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                        Text("This will permanently delete your account and all associated data. This action cannot be undone.")
                            .font(AppFont.regular(16))
                            .foregroundColor(DesignSystem.Colors.danger)
                            .padding(.bottom, DesignSystem.Spacing.xs)

                        AuthTextField(
                            label: "Password",
                            placeholder: "Enter your password",
                            text: $viewModel.currentPasswordForDelete,
                            isSecure: true,
                            submitLabel: .next
                        )

                        AuthTextField(
                            label: "Type DELETE to confirm",
                            placeholder: "DELETE",
                            text: $viewModel.deleteConfirmText,
                            errorMessage: viewModel.deleteError,
                            submitLabel: .done,
                            onSubmit: { Task { await viewModel.deleteAccount() } }
                        )

                        AppButton(
                            title: "Delete My Account",
                            style: .primary,
                            action: { Task { await viewModel.deleteAccount() } },
                            isLoading: viewModel.isLoadingDelete
                        )
                        .tint(DesignSystem.Colors.danger)
                    }
                    .padding(DesignSystem.Spacing.lg)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Delete Account")
                        .font(AppFont.bold(20))
                        .foregroundColor(tc.textPrimary)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button { viewModel.showDeleteSheet = false } label: {
                        Text("Cancel").font(AppFont.regular(16))
                            .foregroundColor(tc.primary)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func sectionCard<Content: View>(title: String, borderColor: Color? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text(title)
                .font(AppFont.bold(20))
                .foregroundColor(tc.textPrimary)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                content()
            }
            .padding(DesignSystem.Spacing.md)
            // R6c: preserve retired heuristic — accent border when caller omits borderColor
            .adaptiveCard(borderColor: borderColor ?? tc.primary, fillColor: tc.cardBackground, isSelected: borderColor == nil)
        }
    }

    private func toastBanner(_ message: String) -> some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(tc.primary)
            Text(message)
                .font(AppFont.bold(16))
                .foregroundColor(tc.textPrimary)
            Spacer()
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .adaptiveCard(borderColor: tc.primary, fillColor: tc.cardBackground, isSelected: true)  // R6c: preserved implicit-selection (review intent later)
    }
}
