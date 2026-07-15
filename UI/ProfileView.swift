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

    /// R7b §2: presents the pushed SettingsView. The settings section moved off Profile behind
    /// the toolbar gear; all the individual sheet/cover state moved into SettingsView with it.
    @State private var showingSettings = false

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
            // R7c §4: the "Profile" title is gone (the in-content head is the header), but the gear
            // remains — so this root keeps its nav bar rather than hiding it.
            .toolbar {
                // R7b §2: the gear opens the pushed SettingsView (the settings section moved
                // off Profile). Icon-only, so it carries an explicit accessibility label.
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(AppFont.regular(17))
                            .foregroundColor(tc.textPrimary)
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .refreshable {
                await viewModel.refresh()
            }
            .task {
                // Load data when view appears
                await viewModel.loadUserData()
            }
            .sheet(item: $selectedBadge) { badge in
                BadgeDetailSheet(
                    definition: badge,
                    progress: viewModel.badgeProgressList.first { $0.badgeId == badge.id }
                )
            }
            // R7b §2: settings are a pushed screen now (FriendsView push precedent), inside
            // Profile's existing NavigationStack.
            .navigationDestination(isPresented: $showingSettings) {
                SettingsView(
                    coordinator: coordinator,
                    authService: authService,
                    onLogout: onLogout,
                    existingProfile: viewModel.existingProfile
                )
            }
            // R7b §2: one on-return reload replaces the per-sheet reloads that moved into
            // SettingsView — Daily Goals / Health Profile edits show once Profile reappears.
            .onChange(of: showingSettings) { _, showing in
                if !showing {
                    Task { await viewModel.loadUserData() }
                }
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
            }
            .padding(DesignSystem.Spacing.lg)
        }
        // R2 §5 conditional: the tab bar is mounted as a `.safeAreaInset` on the TabView,
        // but that inset does not propagate through this tab's NavigationStack to the
        // ScrollView. Reserve the bar's height as scroll-content margin so the bottom
        // Settings rows (About / Sign Out) clear the bar and stay tappable in both
        // families (fixes the Finding-#1 tap-target bug).
        .contentMargins(.bottom, DesignSystem.Erewhon.tabBarContentHeight + 12, for: .scrollContent)
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

                Text(viewModel.currentRankDisplay)
                    .font(AppFont.regular(14))
                    .foregroundColor(tc.textSecondary)
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .adaptivePill(borderColor: tc.primary, fillColor: tc.primary.opacity(0.15), isSelected: true)  // R6c: preserved implicit-selection (review intent later)
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
                            BadgeEmblem(badge, size: 34, isLocked: !earned)
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
                    BadgeEmblem(definition, size: 80, isLocked: !(progress?.isUnlocked ?? false))
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
        lastActiveDate: Date()
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
