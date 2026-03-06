//
//  ProfileViewModel.swift
//  HealthBar
//
//  Created by Claude on 1/23/26.
//

import Foundation
import SwiftUI

/// ViewModel for the Profile/Settings screen
///
/// Displays user stats (XP, level, rank, streaks) and profile settings.
/// Interacts with AppCoordinator for all business logic.
@Observable
final class ProfileViewModel {

    // MARK: - Properties

    /// The app coordinator (handles all business logic)
    private let coordinator: AppCoordinator

    // MARK: - UI State

    /// Current user progress data
    var userProgress: UserProgress?

    /// Current daily goal data
    var currentGoal: DailyGoal?

    /// Loading state for UI
    var isLoading = false

    /// Error message to display (nil if no error)
    var errorMessage: String?

    // MARK: - Computed Properties for UI

    /// Current level based on total XP
    var currentLevel: Int {
        guard let progress = userProgress else { return 1 }
        // XP formula: 100 XP per level
        return (progress.totalXP / 100) + 1
    }

    /// Current rank based on total XP
    var currentRank: Rank {
        guard let progress = userProgress else { return .iron }

        // Use Rank enum's getRank method for consistency
        return Rank.getRank(from: progress.totalXP)
    }

    /// Formatted total XP (e.g., "1,250 XP")
    var totalXPText: String {
        guard let progress = userProgress else { return "0 XP" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return "\(formatter.string(from: NSNumber(value: progress.totalXP)) ?? "0") XP"
    }

    /// User's initials for avatar placeholder
    var userInitials: String {
        // For now, return a default since we don't have user name
        // In Phase 2+, this would use actual user data
        return "U"
    }

    // MARK: - Initialization

    /// Initializes the ViewModel with an AppCoordinator
    /// - Parameter coordinator: The app coordinator for business logic
    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    // MARK: - Public Methods

    /// Loads user progress and goal data
    ///
    /// Call this when the view appears or needs to refresh.
    func loadUserData() async {
        isLoading = true
        errorMessage = nil

        do {
            userProgress = try await coordinator.getUserProgress()
            currentGoal = try await coordinator.getCurrentGoal()
        } catch {
            errorMessage = "Failed to load profile data: \(error.localizedDescription)"
        }

        isLoading = false
    }

    /// Refreshes the data (for pull-to-refresh)
    func refresh() async {
        await loadUserData()
    }
}
