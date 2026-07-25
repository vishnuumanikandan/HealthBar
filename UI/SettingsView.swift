//
//  SettingsView.swift
//  HealthBar
//
//  Created by Claude on 7/12/26.
//

import SwiftUI

/// R7b §2: the app's settings, moved wholesale out of ProfileView and reached from a gear in
/// Profile's top-right toolbar. A pushed screen inside Profile's existing NavigationStack
/// (FriendsView precedent) — it constructs NO view model of its own; the values passed in are
/// its entire data surface. Returning to Profile triggers Profile's single on-return reload,
/// so SettingsView needs no reload wiring of its own.
struct SettingsView: View {

    /// Coordinator for the presented sheets (Daily Goals, Account) and the onboarding editor.
    private let coordinator: AppCoordinator
    /// Read-only — gates the Account row and the Sign Out row's guest branch.
    private let authService: any AuthService
    /// Ends the auth session (provided by ProfileView, itself from ContentView).
    private let onLogout: () -> Void
    /// Snapshot passed in for the Edit Health Profile onboarding editor (SettingsView has no VM).
    private let existingProfile: UserProfile?

    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }

    // Presentation state, moved verbatim from ProfileView (Tools omitted — deleted, not moved).
    @State private var showingDailyGoals = false
    @State private var showingAccessibility = false
    @State private var showingOnboarding = false
    @State private var showingAccount = false
    @State private var showGuestSignOutWarning = false
    // FEEDBACK-1: the compose sheet + the presenter's transient "thanks" confirmation.
    @State private var showingFeedback = false
    @State private var showFeedbackConfirmation = false

    init(
        coordinator: AppCoordinator,
        authService: any AuthService,
        onLogout: @escaping () -> Void,
        existingProfile: UserProfile?
    ) {
        self.coordinator = coordinator
        self.authService = authService
        self.onLogout = onLogout
        self.existingProfile = existingProfile
    }

    var body: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.sm) {
                // Daily Goals button - navigates to goal editing
                settingButton(
                    icon: "target",
                    title: "Daily Goals",
                    subtitle: "Customize your targets",
                    action: {
                        showingDailyGoals = true
                    }
                )

                // Accessibility button - navigates to accessibility settings
                settingButton(
                    icon: "accessibility",
                    title: "Accessibility",
                    subtitle: "Display & notification preferences",
                    action: {
                        showingAccessibility = true
                    }
                )
                // TUT-1b changeTheme beacon (Decision 7) — the Accessibility row leads to the theme picker.
                // settingButton is an adaptiveCard — match its radius exactly.
                .questBeacon(TutorialCatalog.changeThemeId, cornerRadius: DesignSystem.Erewhon.cardRadius)

                // Edit Health Profile — opens onboarding in edit mode
                settingButton(
                    icon: "person.crop.circle.badge.checkmark",
                    title: "Edit Health Profile",
                    subtitle: "Update your goals and preferences",
                    iconColor: tc.primary,
                    action: { showingOnboarding = true }
                )

                // Account button — hidden for guest users (requires a real account)
                if !authService.isGuest {
                    settingButton(
                        icon: "person.circle",
                        title: "Account",
                        subtitle: "Manage username, display name, password",
                        action: { showingAccount = true }
                    )
                }

                // Send Feedback — hidden for guests (writes to the signed-in
                // account; mirrors the Account row's guest gating). Sits directly
                // above About.
                if !authService.isGuest {
                    settingButton(
                        icon: "envelope",
                        title: "Send Feedback",
                        subtitle: "Tell the developer what's working — or not",
                        action: { showingFeedback = true }
                    )
                }

                // About button (placeholder)
                settingButton(
                    icon: "info.circle",
                    title: "About",
                    subtitle: "App version and info",
                    action: {
                        // Placeholder - will navigate to about screen later
                    }
                )

                // Sign Out — for guests shows a warning before deleting local data
                settingButton(
                    icon: "rectangle.portrait.and.arrow.right",
                    title: "Sign Out",
                    subtitle: authService.isGuest
                        ? "Delete local data and exit guest mode"
                        : "Log out of your account",
                    iconColor: DesignSystem.Colors.danger,
                    isDanger: true,
                    action: {
                        if authService.isGuest {
                            showGuestSignOutWarning = true
                        } else {
                            onLogout()
                        }
                    }
                )
            }
            .padding(DesignSystem.Spacing.lg)
        }
        .background(tc.primaryBackground.ignoresSafeArea())
        // FEEDBACK-1: the presenter's transient success confirmation, shown after
        // the compose sheet dismisses and auto-hidden after 2s (set in the sheet's
        // onSuccess closure below).
        .overlay(alignment: .bottom) {
            if showFeedbackConfirmation {
                Text("Thanks — your feedback was sent.")
                    .font(AppFont.bold(14))
                    .foregroundColor(tc.textPrimary)
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.vertical, DesignSystem.Spacing.md)
                    .adaptiveCard(
                        borderColor: tc.primary.opacity(0.3),
                        fillColor: tc.cardBackground
                    )
                    .padding(.bottom, DesignSystem.Erewhon.tabBarContentHeight + 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Settings")
                    .font(AppFont.display(20))
                    .foregroundColor(tc.textPrimary)
            }
        }
        // R2 §5: reserve the bottom tab bar's height (the TabView's bottom safeAreaInset
        // doesn't reach this pushed screen's ScrollView).
        .contentMargins(.bottom, DesignSystem.Erewhon.tabBarContentHeight + 12, for: .scrollContent)
        .sheet(isPresented: $showingDailyGoals) {
            DailyGoalsView(coordinator: coordinator)
        }
        .sheet(isPresented: $showingAccessibility) {
            AccessibilitySettingsView(coordinator: coordinator)
        }
        .sheet(isPresented: $showingAccount) {
            AccountView(coordinator: coordinator, authService: FirebaseAuthService.shared)
        }
        .sheet(isPresented: $showingFeedback) {
            FeedbackComposeView(coordinator: coordinator) {
                // Success: show the presenter's transient confirmation for 2s.
                withAnimation { showFeedbackConfirmation = true }
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation { showFeedbackConfirmation = false }
                }
            }
        }
        .fullScreenCover(isPresented: $showingOnboarding) {
            OnboardingView(
                coordinator: coordinator,
                authService: FirebaseAuthService.shared,
                existingProfile: existingProfile
            )
        }
        // Guest sign-out warning: deleting local data is irreversible
        .confirmationDialog(
            "Sign Out of Guest Mode?",
            isPresented: $showGuestSignOutWarning,
            titleVisibility: .visible
        ) {
            Button("Sign Out & Delete Data", role: .destructive) {
                Task {
                    try? await coordinator.deleteAllGuestData()
                    onLogout()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You're using guest mode. Signing out will delete all local data. Create a free account first to save your progress.")
        }
    }

    /// Reusable settings button component (moved verbatim from ProfileView).
    private func settingButton(
        icon: String,
        title: String,
        subtitle: String,
        iconColor: Color = SettingsManager.shared.activeColors.primary,
        isDanger: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: DesignSystem.Spacing.md) {
                // Icon
                Image(systemName: icon)
                    .font(AppFont.bold(18))
                    .foregroundColor(.white)
                    .frame(width: DesignSystem.Sizes.iconCircle, height: DesignSystem.Sizes.iconCircle)
                    .adaptivePill(
                        borderColor: SettingsManager.shared.isCleanUI ? .clear : iconColor.adjustedBrightness(-0.2),
                        fillColor: .clear,
                        fillGradient: DesignSystem.Colors.adaptiveGradientFrom(iconColor)
                    )

                // Text
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text(title)
                        .font(AppFont.bold(16))
                        .foregroundColor(tc.textPrimary)

                    Text(subtitle)
                        .font(AppFont.regular(12))
                        .foregroundColor(tc.textSecondary)
                }

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(AppFont.bold(14))
                    .foregroundColor(tc.textTertiary)
            }
            .padding(DesignSystem.Spacing.md)
            .adaptiveCard(
                borderColor: isDanger ? DesignSystem.Colors.danger : tc.primary.opacity(0.3),
                fillColor: tc.cardBackground
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Feedback Compose Sheet (FEEDBACK-1)

/// The compose sheet — a small local view (no view model, no own file, per the
/// prompt). Validation here is UX-only; `DataManager.submitFeedback` revalidates
/// and is the authority. A successful submit calls `onSuccess` then self-dismisses
/// (NOT via onDismiss/onDisappear, which fire on the success path too — the
/// AILOG-1c lesson); a failure keeps the sheet open with an inline error and Send
/// re-enabled.
private struct FeedbackComposeView: View {

    private let coordinator: AppCoordinator
    /// Called exactly once, on a successful submit, immediately before self-dismiss,
    /// so the presenter can show its transient confirmation.
    private let onSuccess: () -> Void

    init(coordinator: AppCoordinator, onSuccess: @escaping () -> Void) {
        self.coordinator = coordinator
        self.onSuccess = onSuccess
    }

    @Environment(\.dismiss) private var dismiss
    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }

    @State private var message = ""
    @State private var isSubmitting = false
    @State private var errorText: String?

    /// The trimmed draft — the exact value DataManager would store.
    private var trimmed: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var isOverLimit: Bool { message.count > FeedbackLimits.maxLength }
    /// Send is enabled only for a non-empty, in-bounds draft that isn't mid-send.
    private var canSend: Bool { !trimmed.isEmpty && !isOverLimit && !isSubmitting }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    // Persistent label (always visible — not a placeholder).
                    Text("What's on your mind?")
                        .font(AppFont.display(16))
                        .foregroundColor(tc.textPrimary)

                    TextEditor(text: $message)
                        .font(AppFont.regular(15))
                        .foregroundColor(tc.textPrimary)
                        .frame(minHeight: 160, maxHeight: 280)
                        .scrollContentBackground(.hidden)
                        .padding(DesignSystem.Spacing.sm)
                        .adaptiveCard(
                            borderColor: tc.primary.opacity(0.3),
                            fillColor: tc.primaryBackground
                        )
                        .accessibilityLabel("Feedback message")

                    // Live character counter — appears only past the threshold.
                    if message.count > FeedbackLimits.counterThreshold {
                        Text("\(message.count) / \(FeedbackLimits.maxLength)")
                            .font(AppFont.regular(12))
                            .foregroundColor(isOverLimit ? DesignSystem.Colors.danger : tc.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    // Failure path: inline error; the sheet stays open and Send
                    // re-enables (isSubmitting is reset in submit()'s catch).
                    if let errorText {
                        Text(errorText)
                            .font(AppFont.regular(13))
                            .foregroundColor(DesignSystem.Colors.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    AppButton(
                        title: "Send",
                        style: .primary,
                        action: { submit() },
                        isLoading: isSubmitting,
                        isDisabled: !canSend
                    )
                }
                .padding(DesignSystem.Spacing.lg)
            }
            .background(tc.primaryBackground.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Send Feedback")
                        .font(AppFont.display(20))
                        .foregroundColor(tc.textPrimary)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(tc.textSecondary)
                }
            }
        }
    }

    private func submit() {
        // Double-tap guard: canSend is already false while isSubmitting and
        // AppButton ignores taps while isLoading — this belt-and-suspenders re-check
        // ensures a queued tap can't open a second write.
        guard canSend else { return }
        isSubmitting = true
        errorText = nil
        Task { @MainActor in
            do {
                try await coordinator.submitFeedback(message: message)
                onSuccess()
                dismiss()
            } catch {
                errorText = "Couldn't send your feedback. Check your connection and try again."
                isSubmitting = false
            }
        }
    }
}
