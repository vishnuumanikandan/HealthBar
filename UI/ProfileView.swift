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
/// - Settings section with placeholder buttons
struct ProfileView: View {

    // MARK: - Properties

    /// The view model managing this view's state
    @State private var viewModel: ProfileViewModel

    // MARK: - Initialization

    init(coordinator: AppCoordinator) {
        self.viewModel = ProfileViewModel(coordinator: coordinator)
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
                // Avatar and name section
                avatarSection

                // Stats grid
                statsSection

                // Settings section
                settingsSection
            }
            .padding(DesignSystem.Spacing.lg)
        }
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

            // User name placeholder
            Text("User")
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

    // MARK: - Settings Section

    private var settingsSection: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            Text("Settings")
                .font(.system(size: DesignSystem.FontSizes.title2, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: DesignSystem.Spacing.sm) {
                // Daily Goals button (placeholder)
                settingButton(
                    icon: "target",
                    title: "Daily Goals",
                    subtitle: "Customize your targets",
                    action: {
                        // Placeholder - will navigate to goal settings later
                    }
                )

                // Account button (placeholder)
                settingButton(
                    icon: "person.circle",
                    title: "Account",
                    subtitle: "Manage your profile",
                    action: {
                        // Placeholder - will navigate to account settings later
                    }
                )

                // About button (placeholder)
                settingButton(
                    icon: "info.circle",
                    title: "About",
                    subtitle: "App version and info",
                    action: {
                        // Placeholder - will navigate to about screen later
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
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: DesignSystem.Spacing.md) {
                // Icon
                ZStack {
                    Circle()
                        .fill(DesignSystem.Colors.primary.opacity(0.15))
                        .frame(width: DesignSystem.Sizes.iconCircle, height: DesignSystem.Sizes.iconCircle)

                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.primary)
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

    return ProfileView(coordinator: coordinator)
}
