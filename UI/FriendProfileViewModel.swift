//
//  FriendProfileViewModel.swift
//  HealthBar
//
//  Created by Claude on 6/10/26.
//

import Foundation

/// ViewModel for FriendProfileView (Friend System Phase 4).
///
/// A friend's profile is a richer render of the same `public/stats` projection
/// the leaderboard fetches — one friend-gated document read, nothing persisted,
/// no listener. Badges arrive as published IDs and are resolved to emoji/title
/// locally via BadgeDefinition; another user's badges subcollection is never
/// read.
@Observable
@MainActor
final class FriendProfileViewModel {

    // MARK: - Dependencies

    private let coordinator: AppCoordinator

    // MARK: - Identity

    /// The profile's identity key — stats, removal, and dedup all key on this.
    let friendUid: String

    /// Local Friend snapshot identity, shown instantly while stats load and
    /// kept as the fallback when the friend has not published yet.
    private let initialUsername: String
    private let initialDisplayName: String

    // MARK: - State

    var stats: PublicStatsDTO? = nil
    var isLoading: Bool = false
    var loadError: String? = nil

    /// True once any load attempt has finished — separates "still loading"
    /// from "loaded and the friend has no published stats."
    private(set) var hasLoaded: Bool = false

    var isRemoving: Bool = false
    var removeError: String? = nil

    // MARK: - Comparison State (Friend System Phase 6)

    /// The current user's own stats, built LOCALLY (no network, no self-read of
    /// `public/stats`). nil until the first Compare tap; built at most once per
    /// view-model lifetime and reused across expand/collapse toggles.
    var myStats: PublicStatsDTO? = nil

    /// Whether the inline comparison section is expanded.
    var showComparison: Bool = false

    /// True only during the one-shot local snapshot build.
    var isBuildingMine: Bool = false

    /// Surfaced inline when the local self-build fails (vs. silently hiding
    /// Compare) — the friend's stats are fine, only my snapshot couldn't build.
    var compareError: String? = nil

    // MARK: - Init

    init(coordinator: AppCoordinator, friendUid: String, username: String, displayName: String) {
        self.coordinator = coordinator
        self.friendUid = friendUid
        self.initialUsername = username
        self.initialDisplayName = displayName
    }

    // MARK: - Display Identity (published snapshot first, local fallback)

    var displayName: String {
        if let published = stats?.displayName, !published.isEmpty { return published }
        return initialDisplayName
    }

    var username: String {
        if let published = stats?.username, !published.isEmpty { return published }
        return initialUsername
    }

    // MARK: - Badges (IDs → local definitions)

    /// Every badge the app defines — the grid renders all of them, with the
    /// earned ones highlighted.
    let allBadges = BadgeDefinition.all

    /// Published IDs resolved locally; IDs without a current definition
    /// (badge removed from the app) are silently dropped.
    var earnedBadges: [BadgeDefinition] {
        (stats?.earnedBadgeIds ?? []).compactMap { BadgeDefinition.find(id: $0) }
    }

    /// Set of earned IDs for O(1) highlight checks in the grid.
    var earnedBadgeIdSet: Set<String> {
        Set(stats?.earnedBadgeIds ?? [])
    }

    /// The published count is the header's source of truth — it can legitimately
    /// exceed earnedBadges.count when an unknown ID was dropped from the grid.
    var publishedBadgeCount: Int {
        stats?.badgeCount ?? 0
    }

    // MARK: - Loading

    /// Fetches the friend's published projection. nil ⇒ "hasn't shared their
    /// stats yet" (not an error — also covers permission-denied/unfriended,
    /// which the service folds into nil). A thrown error ⇒ retryable loadError.
    func load() async {
        isLoading = true
        loadError = nil
        defer {
            isLoading = false
            hasLoaded = true
        }

        do {
            stats = try await coordinator.fetchPublicStats(friendUid: friendUid)
        } catch {
            loadError = "Couldn't load this profile. Check your connection and retry."
        }
    }

    // MARK: - Comparison (Friend System Phase 6)

    /// Whether the Compare affordance should be offered.
    ///
    /// Gated ONLY on preconditions — the friend has shared stats and we aren't a
    /// guest. NEVER on `myStats`: that is always nil before the first tap, so
    /// gating on it would hide Compare forever. The local self-build happens
    /// lazily in `toggleComparison()`; a build failure surfaces `compareError`
    /// instead of hiding the button.
    var canCompare: Bool {
        stats != nil && !coordinator.isGuest
    }

    /// Expands/collapses the inline comparison.
    ///
    /// First reveal builds the local snapshot exactly once (no self-read; fresher
    /// than the published doc) and caches it. Later toggles just flip
    /// `showComparison` — adherence is never recomputed on expand/collapse. A
    /// build that returns nil leaves `myStats` nil and surfaces `compareError`,
    /// so a later tap can retry rather than the button silently dying.
    func toggleComparison() async {
        // Already built — cheap flip, never recompute.
        if myStats != nil {
            showComparison.toggle()
            return
        }

        guard !isBuildingMine else { return }
        isBuildingMine = true
        compareError = nil
        defer { isBuildingMine = false }

        if let snapshot = await coordinator.currentUserStats() {
            myStats = snapshot
            showComparison = true
        } else {
            compareError = "Couldn't build your stats to compare. Try again."
        }
    }

    // MARK: - Remove Friend

    /// Removes the friendship and reports success — the view dismisses only on
    /// true; on failure the sheet stays open with removeError surfaced.
    func removeFriend() async -> Bool {
        guard !isRemoving else { return false }
        isRemoving = true
        removeError = nil
        defer { isRemoving = false }

        do {
            try await coordinator.removeFriend(friendUid: friendUid)
            return true
        } catch {
            if let friendError = error as? FriendError {
                removeError = friendError.errorDescription ?? "Couldn't remove this friend."
            } else {
                removeError = FriendError.network(error.localizedDescription).errorDescription
                    ?? "Couldn't remove this friend."
            }
            return false
        }
    }
}
