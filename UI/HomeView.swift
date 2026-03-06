//
//  HomeView.swift
//  HealthBar
//
//  Created by Claude on 1/19/26.
//  Updated on 1/22/26 - Now uses DesignSystem components
//

import SwiftUI
import SwiftData

/// Main dashboard view showing today's summary
///
/// Features:
/// - XP progress and current rank display
/// - Current streak tracker
/// - Nutrition progress (calories, protein, carbs, fat)
/// - Daily quests list
/// - Today's meal entries
/// - Quick action button to navigate to Food Log
/// - Pull-to-refresh
struct HomeView: View {

    // MARK: - Properties

    /// The view model (holds all UI state and logic)
    @State private var viewModel: HomeViewModel

    /// Binding to the selected tab for programmatic navigation
    @Binding var selectedTab: Int

    /// Show purity score info sheet
    @State private var showingPurityScoreInfo: Bool = false

    /// Settings manager for advanced nutrition toggle
    @State private var settings = SettingsManager.shared

    /// Show mood check modal
    @State private var showMoodCheck: Bool = false

    /// Scene phase for detecting app active/background state
    @Environment(\.scenePhase) private var scenePhase

    /// AppStorage key for insights card dismissal (resets daily)
    @AppStorage("insightsCardDismissedDate") private var insightsCardDismissedDate: String = ""

    // MARK: - Initialization

