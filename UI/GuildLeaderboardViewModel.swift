//
//  GuildLeaderboardViewModel.swift
//  HealthBar
//
//  Created by Claude on 6/18/26.
//

import Foundation

/// The metric the guild leaderboard ranks by. All three live in the fetched
/// `public/stats` projection, so switching metric re-sorts in memory — never refetches.
enum GuildMetric: String, CaseIterable, Identifiable {
    case adherence = "Adherence"
    case xp = "XP"
    case level = "Level"

    var id: String { rawValue }
}

/// ViewModel for GuildLeaderboardView (Guilds Prompt G2).
///
/// Holds the ranked entries IN MEMORY only — each guild-mate's published stats
/// are fetched through the coordinator on appear and on pull-to-refresh, never
/// persisted. No listeners. Reuses the friend-leaderboard `LeaderboardEntry`.
///
/// The metric toggle re-sorts `entries` in memory via `sortedEntries`; it never
/// triggers a refetch (all three metrics are already in each entry).
@Observable
@MainActor
final class GuildLeaderboardViewModel {

    // MARK: - Dependencies

    private let coordinator: AppCoordinator

    // MARK: - State

    /// Ranked rows: current user + every guild-mate, deduped by uid. Stored
    /// unsorted; `sortedEntries` applies the selected-metric comparator.
    var entries: [LeaderboardEntry] = []

    /// Selected ranking metric. Default = weekly adherence (matches the friend
    /// leaderboard's primary metric).
    var metric: GuildMetric = .adherence

    var isLoading: Bool = false
    var loadError: String? = nil

    /// True once any refresh has completed — gates the first-load spinner.
    private(set) var hasLoaded: Bool = false

    // MARK: - Init

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    // MARK: - Derived

    /// `entries` ranked by the selected metric. `hasData == false` rows always
    /// sort last regardless of metric; ties broken deterministically.
    var sortedEntries: [LeaderboardEntry] {
        entries.sorted { lhs, rhs in
            // No-data rows always last.
            if lhs.hasData != rhs.hasData { return lhs.hasData }

            switch metric {
            case .adherence:
                if lhs.weeklyAdherence != rhs.weeklyAdherence { return lhs.weeklyAdherence > rhs.weeklyAdherence }
                if lhs.totalXP != rhs.totalXP { return lhs.totalXP > rhs.totalXP }
                if lhs.currentStreak != rhs.currentStreak { return lhs.currentStreak > rhs.currentStreak }
                return lhs.username.localizedCaseInsensitiveCompare(rhs.username) == .orderedAscending
            case .xp:
                if lhs.totalXP != rhs.totalXP { return lhs.totalXP > rhs.totalXP }
                if lhs.level != rhs.level { return lhs.level > rhs.level }
                return lhs.username.localizedCaseInsensitiveCompare(rhs.username) == .orderedAscending
            case .level:
                if lhs.level != rhs.level { return lhs.level > rhs.level }
                if lhs.totalXP != rhs.totalXP { return lhs.totalXP > rhs.totalXP }
                return lhs.username.localizedCaseInsensitiveCompare(rhs.username) == .orderedAscending
            }
        }
    }

    /// True when the only member with a row is the current user (a solo guild) —
    /// shown with an invite hint rather than an empty state.
    var isSoloGuild: Bool {
        entries.count == 1 && entries.first?.isCurrentUser == true
    }

    // MARK: - Loading

    /// Fetches each guild-mate's published projection and re-ranks client-side.
    /// Called from `.task` on appear and from pull-to-refresh.
    func refresh() async {
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }

        let result = await coordinator.loadGuildLeaderboard()
        if result.isEmpty {
            // In a guild, the current user's own row always exists — an empty
            // result means the load couldn't run. Keep any previously shown rows.
            loadError = "Couldn't load the leaderboard. Pull down to retry."
        } else {
            entries = result
            loadError = nil
        }
    }
}
