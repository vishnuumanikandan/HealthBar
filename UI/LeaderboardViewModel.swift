//
//  LeaderboardViewModel.swift
//  HealthBar
//
//  Created by Claude on 6/10/26.
//

import Foundation

/// ViewModel for LeaderboardView (Friend System Phase 3).
///
/// Holds the ranked entries IN MEMORY only — friends' published stats are
/// fetched through the coordinator on appear and on pull-to-refresh, and are
/// never persisted to SwiftData. No listeners are opened; staleness between
/// refreshes is acceptable for a friends leaderboard.
@Observable
@MainActor
final class LeaderboardViewModel {

    // MARK: - Dependencies

    private let coordinator: AppCoordinator

    // MARK: - State

    /// Ranked rows: current user + every friend, deduped by uid and sorted by
    /// weekly adherence (no-data friends pinned last).
    var entries: [LeaderboardEntry] = []
    var isLoading: Bool = false
    var loadError: String? = nil

    /// True once any refresh has completed — gates the first-load spinner.
    private(set) var hasLoaded: Bool = false

    /// True when at least one friend row is present (the current user's own
    /// row always exists for non-guests).
    var hasFriendRows: Bool { entries.contains { !$0.isCurrentUser } }

    // MARK: - Init

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    // MARK: - Loading

    /// Fetches every friend's published projection and re-ranks client-side.
    /// Called from .task on appear and from pull-to-refresh.
    func refresh() async {
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }

        let result = await coordinator.loadLeaderboard()
        if result.isEmpty {
            // Non-guests always get at least their own row — an empty result
            // means the load couldn't run. Keep any previously shown entries.
            loadError = "Couldn't load the leaderboard. Pull down to retry."
        } else {
            entries = result
            loadError = nil
        }
    }
}
