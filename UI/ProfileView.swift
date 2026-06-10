//
//  ProfileView.swift
//  HealthBar
//
//  Created by Claude on 1/23/26.
//

import SwiftUI
import SwiftData

/// Profile screen showing user stats and settings
///
/// Features:
/// - User avatar (placeholder)
/// - Current stats (XP, Level, Rank, Streaks)
/// - Settings section with navigation to goal editing
struct ProfileView: View {

    // MARK: - Properties

    /// The view model managing this view's state
    @State private var viewModel: ProfileViewModel

    /// Coordinator for navigation
    private let coordinator: AppCoordinator

    /// Show daily goals sheet
    @State private var showingDailyGoals = false

    /// Show accessibility settings sheet
    @State private var showingAccessibility = false

    /// Show onboarding / health profile editor
    @State private var showingOnboarding = false

    /// Show account management screen
    @State private var showingAccount = false

    /// Selected badge for detail sheet
    @State private var selectedBadge: BadgeDefinition? = nil

    /// Settings manager for app-wide settings
    @State private var settings = SettingsManager.shared

    /// Theme colors shortcut
    private var tc: ThemeColors { settings.activeColors }

    /// Callback that ends the auth session and returns to LoginView.
    /// Provided by ContentView — ProfileView never references the auth service directly.
    private let onLogout: () -> Void

    /// Callback invoked when a guest user taps "Create Account" in the upsell banner.
    /// ContentView presents the sign-up sheet in response.
    private let onCreateAccount: () -> Void

    /// Auth service reference — read-only, used only to check isGuest and isNewUser.
    /// ProfileView never calls methods on this directly.
    private let authService: any AuthService

    /// True when the guest sign-out warning dialog should be shown.
    @State private var showGuestSignOutWarning = false

    // MARK: - Initialization

    init(
        coordinator: AppCoordinator,
        authService: any AuthService,
        onLogout: @escaping () -> Void,
        onCreateAccount: @escaping () -> Void = {}
    ) {
        self.coordinator = coordinator
        self.authService = authService
        self.onLogout = onLogout
        self.onCreateAccount = onCreateAccount
        self._viewModel = State(initialValue: ProfileViewModel(coordinator: coordinator, authService: authService))
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                // Background color
                tc.primaryBackground
                    .ignoresSafeArea()

                if viewModel.isLoading {
                    loadingView
                } else if let error = viewModel.errorMessage {
                    errorView(error)
                } else {
                    contentView
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Profile")
                        .font(AppFont.bold(20))
                        .foregroundColor(tc.textPrimary)
                }
            }
            .refreshable {
                await viewModel.refresh()
            }
            .task {
                // Load data when view appears
                await viewModel.loadUserData()
            }
            .sheet(isPresented: $showingDailyGoals) {
                DailyGoalsView(coordinator: coordinator)
            }
            .sheet(isPresented: $showingAccessibility) {
                AccessibilitySettingsView()
            }
            .sheet(isPresented: $showingAccount) {
                AccountView(coordinator: coordinator, authService: FirebaseAuthService.shared)
            }
            .sheet(item: $selectedBadge) { badge in
                BadgeDetailSheet(
                    definition: badge,
                    progress: viewModel.badgeProgressList.first { $0.badgeId == badge.id }
                )
            }
            .fullScreenCover(isPresented: $showingOnboarding) {
                OnboardingView(
                    coordinator: coordinator,
                    authService: FirebaseAuthService.shared,
                    existingProfile: viewModel.existingProfile
                )
            }
            .onChange(of: showingOnboarding) { _, isShowing in
                if !isShowing {
                    Task { await viewModel.loadUserData() }
                }
            }
            .onChange(of: showingDailyGoals) { _, isShowing in
                // Refresh data when returning from goals screen
                if !isShowing {
                    Task {
                        await viewModel.loadUserData()
                    }
                }
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
    }

    // MARK: - Subviews

