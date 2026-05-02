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
    }

    // MARK: - Save Display Name

    func saveDisplayName() async {
        displayNameError = nil
        let trimmed = displayName.trimmingCharacters(in: .whitespaces)

        guard trimmed.count >= 2, trimmed.count <= 30 else {
            displayNameError = "Display name must be 2–30 characters."
            return
        }

        isSavingDisplayName = true
        defer { isSavingDisplayName = false }

        do {
            // 1. Update Firebase Auth profile
            try await authService.updateDisplayName(trimmed)

            // 2. Write full account/info to Firestore
            let userId = authService.currentUserEmail ?? ""
            if !userId.isEmpty {
                let info = AccountInfoDTO(
                    displayName: trimmed,
                    email: currentEmail,
                    createdAt: Date()
                )
                try await firestoreService.writeAccountInfo(info, userId: userId)
            }

            // 3. Update local UserProfile
            try await coordinator.updateUserProfileDisplayName(trimmed)

            showToast("Display name updated.")
        } catch {
            displayNameError = error.localizedDescription
        }
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
    private var tc: ThemeColors { settings.activeTheme.colors }

    init(coordinator: AppCoordinator, authService: FirebaseAuthService) {
        self._viewModel = State(
            initialValue: AccountViewModel(coordinator: coordinator, authService: authService)
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            tc.primaryBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: DesignSystem.Spacing.lg) {
                    displayNameSection
                    emailSection
                    passwordSection
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
                    .font(PixelFont.bold(20))
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

                AppButton(
                    title: "Save",
                    style: .primary,
                    action: { Task { await viewModel.saveDisplayName() } },
                    isLoading: viewModel.isSavingDisplayName
                )
            }
        }
    }

    // MARK: - Email Section

    private var emailSection: some View {
        sectionCard(title: "Email") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text(viewModel.currentEmail.isEmpty ? "—" : viewModel.currentEmail)
                    .font(PixelFont.bold(16))
                    .foregroundColor(tc.textPrimary)

                Text("To change your email, contact support.")
                    .font(PixelFont.regular(14))
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
                        .font(PixelFont.bold(20))
                        .foregroundColor(tc.textPrimary)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button { viewModel.showPasswordSheet = false } label: {
                        Text("Cancel").font(PixelFont.regular(16))
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
                            .font(PixelFont.regular(16))
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
                        .font(PixelFont.bold(20))
                        .foregroundColor(tc.textPrimary)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button { viewModel.showDeleteSheet = false } label: {
                        Text("Cancel").font(PixelFont.regular(16))
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
                .font(PixelFont.bold(20))
                .foregroundColor(tc.textPrimary)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                content()
            }
            .padding(DesignSystem.Spacing.md)
            .pixelCard(borderColor: borderColor ?? tc.primary, fillColor: tc.cardBackground)
        }
    }

    private func toastBanner(_ message: String) -> some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(tc.primary)
            Text(message)
                .font(PixelFont.bold(16))
                .foregroundColor(tc.textPrimary)
            Spacer()
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .pixelCard(borderColor: tc.primary, fillColor: tc.cardBackground)
    }
}
