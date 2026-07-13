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
            AccessibilitySettingsView()
        }
        .sheet(isPresented: $showingAccount) {
            AccountView(coordinator: coordinator, authService: FirebaseAuthService.shared)
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
