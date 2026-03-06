//
//  HomeView.swift
//  HealthBar
//
//  Created by Claude on 1/19/26.
//  Updated on 1/22/26 - Now uses DesignSystem components
//

import SwiftUI

/// Main dashboard view showing today's summary
///
/// Features:
/// - XP progress and current rank display
/// - Current streak tracker
/// - Nutrition progress (calories, protein, carbs, fat)
/// - Daily quests list
/// - Today's meal entries
/// - Pull-to-refresh
struct HomeView: View {

    // MARK: - Properties

    /// The view model (holds all UI state and logic)
    @State private var viewModel: HomeViewModel

    // MARK: - Initialization

    init(coordinator: AppCoordinator) {
        self.viewModel = HomeViewModel(coordinator: coordinator)
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
            .navigationTitle("HealthBar")
            .refreshable {
                await viewModel.refresh()
            }
            .task {
                // Load data when view appears
                await viewModel.loadData()
            }
        }
    }

    // MARK: - Subviews

    /// Loading indicator
    private var loadingView: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading your progress...")
                .font(.system(size: DesignSystem.FontSizes.callout, weight: .regular))
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
    }

    /// Error view
    private func errorView(_ message: String) -> some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 64, weight: .regular)) // Keep large icon size as-is
                .foregroundStyle(DesignSystem.Colors.danger)

            VStack(spacing: DesignSystem.Spacing.sm) {
                Text("Error Loading Data")
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
                        await viewModel.loadData()
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
                // XP, Level, and Streak Section
                xpAndStreakSection

                // Nutrition Progress Section
                nutritionProgressSection

                // Daily Quests Section
                questsSection

                // Today's Meals Section
                if let entries = viewModel.summary?.entries, !entries.isEmpty {
                    mealsSection(entries: entries)
                }
            }
            .padding(DesignSystem.Spacing.lg)
        }
    }

    // MARK: - XP and Streak Section

    private var xpAndStreakSection: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            // Rank Badge
            if let summary = viewModel.summary {
                HStack {
                    ZStack {
                        Circle()
                            .fill(DesignSystem.Colors.growth.opacity(0.15))
                            .frame(width: DesignSystem.Sizes.rankBadge, height: DesignSystem.Sizes.rankBadge)

                        Image(systemName: "crown.fill")
                            .font(.system(size: DesignSystem.FontSizes.title3, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.growth)
                    }

                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                        Text(summary.currentRank.displayName)
                            .font(.system(size: DesignSystem.FontSizes.title3, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textPrimary)

                        Text("Level \(summary.currentLevel)")
                            .font(.system(size: DesignSystem.FontSizes.footnote, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }

                    Spacer()

                    // Streak badge
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.energy)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(summary.currentStreak)")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(DesignSystem.Colors.textPrimary)

                            Text("day\(summary.currentStreak == 1 ? "" : "s")")
                                .font(.system(size: DesignSystem.FontSizes.caption, weight: .regular))
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        }
                    }
                    .padding(DesignSystem.Spacing.md)
                    .background(DesignSystem.Colors.energy.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                }

                // XP Progress Bar
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    HStack {
                        Text("XP Progress")
                            .font(.system(size: DesignSystem.FontSizes.footnote, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textSecondary)

                        Spacer()

                        Text("\(summary.xpForNextLevel) XP to next level")
                            .font(.system(size: DesignSystem.FontSizes.caption, weight: .regular))
                            .foregroundColor(DesignSystem.Colors.textTertiary)
                    }

                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(DesignSystem.Colors.border)
                                .frame(height: 8)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(DesignSystem.Colors.primaryGradient)
                                .frame(width: geometry.size.width * viewModel.levelProgressPercentage, height: 8)
                                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: viewModel.levelProgressPercentage)
                        }
                    }
                    .frame(height: 8)
                }
            }
        }
        .padding(DesignSystem.Spacing.lg)
        .background(DesignSystem.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
        .shadow(
            color: DesignSystem.Shadows.card.color,
            radius: DesignSystem.Shadows.card.radius,
            x: DesignSystem.Shadows.card.x,
            y: DesignSystem.Shadows.card.y
        )
    }

    // MARK: - Nutrition Progress Section

    private var nutritionProgressSection: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            Text("Today's Nutrition")
                .font(.system(size: DesignSystem.FontSizes.title2, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Macro cards grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: DesignSystem.Spacing.md) {
                // Calories
                StatCard(
                    icon: "flame.fill",
                    title: "Calories",
                    value: viewModel.calorieProgressText,
                    iconColor: DesignSystem.Colors.energy,
                    progress: viewModel.calorieProgressPercentage,
                    progressColor: viewModel.calorieProgressPercentage > 1.0 ? DesignSystem.Colors.danger : DesignSystem.Colors.primary
                )

                // Protein
                StatCard(
                    icon: "leaf.fill",
                    title: "Protein",
                    value: viewModel.proteinProgressText,
                    iconColor: DesignSystem.Colors.primary,
                    progress: viewModel.proteinProgressPercentage,
                    progressColor: viewModel.proteinProgressPercentage >= 1.0 ? DesignSystem.Colors.primary : DesignSystem.Colors.warning
                )

                // Carbs (if we add carb tracking to HomeViewModel)
                if let summary = viewModel.summary {
                    StatCard(
                        icon: "flame.fill",
                        title: "Carbs",
                        value: "\(Int(summary.totalCarbs))g",
                        iconColor: DesignSystem.Colors.warning,
                        progress: summary.goal.carbTarget > 0 ? summary.totalCarbs / summary.goal.carbTarget : 0,
                        progressColor: DesignSystem.Colors.warning
                    )

                    // Fat
                    StatCard(
                        icon: "drop.fill",
                        title: "Fat",
                        value: "\(Int(summary.totalFat))g",
                        iconColor: DesignSystem.Colors.secondary,
                        progress: summary.goal.fatTarget > 0 ? summary.totalFat / summary.goal.fatTarget : 0,
                        progressColor: DesignSystem.Colors.secondary
                    )
                }
            }

            // Toxin Score
            if let summary = viewModel.summary {
                HStack(spacing: DesignSystem.Spacing.md) {
                    ZStack {
                        Circle()
                            .fill(toxinScoreColor(summary.totalToxinScore, target: summary.goal.purityTarget).opacity(0.15))
                            .frame(width: DesignSystem.Sizes.iconCircle, height: DesignSystem.Sizes.iconCircle)

                        Image(systemName: "leaf.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(toxinScoreColor(summary.totalToxinScore, target: summary.goal.purityTarget))
                    }

                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                        Text("Purity Score")
                            .font(.system(size: DesignSystem.FontSizes.footnote, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textSecondary)

                        Text("\(summary.totalToxinScore) / \(summary.goal.purityTarget)")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(toxinScoreColor(summary.totalToxinScore, target: summary.goal.purityTarget))
                    }

                    Spacer()

                    Text(summary.totalToxinScore <= summary.goal.purityTarget ? "Clean!" : "Over Limit")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(toxinScoreColor(summary.totalToxinScore, target: summary.goal.purityTarget))
                        .padding(.horizontal, DesignSystem.Spacing.md)
                        .padding(.vertical, DesignSystem.Spacing.sm)
                        .background(toxinScoreColor(summary.totalToxinScore, target: summary.goal.purityTarget).opacity(0.15))
                        .clipShape(Capsule())
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
        }
    }

    // MARK: - Quests Section

    private var questsSection: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            HStack {
                Text("Daily Quests")
                    .font(.system(size: DesignSystem.FontSizes.title2, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Spacer()

                Text(viewModel.questProgressText)
                    .font(.system(size: DesignSystem.FontSizes.footnote, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }

            if let quests = viewModel.summary?.quests, !quests.isEmpty {
                VStack(spacing: DesignSystem.Spacing.sm) {
                    ForEach(quests, id: \.id) { quest in
                        questRow(quest)
                    }
                }
            } else {
                EmptyStateView(
                    icon: "checkmark.circle",
                    title: "No Quests Today",
                    message: "Complete your nutrition goals to unlock daily quests!"
                )
                .frame(height: 200)
            }
        }
    }

    /// Quest row view
    private func questRow(_ quest: DailyQuest) -> some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            // Completion icon
            ZStack {
                Circle()
                    .fill(quest.isCompleted ? DesignSystem.Colors.primary.opacity(0.15) : DesignSystem.Colors.border)
                    .frame(width: DesignSystem.Sizes.iconCircle, height: DesignSystem.Sizes.iconCircle)

                Image(systemName: quest.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(quest.isCompleted ? DesignSystem.Colors.primary : DesignSystem.Colors.textTertiary)
            }

            // Quest info
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text(quest.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Text(quest.description)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }

            Spacer()

            // XP reward badge
            XPBadge(xp: quest.xpReward, useGradient: quest.isCompleted, size: .small)
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

    // MARK: - Meals Section

    private func mealsSection(entries: [FoodEntry]) -> some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            Text("Today's Meals")
                .font(.system(size: DesignSystem.FontSizes.title2, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: DesignSystem.Spacing.sm) {
                ForEach(entries, id: \.id) { entry in
                    mealRow(entry)
                }
            }
        }
    }

    /// Meal entry row view
    private func mealRow(_ entry: FoodEntry) -> some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            // Photo thumbnail or placeholder
            if let photoData = entry.photoData,
               let uiImage = UIImage(data: photoData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: DesignSystem.Sizes.thumbnail, height: DesignSystem.Sizes.thumbnail)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm)
                        .fill(DesignSystem.Colors.primary.opacity(0.1))
                        .frame(width: DesignSystem.Sizes.thumbnail, height: DesignSystem.Sizes.thumbnail)

                    Image(systemName: "fork.knife")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.primary)
                }
            }

            // Food info
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text(entry.name)
                    .font(.system(size: DesignSystem.FontSizes.headline, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Text("\(entry.calories) cal")
                    .font(.system(size: DesignSystem.FontSizes.footnote, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textSecondary)

                Text("P: \(Int(entry.protein))g • C: \(Int(entry.carbs))g • F: \(Int(entry.fat))g")
                    .font(.system(size: DesignSystem.FontSizes.caption, weight: .regular))
                    .foregroundColor(DesignSystem.Colors.textTertiary)
            }

            Spacer()

            // Time
            Text(timeString(from: entry.date))
                .font(.system(size: DesignSystem.FontSizes.caption, weight: .regular))
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

    // MARK: - Helpers

    /// Determines toxin score color based on value vs target
    private func toxinScoreColor(_ score: Int, target: Int) -> Color {
        if score <= target {
            return DesignSystem.Colors.primary
        } else if score <= target * 1.5 {
            return DesignSystem.Colors.warning
        } else {
            return DesignSystem.Colors.danger
        }
    }

    /// Formats a date into a time string
    private func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

// MARK: - Preview

#Preview("Home View - With Data") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: FoodEntry.self, DailyGoal.self, UserProgress.self, DailyQuest.self, configurations: config)
    let context = container.mainContext

    // Add sample data
    let sampleEntry = FoodEntry(
        name: "Grilled Chicken Salad",
        date: Date(),
        calories: 450,
        protein: 42.0,
        carbs: 25.0,
        fat: 18.0,
        toxinScore: 15
    )

    let sampleGoal = DailyGoal(
        date: Date(),
        calorieTarget: 2000,
        proteinTarget: 150.0,
        carbTarget: 200.0,
        fatTarget: 65.0,
        purityTarget: 30
    )

    let sampleProgress = UserProgress(
        totalXP: 350,
        currentStreak: 7,
        longestStreak: 12,
        lastActiveDate: Date(),
        rank: Rank.bronze.rawValue
    )

    context.insert(sampleEntry)
    context.insert(sampleGoal)
    context.insert(sampleProgress)

    let coordinator = AppCoordinator(modelContext: context)

    return HomeView(coordinator: coordinator)
}
