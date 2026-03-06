//
//  HomeViewModel.swift
//  HealthBar
//
//  Created by Claude on 1/19/26.
//

import Foundation
import SwiftUI

/// ViewModel for the Home/Dashboard screen
///
/// Displays today's nutrition summary, XP progress, quests, and streaks.
/// Interacts with AppCoordinator for all business logic.
@Observable
final class HomeViewModel {

    // MARK: - Properties

    /// The app coordinator (handles all business logic)
    /// Exposed for use by Quick Scan flow
    let coordinator: AppCoordinator

    // MARK: - UI State

    /// Today's complete summary (nutrition + gamification data)
    var summary: TodaySummary?

    /// Loading state for UI
    var isLoading = false

    /// Error message to display (nil if no error)
    var errorMessage: String?

    /// Show quick scan sheet
    var showQuickScan: Bool = false

    // MARK: - Quest Animation State

    /// Whether to show XP toast
    var showXPToast: Bool = false

    /// Total XP to show in toast
    var xpToastAmount: Int = 0

    /// Number of quests that completed simultaneously
    var xpToastQuestCount: Int = 0

    /// Whether all quests are complete
    var allQuestsComplete: Bool = false

    /// Total XP earned from quests today
    var totalQuestXPEarnedToday: Int = 0

    /// Track previous quest completion state for animations
    private var previousQuestCompletionState: [UUID: Bool] = [:]

    /// Quest rollback message (shown when quest becomes incomplete)
    var questRollbackMessage: String?

    /// Whether to show quest rollback toast
    var showQuestRollbackToast: Bool = false

    // MARK: - Streak Milestone State

    /// Pending milestone to celebrate (set when milestone is reached)
    var pendingMilestone: StreakMilestone?

    /// Whether to show the milestone toast
    var showMilestoneToast: Bool = false

    // MARK: - Daily Insights State

    /// Daily insights data for the insights card
    var dailyInsights: DailyInsights?

    /// Whether the insights card is dismissed for today
    var insightsCardDismissedToday: Bool = false

    // MARK: - Weekly Summary State

    /// Selected view mode (Today or Week)
    var selectedViewMode: HomeViewMode = .today

    /// Weekly summary data
    var weeklySummary: WeeklySummary?

    /// Loading state for weekly summary
    var isLoadingWeekly: Bool = false

    // MARK: - Computed Properties for UI

    /// Formatted calorie progress string (e.g., "1500 / 2000")
    var calorieProgressText: String {
        guard let summary else { return "-- / --" }
        return "\(summary.totalCalories) / \(summary.goal.calorieTarget)"
    }

    /// Calorie progress percentage (0.0 to 1.0)
    var calorieProgressPercentage: Double {
        guard let summary, summary.goal.calorieTarget > 0 else { return 0.0 }
        return Double(summary.totalCalories) / Double(summary.goal.calorieTarget)
    }

    /// Formatted protein progress string (e.g., "120.5g / 150.0g")
    var proteinProgressText: String {
        guard let summary else { return "-- / --" }
        return String(format: "%.1fg / %.1fg", summary.totalProtein, summary.goal.proteinTarget)
    }

    /// Protein progress percentage (0.0 to 1.0)
    var proteinProgressPercentage: Double {
        guard let summary, summary.goal.proteinTarget > 0 else { return 0.0 }
        return summary.totalProtein / summary.goal.proteinTarget
    }

    /// Level progress text (e.g., "Level 5 • 234/500 XP")
    var levelProgressText: String {
        guard let summary else { return "Level --" }
        return "Level \(summary.currentLevel) • \(summary.xpForNextLevel) XP to next level"
    }

    /// Level progress percentage within current level
    var levelProgressPercentage: Double {
        guard let summary else { return 0.0 }
        let xpPerLevel = 100
        let xpInCurrentLevel = summary.totalXP % xpPerLevel
        return Double(xpInCurrentLevel) / Double(xpPerLevel)
    }

    /// Streak display text (e.g., "🔥 12 day streak")
    var streakText: String {
        guard let summary else { return "No streak" }
        let days = summary.currentStreak
        return "🔥 \(days) day\(days == 1 ? "" : "s") streak"
    }

    /// Number of completed quests today
    var completedQuestsCount: Int {
        summary?.quests.filter { $0.isCompleted }.count ?? 0
    }

    /// Total number of quests today
    var totalQuestsCount: Int {
        summary?.quests.count ?? 0
    }

    /// Quest progress text (e.g., "2/3 quests complete")
    var questProgressText: String {
        "\(completedQuestsCount)/\(totalQuestsCount) quests complete"
    }

    /// Formatted carbs progress string
    var carbsProgressText: String {
        guard let summary else { return "-- / --" }
        return String(format: "%.1fg / %.1fg", summary.totalCarbs, summary.goal.carbTarget)
    }

    /// Carbs progress percentage (0.0 to 1.0)
    var carbsProgressPercentage: Double {
        guard let summary, summary.goal.carbTarget > 0 else { return 0.0 }
        return summary.totalCarbs / summary.goal.carbTarget
    }

    /// Formatted fat progress string
    var fatProgressText: String {
        guard let summary else { return "-- / --" }
        return String(format: "%.1fg / %.1fg", summary.totalFat, summary.goal.fatTarget)
    }

    /// Fat progress percentage (0.0 to 1.0)
    var fatProgressPercentage: Double {
        guard let summary, summary.goal.fatTarget > 0 else { return 0.0 }
        return summary.totalFat / summary.goal.fatTarget
    }

    // MARK: - Initialization