    init(coordinator: AppCoordinator, selectedTab: Binding<Int>) {
        self._viewModel = State(initialValue: HomeViewModel(coordinator: coordinator))
        self._selectedTab = selectedTab
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

                // Check for streak milestones after data loads
                await viewModel.checkForStreakMilestone()

                // Load daily insights
                await viewModel.loadDailyInsights()
            }
            .overlay {
                // XP Toast overlay (positioned in upper half, never overlaps undo toast)
                if viewModel.showXPToast {
                    VStack {
                        XPToastContainer(
                            totalXP: viewModel.xpToastAmount,
                            questCount: viewModel.xpToastQuestCount,
                            isShowing: $viewModel.showXPToast
                        )
                        Spacer()
                    }
                }

                // Quest rollback toast (positioned in upper half)
                if viewModel.showQuestRollbackToast, let message = viewModel.questRollbackMessage {
                    VStack {
                        QuestRollbackToast(questTitle: message)
                            .padding(.top, 80)
                        Spacer()
                    }
                    .allowsHitTesting(false)
                }

                // Streak milestone celebration toast (centered, full screen overlay)
                if viewModel.showMilestoneToast, let milestone = viewModel.pendingMilestone {
                    StreakMilestoneToastContainer(
                        milestone: milestone,
                        isShowing: $viewModel.showMilestoneToast
                    )
                }

                // Daily mood check modal
                if showMoodCheck {
                    MoodCheckContainer(
                        isPresented: $showMoodCheck,
                        onMoodSelected: { mood in
                            Task {
                                try? await viewModel.coordinator.logMood(mood)
                            }
                        }
                    )
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    checkForMoodPrompt()
                    // Refresh data when app becomes active (user may have logged food in another tab)
                    Task {
                        await viewModel.loadData()
                        await viewModel.refreshWeeklyIfNeeded()
                        await viewModel.loadDailyInsights()
                    }
                }
            }
            .onChange(of: selectedTab) { _, newTab in
                // Refresh data when returning to home tab
                if newTab == 0 {
                    Task {
                        await viewModel.loadData()
                        await viewModel.refreshWeeklyIfNeeded()
                        await viewModel.loadDailyInsights()
                    }
                }
            }
        }
    }

    // MARK: - Daily Insights Card Logic

    /// Whether the insights card is dismissed for today
    private var isInsightsCardDismissedToday: Bool {
        let todayString = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
        return insightsCardDismissedDate == todayString
    }

    /// Dismisses the insights card for today
    private func dismissInsightsCard() {
        let todayString = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
        insightsCardDismissedDate = todayString
    }

    // MARK: - Mood Check Logic

    /// Checks if we should show the mood check prompt
    private func checkForMoodPrompt() {
        // Only show if enabled in settings
        guard settings.dailyMoodCheckEnabled else { return }

        // Only show after 7pm
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: Date())
        guard hour >= 19 else { return }

        // Check if mood already logged today
        Task {
            let alreadyLogged = try? await viewModel.coordinator.checkIfMoodLoggedToday()
            if alreadyLogged == false {
                await MainActor.run {
                    showMoodCheck = true
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

                // Today/Week Segmented Control
                viewModeSelector

                // Show Today or Week view based on selection
                if viewModel.selectedViewMode == .today {
                    todayContent
                } else {
                    weeklyContent
                }
            }
            .padding(DesignSystem.Spacing.lg)
        }
    }

    // MARK: - View Mode Selector

    private var viewModeSelector: some View {
        Picker("View Mode", selection: $viewModel.selectedViewMode) {
            ForEach(HomeViewMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: viewModel.selectedViewMode) { _, newValue in
            if newValue == .week {
                // Always refresh when switching to week view to get latest data and goals
                Task {
                    await viewModel.loadWeeklySummary()
                }
            }
        }
    }

    // MARK: - Today Content

    private var todayContent: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            // Nutrition Progress Section
            nutritionProgressSection

            // Quick Action Button
            quickActionButton

            // Daily Quests Section
            questsSection

            // Daily Insights Card (below quests, dismissible)
            if let insights = viewModel.dailyInsights, !isInsightsCardDismissedToday {
                DailyInsightsCard(
                    insights: insights,
                    onDismiss: {
                        dismissInsightsCard()
                    }
                )
            }

            // Today's Meals Section
            if let entries = viewModel.summary?.entries, !entries.isEmpty {
                mealsSection(entries: entries)
            }
        }
    }

    // MARK: - Weekly Content

    private var weeklyContent: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            if viewModel.isLoadingWeekly {
                VStack(spacing: DesignSystem.Spacing.md) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Loading weekly data...")
                        .font(.system(size: DesignSystem.FontSizes.callout, weight: .regular))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                .frame(minHeight: 300)
            } else if let weeklySummary = viewModel.weeklySummary {
                WeeklySummaryView(summary: weeklySummary)
            } else {
                EmptyStateView(
                    icon: "calendar",
                    title: "No Weekly Data",
                    message: "Log some meals to see your weekly summary!"
                )
                .frame(minHeight: 300)
            }
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
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                .strokeBorder(DesignSystem.Colors.primary.opacity(0.25), lineWidth: 1.5)
        )
        .shadow(
            color: DesignSystem.Shadows.card.color,
            radius: DesignSystem.Shadows.card.radius,
            x: DesignSystem.Shadows.card.x,
            y: DesignSystem.Shadows.card.y
        )
    }

    // MARK: - Quick Action Buttons

    /// Quick action buttons to log food or scan barcode
    private var quickActionButton: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            // Log Food button (takes 60% width)
            AppButton(
                title: "Log Food",
                style: .primary,
                action: {
                    selectedTab = 1 // Switch to Food Log tab
                },
                icon: "plus.circle.fill"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Quick Scan button (takes 40% width)
            Button {
                viewModel.showQuickScan = true
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "barcode.viewfinder")
                        .font(.system(size: 20, weight: .semibold))

                    Text("Scan")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(DesignSystem.Colors.secondary)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
            }
            .frame(width: 80)
        }
        .sheet(isPresented: $viewModel.showQuickScan) {
            QuickScanView(viewModel: viewModel, selectedTab: $selectedTab)
        }
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
                        HStack(spacing: DesignSystem.Spacing.xs) {
                            Text("Purity Score")
                                .font(.system(size: DesignSystem.FontSizes.footnote, weight: .medium))
                                .foregroundColor(DesignSystem.Colors.textSecondary)

                            // Info button (44x44pt touch target)
                            Button {
                                showingPurityScoreInfo = true
                            } label: {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(DesignSystem.Colors.textTertiary)
                            }
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                        }

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
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                        .strokeBorder(DesignSystem.Colors.primary.opacity(0.25), lineWidth: 1.5)
                )
                .shadow(
                    color: DesignSystem.Shadows.card.color,
                    radius: DesignSystem.Shadows.card.radius / 2,
                    x: DesignSystem.Shadows.card.x,
                    y: DesignSystem.Shadows.card.y
                )
                .sheet(isPresented: $showingPurityScoreInfo) {
                    PurityScoreInfoSheet()
                }
            }

            // Advanced Nutrients Grid (only when toggle is enabled)
            if settings.trackAdvancedNutrition, let summary = viewModel.summary {
                AdvancedNutrientsGrid(entries: summary.entries, goal: summary.goal)
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

            // Show all quests complete view if all done
            if viewModel.allQuestsComplete {
                AllQuestsCompleteView(totalXPFromQuests: viewModel.totalQuestXPEarnedToday)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else if let quests = viewModel.summary?.quests, !quests.isEmpty {
                VStack(spacing: DesignSystem.Spacing.sm) {
                    ForEach(quests, id: \.id) { quest in
                        questRow(quest)
                            .transition(.asymmetric(
                                insertion: .scale.combined(with: .opacity),
                                removal: .opacity
                            ))
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
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.allQuestsComplete)
    }

    /// Quest row view with animated checkmark
    private func questRow(_ quest: DailyQuest) -> some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            // Completion icon with spring animation
            ZStack {
                Circle()
                    .fill(quest.isCompleted ? DesignSystem.Colors.primary.opacity(0.15) : DesignSystem.Colors.border)
                    .frame(width: DesignSystem.Sizes.iconCircle, height: DesignSystem.Sizes.iconCircle)

                Image(systemName: quest.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(quest.isCompleted ? DesignSystem.Colors.primary : DesignSystem.Colors.textTertiary)
                    .scaleEffect(quest.isCompleted ? 1.0 : 0.9)
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: quest.isCompleted)

            // Quest info
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text(quest.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .strikethrough(quest.isCompleted, color: DesignSystem.Colors.textTertiary)

                Text(quest.questDescription)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            .animation(.easeInOut(duration: 0.2), value: quest.isCompleted)

            Spacer()

            // XP reward badge
            XPBadge(xp: quest.xpReward, useGradient: quest.isCompleted, size: .small)
                .scaleEffect(quest.isCompleted ? 1.05 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: quest.isCompleted)
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                .strokeBorder(
                    quest.isCompleted ? DesignSystem.Colors.primary.opacity(0.5) : DesignSystem.Colors.primary.opacity(0.25),
                    lineWidth: 1.5
                )
        )
        .shadow(
            color: quest.isCompleted ? DesignSystem.Colors.primary.opacity(0.15) : DesignSystem.Shadows.card.color,
            radius: DesignSystem.Shadows.card.radius / 2,
            x: DesignSystem.Shadows.card.x,
            y: DesignSystem.Shadows.card.y
        )
        .animation(.easeInOut(duration: 0.3), value: quest.isCompleted)
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
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                .strokeBorder(DesignSystem.Colors.primary.opacity(0.25), lineWidth: 1.5)
        )
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
        } else if Double(score) <= Double(target) * 1.5 {
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

    return HomeView(coordinator: coordinator, selectedTab: .constant(0))
}

// MARK: - Quick Scan View

/// Quick scan view for fast barcode scanning from home screen
struct QuickScanView: View {

    @Bindable var viewModel: HomeViewModel
    @Binding var selectedTab: Int
    @Environment(\.dismiss) private var dismiss

    @State private var showManualEntry = false
    @State private var showScanner = false
    @State private var manualBarcodeInput = ""
    @State private var isLoadingBarcode = false
    @State private var barcodeError: String?
    @State private var scannedNutrition: FoodNutrition?
    @State private var showAddFoodForm = false

    var body: some View {
        NavigationStack {
            VStack(spacing: DesignSystem.Spacing.xl) {
                // Icon
                ZStack {
                    Circle()
                        .fill(DesignSystem.Colors.secondary.opacity(0.15))
                        .frame(width: 100, height: 100)

                    Image(systemName: "barcode.viewfinder")
                        .font(.system(size: 50, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.secondary)
                }
                .padding(.top, DesignSystem.Spacing.xxl)

                // Title and description
                VStack(spacing: DesignSystem.Spacing.sm) {
                    Text("Quick Scan")
                        .font(.system(size: DesignSystem.FontSizes.title, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textPrimary)

                    Text("Scan a barcode or enter manually to quickly log packaged foods")
                        .font(.system(size: DesignSystem.FontSizes.callout, weight: .regular))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DesignSystem.Spacing.xl)
                }

                Spacer()

                // Action buttons
                VStack(spacing: DesignSystem.Spacing.md) {
                    AppButton(
                        title: "Scan with Camera",
                        style: .primary,
                        action: {
                            showScanner = true
                        },
                        icon: "camera.fill"
                    )

                    AppButton(
                        title: "Enter Barcode Manually",
                        style: .secondary,
                        action: {
                            showManualEntry = true
                        },
                        icon: "keyboard"
                    )

                    Button {
                        dismiss()
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.xl)
                .padding(.bottom, DesignSystem.Spacing.xl)
            }
            .background(DesignSystem.Colors.primaryBackground)
            .navigationTitle("Quick Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .fullScreenCover(isPresented: $showScanner) {
                BarcodeScannerView { barcode in
                    // Dismiss quick scan and go to food log with barcode
                    dismiss()
                    selectedTab = 1
                    // Note: The barcode will need to be passed to FoodLogView
                    // This is a simplified version - you may need to add coordinator method
                }
            }
            .sheet(isPresented: $showManualEntry) {
                QuickScanManualEntryView(
                    manualBarcodeInput: $manualBarcodeInput,
                    isLoadingBarcode: $isLoadingBarcode,
                    barcodeError: $barcodeError,
                    onBarcodeSubmit: { barcode in
                        Task {
                            await handleBarcodeSubmit(barcode)
                        }
                    },
                    onDismiss: {
                        showManualEntry = false
                    }
                )
            }
            .sheet(isPresented: $showAddFoodForm) {
                if let nutrition = scannedNutrition {
                    QuickScanAddFoodView(
                        nutrition: nutrition,
                        barcode: manualBarcodeInput,
                        coordinator: viewModel.coordinator,
                        onComplete: {
                            // Reset state and dismiss
                            scannedNutrition = nil
                            manualBarcodeInput = ""
                            showAddFoodForm = false
                            dismiss()
                        },
                        onCancel: {
                            showAddFoodForm = false
                        }
                    )
                }
            }
        }
    }

    /// Handles barcode submission and fetches nutrition data
    private func handleBarcodeSubmit(_ barcode: String) async {
        isLoadingBarcode = true
        barcodeError = nil

        let barcodeService = BarcodeService()

        do {
            let nutrition = try await barcodeService.fetchNutrition(barcode: barcode)
            await MainActor.run {
                scannedNutrition = nutrition
                isLoadingBarcode = false
                showManualEntry = false
                showAddFoodForm = true
            }
        } catch let error as BarcodeError {
            await MainActor.run {
                barcodeError = error.localizedDescription
                isLoadingBarcode = false
            }
        } catch {
            await MainActor.run {
                barcodeError = "Failed to fetch product data. Please try again."
                isLoadingBarcode = false
            }
        }
    }
}

// MARK: - Quick Scan Manual Entry View

/// Sheet for manually entering barcode from Quick Scan
struct QuickScanManualEntryView: View {

    @Binding var manualBarcodeInput: String
    @Binding var isLoadingBarcode: Bool
    @Binding var barcodeError: String?
    let onBarcodeSubmit: (String) -> Void
    let onDismiss: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: DesignSystem.Spacing.xl) {
                // Icon
                ZStack {
                    Circle()
                        .fill(DesignSystem.Colors.secondary.opacity(0.15))
                        .frame(width: 80, height: 80)

                    Image(systemName: "keyboard")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.secondary)
                }
                .padding(.top, DesignSystem.Spacing.xl)

                // Instructions
                VStack(spacing: DesignSystem.Spacing.sm) {
                    Text("Enter Barcode Number")
                        .font(.system(size: DesignSystem.FontSizes.title2, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textPrimary)

                    Text("Enter the UPC or EAN barcode from the product packaging")
                        .font(.system(size: DesignSystem.FontSizes.callout, weight: .regular))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DesignSystem.Spacing.xl)
                }

                // Barcode input field
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    TextField("e.g., 737628064502", text: $manualBarcodeInput)
                        .font(.system(size: DesignSystem.FontSizes.body, weight: .regular))
                        .keyboardType(.numberPad)
                        .textFieldStyle(.plain)
                        .padding(DesignSystem.Spacing.md)
                        .background(DesignSystem.Colors.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                                .strokeBorder(DesignSystem.Colors.border, lineWidth: 1)
                        )
                        .focused($isFocused)

                    // Helper text
                    Text("Note: Nutrition shown is per 100g, not per serving")
                        .font(.system(size: DesignSystem.FontSizes.caption, weight: .regular))
                        .foregroundColor(DesignSystem.Colors.warning)
                        .padding(.top, DesignSystem.Spacing.sm)

                    // Error message
                    if let error = barcodeError {
                        HStack(spacing: DesignSystem.Spacing.xs) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(DesignSystem.Colors.danger)

                            Text(error)
                                .font(.system(size: DesignSystem.FontSizes.caption, weight: .regular))
                                .foregroundColor(DesignSystem.Colors.danger)
                        }
                        .padding(.top, DesignSystem.Spacing.xs)
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.xl)

                Spacer()

                // Action buttons
                VStack(spacing: DesignSystem.Spacing.md) {
                    AppButton(
                        title: "Look Up Nutrition",
                        style: .primary,
                        action: {
                            let barcode = manualBarcodeInput.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !barcode.isEmpty else { return }
                            onBarcodeSubmit(barcode)
                        },
                        isLoading: isLoadingBarcode,
                        isDisabled: manualBarcodeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoadingBarcode,
                        icon: "magnifyingglass"
                    )

                    Button {
                        onDismiss()
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.xl)
                .padding(.bottom, DesignSystem.Spacing.xl)
            }
            .background(DesignSystem.Colors.primaryBackground)
            .navigationTitle("Enter Barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDismiss()
                    }
                }
            }
            .onAppear {
                isFocused = true
            }
        }
    }
}

