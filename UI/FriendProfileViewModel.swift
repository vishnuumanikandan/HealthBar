//
//  FriendProfileViewModel.swift
//  HealthBar
//
//  Created by Claude on 6/10/26.
//

import Foundation

/// ViewModel for FriendProfileView.
///
/// NAV-1a broadened this from friends-only to ANY signed-in viewer: the profile
/// is a richer render of the same `public/stats` projection the leaderboard
/// fetches — one document read (open to any signed-in user post-B1), nothing
/// persisted, no listener. `relationship` drives friend vs. stranger mode.
/// Badges arrive as published IDs and are resolved to emoji/title locally via
/// BadgeDefinition; another user's badges subcollection is never read. The name
/// is kept deliberately (no-renames rule).
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

    // MARK: - Relationship (NAV-1a)

    /// Drives friend vs. stranger mode. Resolved from the local friendship cache
    /// on every load(); a synchronous read, so it's set directly on the main actor.
    private(set) var relationship: FriendshipState = .none

    /// In-flight flag for the Add Friend send (mirrors isRemoving's shape).
    var isAddingFriend: Bool = false

    /// Surfaced inline below the Add Friend button on failure; the section stays.
    var addFriendError: String? = nil

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
        // NAV-1a: resolve friend vs. stranger mode on every load (incl. retry).
        // Synchronous local-cache read — safe to set directly on the main actor.
        relationship = coordinator.friendshipState(with: friendUid)
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

    // MARK: - Add Friend (NAV-1a)

    /// True in friend mode — gates the comparison + Remove Friend sections in the view.
    var isFriend: Bool { relationship == .friends }

    /// Pass-through for the view's defense-in-depth Add Friend hide (mirrors the
    /// addFriend() guard; guests can't reach profiles today).
    var isGuest: Bool { coordinator.isGuest }

    /// Sends a friend request to this profile's owner by uid (NAV-1a). Guarded to
    /// the `.none` relationship (defense-in-depth; the button only renders then)
    /// and to non-guests, with an in-flight flag matching removeFriend's shape.
    /// On success the local insert (or the FR-1 idempotent branch) makes the
    /// relationship `.outgoingPending` → the button reads "Request Sent". Failure
    /// surfaces `addFriendError`; all copy comes from existing FriendError cases.
    func addFriend() async {
        guard !coordinator.isGuest, relationship == .none, !isAddingFriend else { return }
        isAddingFriend = true
        addFriendError = nil
        defer { isAddingFriend = false }

        do {
            try await coordinator.sendFriendRequest(toUid: friendUid, username: username)
            // Re-resolve directly (no load() — no redundant stats refetch); the local
            // insert makes this .outgoingPending.
            relationship = coordinator.friendshipState(with: friendUid)
        } catch {
            // No new copy: matches removeFriend's FriendError-or-network fallback shape,
            // minus the literal default (every relevant FriendError case has copy).
            if let friendError = error as? FriendError {
                addFriendError = friendError.errorDescription
            } else {
                addFriendError = FriendError.network(error.localizedDescription).errorDescription
            }
        }
    }

    // MARK: - Safety (UGC-1b)

    /// Transient confirmation after a report — mirrors FriendsView's success line (persists
    /// until the next action or the sheet dismisses).
    var actionMessage: String? = nil

    /// Surfaced when a block fails; the sheet stays open (same treatment as removeError).
    var blockError: String? = nil
    var isBlocking: Bool = false

    /// Reports this profile (D5 `.userProfile`). Deterministic-id duplicates return silent
    /// success in DataManager (D6) → same confirmation, no special casing. Snapshot composed
    /// at the call site: "@username / displayName", omitting " / " when displayName is empty.
    func report() async {
        blockError = nil
        let snapshot = displayName.isEmpty ? "@\(username)" : "@\(username) / \(displayName)"
        do {
            try await coordinator.submitReport(
                context: .userProfile, reportedUid: friendUid,
                contentSnapshot: snapshot, guildCode: nil, messageId: nil)
            actionMessage = "Report submitted"
        } catch {
            blockError = (error as? BlockError)?.errorDescription ?? "Couldn't submit the report."
        }
    }

    /// Blocks this user (D4). Returns true so the view dismisses (D11 — they are no longer
    /// viewable). On failure the sheet stays open with blockError surfaced.
    func block() async -> Bool {
        guard !isBlocking else { return false }
        isBlocking = true
        blockError = nil
        defer { isBlocking = false }
        do {
            try await coordinator.blockUser(friendUid)
            return true
        } catch {
            blockError = (error as? BlockError)?.errorDescription ?? "Couldn't block this user."
            return false
        }
    }
}
