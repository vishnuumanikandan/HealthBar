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
    private let coordinator: AppCoordinator

    // MARK: - UI State

    /// Today's complete summary (nutrition + gamification data)
    var summary: TodaySummary?

    /// Loading state for UI
    var isLoading = false

    /// Error message to display (nil if no error)
    var errorMessage: String?

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
    func loadData() async {
        isLoading = true
        errorMessage = nil

        do {
            summary = try await coordinator.getTodaysSummary()
        } catch {
            errorMessage = "Failed to load data: \(error.localizedDescription)"
        }

        isLoading = false
    }

    /// Refreshes the data (for pull-to-refresh)
    func refresh() async {
        await loadData()
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