// MARK: - Quick Scan Add Food View

/// Simple food form after barcode lookup from Quick Scan
struct QuickScanAddFoodView: View {

    let nutrition: FoodNutrition
    let barcode: String
    let coordinator: AppCoordinator
    let onComplete: () -> Void
    let onCancel: () -> Void

    @State private var foodName: String = ""
    @State private var calories: String = ""
    @State private var protein: String = ""
    @State private var carbs: String = ""
    @State private var fat: String = ""
    @State private var toxinScore: Double = 30.0
    @State private var servingSize: String = "100"
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.lg) {
                    // Product info header
                    VStack(spacing: DesignSystem.Spacing.sm) {
                        ZStack {
                            Circle()
                                .fill(DesignSystem.Colors.primary.opacity(0.15))
                                .frame(width: 80, height: 80)

                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 40, weight: .medium))
                                .foregroundColor(DesignSystem.Colors.primary)
                        }

                        Text("Product Found!")
                            .font(.system(size: DesignSystem.FontSizes.title2, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textPrimary)

                        if let brand = nutrition.brand {
                            Text(brand)
                                .font(.system(size: DesignSystem.FontSizes.footnote, weight: .medium))
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        }
                    }
                    .padding(.bottom, DesignSystem.Spacing.md)

                    // Per 100g notice
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.warning)

                        Text("Values are per 100g - adjust serving size below")
                            .font(.system(size: DesignSystem.FontSizes.caption, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.warning)
                    }
                    .padding(DesignSystem.Spacing.md)
                    .background(DesignSystem.Colors.warning.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm))

                    // Serving size
                    servingSizeSection

                    // Food name
                    inputField(title: "Food Name", text: $foodName, placeholder: "Product name")

                    // Nutrition fields
                    nutritionInputs

                    // Toxin score
                    toxinScoreSection

                    // Error message
                    if let error = errorMessage {
                        Text(error)
                            .font(.system(size: DesignSystem.FontSizes.caption, weight: .regular))
                            .foregroundColor(DesignSystem.Colors.danger)
                    }

                    // Action buttons
                    VStack(spacing: DesignSystem.Spacing.md) {
                        AppButton(
                            title: "Add to Food Log",
                            style: .primary,
                            action: {
                                Task {
                                    await saveFood()
                                }
                            },
                            isLoading: isSubmitting,
                            isDisabled: isSubmitting,
                            icon: "checkmark.circle.fill"
                        )

                        Button {
                            onCancel()
                        } label: {
                            Text("Cancel")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        }
                    }
                    .padding(.top, DesignSystem.Spacing.md)
                }
                .padding(DesignSystem.Spacing.lg)
            }
            .background(DesignSystem.Colors.primaryBackground)
            .navigationTitle("Add Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
            }
            .onAppear {
                // Pre-fill with nutrition data
                foodName = nutrition.name
                calories = String(nutrition.calories)
                protein = String(format: "%.1f", nutrition.protein)
                carbs = String(format: "%.1f", nutrition.carbs)
                fat = String(format: "%.1f", nutrition.fat)
                toxinScore = Double(nutrition.toxinScore)
            }
        }
    }

    private var servingSizeSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Serving Size")
                .font(.system(size: DesignSystem.FontSizes.footnote, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.textSecondary)

            HStack(spacing: DesignSystem.Spacing.md) {
                TextField("100", text: $servingSize)
                    .font(.system(size: DesignSystem.FontSizes.body, weight: .medium))
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.plain)
                    .padding(DesignSystem.Spacing.md)
                    .background(DesignSystem.Colors.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                            .strokeBorder(DesignSystem.Colors.border, lineWidth: 1)
                    )
                    .frame(maxWidth: .infinity)

                Text("grams")
                    .font(.system(size: DesignSystem.FontSizes.callout, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textSecondary)

                Button {
                    applyServingSize()
                } label: {
                    Text("Apply")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, DesignSystem.Spacing.md)
                        .padding(.vertical, DesignSystem.Spacing.sm)
                        .background(DesignSystem.Colors.secondary)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm))
                }
            }
        }
    }

    private var nutritionInputs: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            Text("Nutrition Info")
                .font(.system(size: DesignSystem.FontSizes.headline, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            inputField(title: "Calories", text: $calories, placeholder: "0", unit: "cal", keyboardType: .numberPad)
            inputField(title: "Protein", text: $protein, placeholder: "0", unit: "g", keyboardType: .decimalPad)
            inputField(title: "Carbs", text: $carbs, placeholder: "0", unit: "g", keyboardType: .decimalPad)
            inputField(title: "Fat", text: $fat, placeholder: "0", unit: "g", keyboardType: .decimalPad)
        }
    }

    private func inputField(
        title: String,
        text: Binding<String>,
        placeholder: String,
        unit: String? = nil,
        keyboardType: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text(title)
                .font(.system(size: DesignSystem.FontSizes.footnote, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.textSecondary)

            HStack {
                TextField(placeholder, text: text)
                    .font(.system(size: DesignSystem.FontSizes.body, weight: .regular))
                    .keyboardType(keyboardType)
                    .textFieldStyle(.plain)

                if let unit = unit {
                    Text(unit)
                        .font(.system(size: DesignSystem.FontSizes.footnote, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
            }
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                    .strokeBorder(DesignSystem.Colors.border, lineWidth: 1)
            )
        }
    }

    private var toxinScoreSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack {
                Text("Toxin Score")
                    .font(.system(size: DesignSystem.FontSizes.headline, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Spacer()

                Text("\(Int(toxinScore))")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(toxinScoreColor)
            }

            Slider(value: $toxinScore, in: 0...100, step: 1)
                .tint(toxinScoreColor)

            HStack {
                Text("Clean")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(DesignSystem.Colors.primary)

                Spacer()

                Text("Processed")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(DesignSystem.Colors.danger)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
    }

    private var toxinScoreColor: Color {
        if toxinScore < 30 {
            return DesignSystem.Colors.primary
        } else if toxinScore < 60 {
            return DesignSystem.Colors.warning
        } else {
            return DesignSystem.Colors.danger
        }
    }

    private func applyServingSize() {
        guard let grams = Double(servingSize), grams > 0 else { return }

        let multiplier = grams / 100.0

        // Recalculate from original nutrition values
        calories = String(Int(Double(nutrition.calories) * multiplier))
        protein = String(format: "%.1f", nutrition.protein * multiplier)
        carbs = String(format: "%.1f", nutrition.carbs * multiplier)
        fat = String(format: "%.1f", nutrition.fat * multiplier)
    }

    private func saveFood() async {
        guard !foodName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Food name is required"
            return
        }

        guard let caloriesInt = Int(calories) else {
            errorMessage = "Invalid calorie value"
            return
        }

        isSubmitting = true
        errorMessage = nil

        do {
            _ = try await coordinator.addFoodEntry(
                name: foodName.trimmingCharacters(in: .whitespacesAndNewlines),
                calories: caloriesInt,
                protein: Double(protein) ?? 0.0,
                carbs: Double(carbs) ?? 0.0,
                fat: Double(fat) ?? 0.0,
                toxinScore: Int(toxinScore),
                photoData: nil,
                barcodeUPC: barcode
            )

            // Success haptic
            #if os(iOS)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            #endif

            isSubmitting = false
            onComplete()

        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
            isSubmitting = false
        }
    }
}

