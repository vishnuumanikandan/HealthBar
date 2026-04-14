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
                DesignSystem.Colors.primaryBackground
                    .ignoresSafeArea()

                if viewModel.isLoading {
                    loadingView
                } else if let error = viewModel.errorMessage {
                    errorView(error)
                } else {
                    contentView
                }
            }
            .navigationTitle("Profile")
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
                .font(.system(size: DesignSystem.FontSizes.callout, weight: .regular))
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
    }

    /// Error view
    private func errorView(_ message: String) -> some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 64, weight: .regular))
                .foregroundStyle(DesignSystem.Colors.danger)

            VStack(spacing: DesignSystem.Spacing.sm) {
                Text("Error Loading Profile")
                    .font(.system(size: DesignSystem.FontSizes.title2, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Text(message)
                    .font(.system(size: DesignSystem.FontSizes.callout, weight: .regular))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
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
                .font(.system(size: DesignSystem.FontSizes.caption, weight: .regular))
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            AppButton(
                title: "Create Account",
                style: .primary,
                action: { onCreateAccount() }
            )
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.primary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
    }

    // MARK: - Avatar Section

    private var avatarSection: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            // Avatar circle
            ZStack {
                Circle()
                    .fill(DesignSystem.Colors.primaryGradient)
                    .frame(width: 100, height: 100)

                Text(viewModel.userInitials)
                    .font(.system(size: 42, weight: .bold))
                    .foregroundColor(.white)
            }
            .shadow(
                color: DesignSystem.Shadows.accentGlow.color,
                radius: DesignSystem.Shadows.accentGlow.radius,
                x: DesignSystem.Shadows.accentGlow.x,
                y: DesignSystem.Shadows.accentGlow.y
            )

            Text(viewModel.displayName)
                .font(.system(size: DesignSystem.FontSizes.title2, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.textPrimary)

            // Rank badge
            HStack(spacing: DesignSystem.Spacing.xs) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.growth)

                Text(viewModel.currentRank.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.growth)
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .background(DesignSystem.Colors.growth.opacity(0.15))
            .clipShape(Capsule())
        }
        .padding(.vertical, DesignSystem.Spacing.md)
    }

    // MARK: - Stats Section

    private var statsSection: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            Text("Stats")
                .font(.system(size: DesignSystem.FontSizes.title2, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Stats grid - 2 columns
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: DesignSystem.Spacing.md) {
                // Total XP
                StatCard(
                    icon: "star.fill",
                    title: "Total XP",
                    value: viewModel.totalXPText,
                    iconColor: DesignSystem.Colors.primary
                )

                // Current Level
                StatCard(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Level",
                    value: "\(viewModel.currentLevel)",
                    iconColor: DesignSystem.Colors.secondary
                )

                // Current Streak
                if let progress = viewModel.userProgress {
                    StatCard(
                        icon: "flame.fill",
                        title: "Current Streak",
                        value: "\(progress.currentStreak) day\(progress.currentStreak == 1 ? "" : "s")",
                        iconColor: DesignSystem.Colors.energy
                    )

                    // Longest Streak
                    StatCard(
                        icon: "flame.fill",
                        title: "Longest Streak",
                        value: "\(progress.longestStreak) day\(progress.longestStreak == 1 ? "" : "s")",
                        iconColor: DesignSystem.Colors.warning
                    )
                }
            }
        }
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
            .font(.system(size: DesignSystem.FontSizes.caption, weight: .regular))
            .foregroundColor(DesignSystem.Colors.textSecondary)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(DesignSystem.Colors.border)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(DesignSystem.Colors.primaryGradient)
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
                .font(.system(size: DesignSystem.FontSizes.title2, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.textPrimary)
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
                                .font(.system(size: 34))
                                .opacity(earned ? 1.0 : 0.35)
                            Text(badge.title)
                                .font(.system(size: DesignSystem.FontSizes.caption, weight: .medium))
                                .foregroundColor(earned ? DesignSystem.Colors.textPrimary : DesignSystem.Colors.textTertiary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(DesignSystem.Spacing.sm)
                        .background(DesignSystem.Colors.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
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
                .font(.system(size: DesignSystem.FontSizes.title2, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.textPrimary)
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
                    iconColor: DesignSystem.Colors.primary,
                    action: { showingOnboarding = true }
                )

                // Account button — hidden for guest users (requires a real account)
                if !authService.isGuest {
                    settingButton(
                        icon: "person.circle",
                        title: "Account",
                        subtitle: "Manage display name, password",
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
        iconColor: Color = DesignSystem.Colors.primary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: DesignSystem.Spacing.md) {
                // Icon
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.15))
                        .frame(width: DesignSystem.Sizes.iconCircle, height: DesignSystem.Sizes.iconCircle)

                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(iconColor)
                }

                // Text
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text(title)
                        .font(.system(size: DesignSystem.FontSizes.headline, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textPrimary)

                    Text(subtitle)
                        .font(.system(size: DesignSystem.FontSizes.caption, weight: .regular))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textTertiary)
            }
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
            .shadow(
                color: DesignSystem.Shadows.card.color,
                radius: DesignSystem.Shadows.card.radius / 2,
                x: DesignSystem.Shadows.card.x,
                y: DesignSystem.Shadows.card.y
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

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.primaryBackground.ignoresSafeArea()

                VStack(spacing: DesignSystem.Spacing.lg) {
                    Text(definition.emoji)
                        .font(.system(size: 80))
                        .padding(.top, DesignSystem.Spacing.lg)

                    VStack(spacing: DesignSystem.Spacing.sm) {
                        Text(definition.title)
                            .font(.system(size: DesignSystem.FontSizes.title2, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textPrimary)

                        Text(definition.description)
                            .font(.system(size: DesignSystem.FontSizes.callout, weight: .regular))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, DesignSystem.Spacing.xl)
                    }

                    if let progress = progress, progress.isUnlocked, let date = progress.unlockedAt {
                        HStack(spacing: DesignSystem.Spacing.xs) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(DesignSystem.Colors.primary)
                            Text("Unlocked \(date.formatted(date: .abbreviated, time: .omitted))")
                                .font(.system(size: DesignSystem.FontSizes.footnote, weight: .medium))
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        }
                    } else {
                        HStack(spacing: DesignSystem.Spacing.xs) {
                            Image(systemName: "lock.fill")
                                .foregroundColor(DesignSystem.Colors.textTertiary)
                            Text("Not yet unlocked")
                                .font(.system(size: DesignSystem.FontSizes.footnote, weight: .medium))
                                .foregroundColor(DesignSystem.Colors.textTertiary)
                        }
                    }

                    Spacer()
                }
            }
            .navigationTitle("Badge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
