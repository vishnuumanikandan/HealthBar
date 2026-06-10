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

    /// Auth service — read-only, used to suppress false errors for new accounts
    /// and to read guest state for display name fallback logic.
    private var authService: any AuthService

    // MARK: - UI State

    /// Current user progress data
    var userProgress: UserProgress?

    /// Current daily goal data
    var currentGoal: DailyGoal?

    /// The user's completed health profile (nil if not yet set up or not found).
    var existingProfile: UserProfile?

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

    /// Display name with fallback chain: UserProfile.displayName → Firebase Auth → "User"
    var displayName: String {
        if let name = existingProfile?.displayName, !name.isEmpty { return name }
        if let name = FirebaseAuthService.shared.currentUserDisplayName, !name.isEmpty { return name }
        return "User"
    }

    /// First character of displayName (uppercased), fallback "U"
    var userInitials: String {
        String(displayName.prefix(1)).uppercased()
    }

    // MARK: - XP Progress

    /// XP earned within the current level (0–99)
    var xpWithinLevel: Int {
        userProgress.map { $0.totalXP % 100 } ?? 0
    }

    /// XP remaining to reach the next level
    var xpToNextLevel: Int {
        userProgress.map { 100 - ($0.totalXP % 100) } ?? 100
    }

    /// Progress ratio within the current level (0.0–1.0)
    var levelProgress: Double {
        userProgress.map { Double($0.totalXP % 100) / 100.0 } ?? 0
    }

    /// Next level number
    var nextLevel: Int { currentLevel + 1 }

    // MARK: - Badge Progress

    /// All badge progress records for the current user.
    var badgeProgressList: [BadgeProgress] = []

    /// The user's unique @handle (nil if not yet claimed or guest).
    var username: String? = nil

    // MARK: - Initialization

    /// Initializes the ViewModel with an AppCoordinator and auth service.
    /// - Parameters:
    ///   - coordinator: The app coordinator for business logic.
    ///   - authService: Used to read isNewUser (suppresses false errors on brand-new accounts)
    ///                  and isGuest (for display name fallback).
    init(coordinator: AppCoordinator, authService: any AuthService) {
        self.coordinator = coordinator
        self.authService = authService
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
            existingProfile = try await coordinator.getUserProfile()
            badgeProgressList = (try? await coordinator.getAllBadgeProgress()) ?? []
            username = await coordinator.currentUsername()
            // First successful load for a new account — clear the new-user flag.
            if authService.isNewUser {
                authService.isNewUser = false
            }
        } catch {
            if authService.isNewUser {
                // Brand-new account: no data exists yet. Suppress the error and show
                // a clean empty state. This prevents false "unable to load" messages
                // immediately after account creation.
                errorMessage = nil
                authService.isNewUser = false
            } else {
                errorMessage = "Failed to load profile data: \(error.localizedDescription)"
            }
        }

        isLoading = false
    }

    /// Refreshes the data (for pull-to-refresh)
    func refresh() async {
        await loadUserData()
    }
}