    /// Initializes the ViewModel with an AppCoordinator
    /// - Parameter coordinator: The app coordinator for business logic
    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    // MARK: - Public Methods

    /// Loads today's summary data
    ///
    /// Call this when the view appears or needs to refresh.
    @MainActor
    func loadData() async {
        isLoading = true
        errorMessage = nil

        do {
            let oldQuests = summary?.quests
            summary = try await coordinator.getTodaysSummary()

            // Check for quest completion changes and trigger animations
            checkQuestCompletionChanges(oldQuests: oldQuests, newQuests: summary?.quests)

        } catch {
            errorMessage = "Failed to load data: \(error.localizedDescription)"
        }

        isLoading = false
    }

    /// Refreshes the data (for pull-to-refresh)
    func refresh() async {
        await loadData()

        // Also refresh weekly summary if we're viewing the week tab
        if selectedViewMode == .week {
            await loadWeeklySummary()
        }
    }

    /// Refreshes weekly data if currently viewing week mode
    /// Call this after adding/editing/deleting food entries
    @MainActor
    func refreshWeeklyIfNeeded() async {
        if selectedViewMode == .week || weeklySummary != nil {
            await loadWeeklySummary()
        }
    }

    /// Checks for quest completion changes and triggers animations
    @MainActor
    private func checkQuestCompletionChanges(oldQuests: [DailyQuest]?, newQuests: [DailyQuest]?) {
        guard let newQuests = newQuests else { return }

        var newlyCompletedQuests: [DailyQuest] = []
        var rolledBackQuests: [DailyQuest] = []

        for quest in newQuests {
            let wasCompleted = previousQuestCompletionState[quest.id] ?? false
            let isNowCompleted = quest.isCompleted

            if !wasCompleted && isNowCompleted {
                // Quest just completed
                newlyCompletedQuests.append(quest)
            } else if wasCompleted && !isNowCompleted {
                // Quest rolled back (user deleted/edited meal)
                rolledBackQuests.append(quest)
            }

            // Update tracking
            previousQuestCompletionState[quest.id] = quest.isCompleted
        }

        // Handle newly completed quests
        if !newlyCompletedQuests.isEmpty {
            triggerQuestCompletionAnimation(quests: newlyCompletedQuests)
        }

        // Handle rolled back quests
        if let firstRolledBack = rolledBackQuests.first {
            triggerQuestRollbackAnimation(quest: firstRolledBack)
        }

        // Check if all quests are complete
        let allComplete = newQuests.allSatisfy { $0.isCompleted }
        if allComplete && !allQuestsComplete {
            // Calculate total XP earned from quests
            totalQuestXPEarnedToday = newQuests.reduce(0) { $0 + $1.xpReward }
        }
        allQuestsComplete = allComplete && !newQuests.isEmpty
    }

    /// Triggers the XP toast animation for completed quests
    @MainActor
    private func triggerQuestCompletionAnimation(quests: [DailyQuest]) {
        // Calculate total XP from all newly completed quests
        let totalXP = quests.reduce(0) { $0 + $1.xpReward }

        // Set toast state
        xpToastAmount = totalXP
        xpToastQuestCount = quests.count

        // Haptic feedback
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif

        // Show toast
        showXPToast = true
    }

    /// Triggers the rollback animation when a quest becomes incomplete
    @MainActor
    private func triggerQuestRollbackAnimation(quest: DailyQuest) {
        questRollbackMessage = "\(quest.title) no longer met"
        showQuestRollbackToast = true

        // Auto-dismiss after 2 seconds
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                showQuestRollbackToast = false
                questRollbackMessage = nil
            }
        }
    }

    /// Dismisses the XP toast
    @MainActor
    func dismissXPToast() {
        showXPToast = false
        xpToastAmount = 0
        xpToastQuestCount = 0
    }

    /// Checks for streak milestones and shows celebration toast if one is reached
    @MainActor
    func checkForStreakMilestone() async {
        do {
            if let milestone = try await coordinator.checkForStreakMilestone() {
                pendingMilestone = milestone
                showMilestoneToast = true
            }
        } catch {
            // Silently fail - milestone check is non-critical
        }
    }

    /// Dismisses the milestone toast
    @MainActor
    func dismissMilestoneToast() {
        showMilestoneToast = false
        pendingMilestone = nil
    }

    /// Loads daily insights data
    @MainActor
    func loadDailyInsights() async {
        do {
            dailyInsights = try await coordinator.getDailyInsights()
        } catch {
            // Silently fail - insights are non-critical
            dailyInsights = nil
        }
    }

    /// Dismisses the insights card for today
    @MainActor
    func dismissInsightsCard() {
        insightsCardDismissedToday = true
    }

    /// Loads weekly summary data
    @MainActor
    func loadWeeklySummary() async {
        isLoadingWeekly = true

        do {
            weeklySummary = try await coordinator.getWeeklySummary()
        } catch {
            // Silently fail - weekly summary is non-critical
            weeklySummary = nil
        }

        isLoadingWeekly = false
    }

    /// Adds a test food entry (for testing purposes)
    func addTestFood() async {
        isLoading = true

        do {
            _ = try await coordinator.addFoodEntry(
                name: "Test Meal",
                calories: 500,
                protein: 30.0,
                carbs: 50.0,
                fat: 15.0,
                toxinScore: 5
            )

            // Reload data to see changes
            await loadData()

        } catch {
            errorMessage = "Failed to add food: \(error.localizedDescription)"
        }

        isLoading = false
    }
}

// MARK: - Home View Mode

/// View mode for the home screen
enum HomeViewMode: String, CaseIterable, Identifiable {
    case today = "Today"
    case week = "Week"

    var id: String { rawValue }
}