    /// Loading indicator
    private var loadingView: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading your profile...")
                .font(AppFont.regular(16))
                .foregroundColor(tc.textSecondary)
        }
    }

    /// Error view
    private func errorView(_ message: String) -> some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Image(systemName: "exclamationmark.triangle")
                .font(AppFont.regular(64))
                .foregroundStyle(DesignSystem.Colors.danger)

            VStack(spacing: DesignSystem.Spacing.sm) {
                Text("Error Loading Profile")
                    .font(AppFont.bold(22))
                    .foregroundColor(tc.textPrimary)

                Text(message)
                    .font(AppFont.regular(16))
                    .foregroundColor(tc.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DesignSystem.Spacing.xl)
            }

            AppButton(
                title: "Try Again",
                style: .primary,
                action: {
                    Task {
                        await viewModel.loadUserData()
                    }
                }
            )
            .padding(.horizontal, DesignSystem.Spacing.xl)
        }
        .padding()
    }

    /// Main content when data is loaded
    private var contentView: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.lg) {
                // Guest mode upsell banner — shown above all other content
                if authService.isGuest {
                    guestBanner
                }
                avatarSection
                xpProgressSection
                statsSection
                badgesSection
                settingsSection
            }
            .padding(DesignSystem.Spacing.lg)
        }
    }

    // MARK: - Guest Banner

    /// Shown at the top of the profile when the user has no account.
    /// Explains local-only storage and offers a path to sign up.
    private var guestBanner: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Your data is stored locally on this device. It may be lost if the app is deleted. Create a free account to back up your progress.")
                .font(AppFont.regular(12))
                .foregroundColor(tc.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            AppButton(
                title: "Create Account",
                style: .primary,
                action: { onCreateAccount() }
            )
        }
        .padding(DesignSystem.Spacing.md)
        .adaptiveCard(borderColor: tc.macroBarCarbs, fillColor: tc.cardBackground)
    }

    // MARK: - Avatar Section

    private var avatarSection: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            // Avatar — pixel-bordered square portrait
            ZStack {
                AdaptiveCardShapeStyle()
                    .fill(DesignSystem.Colors.adaptiveGradient(light: tc.buttonLight, mid: tc.buttonMid, dark: tc.buttonDark))
                    .frame(width: 100, height: 100)

                Text(viewModel.userInitials)
                    .font(AppFont.bold(42))
                    .foregroundColor(.white)
            }
            .clipShape(AdaptiveCardShapeStyle())

            Text(viewModel.displayName)
                .font(AppFont.bold(22))
                .foregroundColor(tc.textPrimary)

            if let username = viewModel.username, !username.isEmpty {
                Text("@\(username)")
                    .font(AppFont.regular(14))
                    .foregroundColor(tc.textSecondary)
            }

            // Rank badge
            HStack(spacing: DesignSystem.Spacing.xs) {
                Image(systemName: "crown.fill")
                    .font(AppFont.bold(14))
                    .foregroundColor(tc.primary)

                Text(viewModel.currentRank.displayName)
                    .font(AppFont.regular(14))
                    .foregroundColor(tc.textSecondary)
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .adaptivePill(borderColor: tc.primary, fillColor: tc.primary.opacity(0.15))
        }
        .padding(.vertical, DesignSystem.Spacing.md)
    }

    // MARK: - Stats Section

    private var statsSection: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            Text("Stats")
                .font(AppFont.bold(22))
                .foregroundColor(tc.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Stats grid - 2 columns
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: DesignSystem.Spacing.md) {
                // Total XP
                pixelStatCell(
                    icon: "star.fill",
                    title: "Total XP",
                    value: viewModel.totalXPText,
                    iconColor: tc.primary
                )

                // Current Level
                pixelStatCell(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Level",
                    value: "\(viewModel.currentLevel)",
                    iconColor: tc.primary
                )

                // Current Streak
                if let progress = viewModel.userProgress {
                    pixelStatCell(
                        icon: "flame.fill",
                        title: "Current Streak",
                        value: "\(progress.currentStreak) day\(progress.currentStreak == 1 ? "" : "s")",
                        iconColor: tc.macroBarCarbs
                    )

                    // Longest Streak
                    pixelStatCell(
                        icon: "flame.fill",
                        title: "Longest Streak",
                        value: "\(progress.longestStreak) day\(progress.longestStreak == 1 ? "" : "s")",
                        iconColor: tc.macroBarFat
                    )
                }
            }
        }
    }

    /// Pixel-styled stat cell for the stats grid
    private func pixelStatCell(
        icon: String,
        title: String,
        value: String,
        iconColor: Color
    ) -> some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: icon)
                .font(AppFont.bold(20))
                .foregroundColor(iconColor)

            Text(value)
                .font(AppFont.bold(20))
                .foregroundColor(tc.textPrimary)

            Text(title)
                .font(AppFont.regular(12))
                .foregroundColor(tc.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(DesignSystem.Spacing.md)
        .adaptiveCard(borderColor: iconColor.opacity(0.6), fillColor: tc.cardBackground)
    }

    // MARK: - XP Progress Section

    private var xpProgressSection: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            HStack {
                Text("\(viewModel.xpWithinLevel) XP")
                Spacer()
                Text("Level \(viewModel.nextLevel)")
                Spacer()
                Text("\(viewModel.xpToNextLevel) to next")
            }
            .font(AppFont.regular(12))
            .foregroundColor(tc.textSecondary)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    AdaptivePillShapeStyle()
                        .fill(tc.primary.opacity(0.3))
                    AdaptivePillShapeStyle()
                        .fill(DesignSystem.Colors.adaptiveGradient(light: tc.buttonLight, mid: tc.buttonMid, dark: tc.buttonDark))
                        .frame(width: max(0, geo.size.width * viewModel.levelProgress))
                }
            }
            .frame(height: 8)
        }
        .padding(.horizontal, DesignSystem.Spacing.xs)
    }

    // MARK: - Badges Section

    private var badgesSection: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            Text("Badges")
                .font(AppFont.bold(22))
                .foregroundColor(tc.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: DesignSystem.Spacing.md) {
                ForEach(BadgeDefinition.all) { badge in
                    let progress = viewModel.badgeProgressList.first { $0.badgeId == badge.id }
                    let earned = progress?.isUnlocked == true

                    Button {
                        selectedBadge = badge
                    } label: {
                        VStack(spacing: DesignSystem.Spacing.xs) {
                            Text(earned ? badge.emoji : "🔒")
                                .font(AppFont.regular(34))
                                .opacity(earned ? 1.0 : 0.35)
                            Text(badge.title)
                                .font(AppFont.regular(11))
                                .foregroundColor(earned ? tc.textPrimary : tc.textTertiary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(DesignSystem.Spacing.sm)
                        .adaptiveCard(
                            borderColor: earned ? tc.primaryDark : tc.primary.opacity(0.3),
                            fillColor: tc.cardBackground
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }

    // MARK: - Settings Section

    private var settingsSection: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            Text("Settings")
                .font(AppFont.bold(22))
                .foregroundColor(tc.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

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
        }
    }

    /// Reusable settings button component
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

// MARK: - BadgeDetailSheet

/// Sheet shown when tapping a badge in the badge grid.
struct BadgeDetailSheet: View {

    let definition: BadgeDefinition
    let progress: BadgeProgress?

    @Environment(\.dismiss) private var dismiss

    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }

    var body: some View {
        NavigationStack {
            ZStack {
                tc.primaryBackground.ignoresSafeArea()

                VStack(spacing: DesignSystem.Spacing.lg) {
                    Text(definition.emoji)
                        .font(AppFont.regular(80))
                        .padding(.top, DesignSystem.Spacing.lg)

                    VStack(spacing: DesignSystem.Spacing.sm) {
                        Text(definition.title)
                            .font(AppFont.bold(22))
                            .foregroundColor(tc.textPrimary)

                        Text(definition.description)
                            .font(AppFont.regular(16))
                            .foregroundColor(tc.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, DesignSystem.Spacing.xl)
                    }

                    if let progress = progress, progress.isUnlocked, let date = progress.unlockedAt {
                        HStack(spacing: DesignSystem.Spacing.xs) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(tc.primary)
                            Text("Unlocked \(date.formatted(date: .abbreviated, time: .omitted))")
                                .font(AppFont.regular(14))
                                .foregroundColor(tc.textSecondary)
                        }
                    } else {
                        HStack(spacing: DesignSystem.Spacing.xs) {
                            Image(systemName: "lock.fill")
                                .foregroundColor(tc.textTertiary)
                            Text("Not yet unlocked")
                                .font(AppFont.regular(14))
                                .foregroundColor(tc.textTertiary)
                        }
                    }

                    Spacer()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Badge")
                        .font(AppFont.bold(20))
                        .foregroundColor(tc.textPrimary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Profile View") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: FoodEntry.self, DailyGoal.self, UserProgress.self, DailyQuest.self, configurations: config)
    let context = container.mainContext

    // Add sample progress data
    let sampleProgress = UserProgress(
        totalXP: 1250,
        currentStreak: 7,
        longestStreak: 12,
        lastActiveDate: Date(),
        rank: Rank.silver.rawValue
    )

    let sampleGoal = DailyGoal(
        date: Date(),
        calorieTarget: 2000,
        proteinTarget: 150.0,
        carbTarget: 200.0,
        fatTarget: 65.0,
        purityTarget: 30
    )

    context.insert(sampleProgress)
    context.insert(sampleGoal)

    let coordinator = AppCoordinator(modelContext: context)

    return ProfileView(coordinator: coordinator, authService: LocalAuthService.shared, onLogout: {})
}
