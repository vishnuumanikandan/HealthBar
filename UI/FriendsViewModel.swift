//
//  FriendsViewModel.swift
//  HealthBar
//
//  Created by Claude on 6/9/26.
//

import Foundation

/// ViewModel for FriendsView (Friend System Phase 2).
///
/// Reads cached Friend/FriendRequest rows via the coordinator and maps them to
/// value-type rows so the view never holds @Model references that the snapshot
/// listeners' reconcile may delete underneath it. All mutations go through the
/// coordinator; this class never writes friend data locally — the listeners'
/// reconcile is the single local writer.
@Observable
@MainActor
final class FriendsViewModel {

    // MARK: - Row Types (value snapshots of the @Model rows)

    struct FriendRow: Identifiable, Equatable {
        let id: String // friend uid
        let username: String
        let displayName: String
        let since: Date

        // D3b preset avatar — the accept-time SNAPSHOT from the Friend edge (NOT the live
        // published stats, deliberately: a pre-D3b friendship has no snapshot and renders
        // initials permanently — no backfill). nil ⇒ initials.
        var avatarIcon: String? = nil
        var avatarColor: String? = nil

        // Published-stats detail (Friend System Phase 4 rich rows).
        // nil ⇒ this friend hasn't published a projection yet.
        var level: Int? = nil
        var currentStreak: Int? = nil
        var rank: String? = nil
        var rr: Int? = nil
    }

    struct RequestRow: Identifiable, Equatable {
        let id: String // counterparty uid
        let username: String
        let displayName: String?
        let createdAt: Date
        // D3b preset avatar — the sender's snapshot (incoming only; outgoing is nil since
        // SentRequestDTO carries no avatar). nil ⇒ initials.
        var avatarIcon: String? = nil
        var avatarColor: String? = nil
    }

    /// One user from the public usernames directory, plus the locally
    /// classified relationship that drives which action button is rendered.
    struct DirectoryRow: Identifiable, Equatable {
        let id: String // uid
        let username: String
        var state: FriendshipState
    }

    // MARK: - Dependencies

    private let coordinator: AppCoordinator

    // MARK: - List State (refreshed from listener-maintained SwiftData)

    var friends: [FriendRow] = []
    var incomingRequests: [RequestRow] = []
    var outgoingRequests: [RequestRow] = []

    // MARK: - Add Friend State (user directory)

    /// Every user in the app (alphabetical, self excluded), from the public
    /// usernames index. Fetched on appear and on pull-to-refresh; relationship
    /// states are recomputed locally on every load() tick.
    var directory: [DirectoryRow] = []
    var directoryError: String? = nil

    /// Filter text for the directory list (leading "@" is ignored).
    var searchInput: String = ""
    var searchError: String? = nil
    var searchSuccessMessage: String? = nil

    /// The directory filtered by the search input. Empty input = everyone.
    var filteredDirectory: [DirectoryRow] {
        let filter = normalizedInput().lowercased()
        guard !filter.isEmpty else { return directory }
        return directory.filter { $0.username.contains(filter) }
    }

    /// Set when a send hits FriendError.incomingExists — the view deep-links
    /// to the Requests segment and resets this flag.
    var shouldShowRequestsSegment: Bool = false

    // MARK: - Per-Action State

    /// Uids with an in-flight accept/decline/cancel/remove — disables their buttons.
    var pendingActionUids: Set<String> = []
    var actionError: String? = nil

    // MARK: - Init

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    // MARK: - Loading

    /// Re-queries the listener-maintained local cache and applies deterministic
    /// sorts (never relies on Firestore snapshot order).
    func load() async {
        let friendModels = (try? await coordinator.fetchFriends()) ?? []
        var friendRows = friendModels
            .map { FriendRow(id: $0.friendUid, username: $0.username, displayName: $0.displayName, since: $0.since,
                             avatarIcon: $0.avatarIcon, avatarColor: $0.avatarColor) }
        // Merge the cached published stats into each row (nil = unpublished).
        friendRows = friendRows.map { row in
            var row = row
            if let stats = friendStatsByUid[row.id] {
                row.level = stats.level
                row.currentStreak = stats.currentStreak
                row.rank = stats.rank
                row.rr = stats.rr
            }
            return row
        }
        friends = friendRows
            .sorted { lhs, rhs in
                // D3: implicit rank ladder — RR descending, nil-rr rows last, displayName tiebreak.
                switch (lhs.rr, rhs.rr) {
                case let (l?, r?) where l != r: return l > r
                case (nil, _?): return false   // lhs unranked → after a ranked rhs
                case (_?, nil): return true    // lhs ranked → before an unranked rhs
                default:
                    return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
                }
            }

        let incomingModels = (try? await coordinator.fetchRequests(direction: "incoming")) ?? []
        incomingRequests = incomingModels
            .map { RequestRow(id: $0.otherUid, username: $0.username, displayName: $0.displayName, createdAt: $0.createdAt,
                              avatarIcon: $0.avatarIcon, avatarColor: $0.avatarColor) }
            .sorted { $0.createdAt > $1.createdAt }

        let outgoingModels = (try? await coordinator.fetchRequests(direction: "outgoing")) ?? []
        outgoingRequests = outgoingModels
            .map { RequestRow(id: $0.otherUid, username: $0.username, displayName: $0.displayName, createdAt: $0.createdAt,
                              avatarIcon: $0.avatarIcon, avatarColor: $0.avatarColor) }
            .sorted { $0.createdAt > $1.createdAt }

        // Recompute every directory row's relationship from the local cache so
        // action buttons flip (Add → Pending → Friends) as listeners reconcile.
        directory = directory.map { row in
            var row = row
            row.state = coordinator.friendshipState(with: row.id)
            return row
        }
    }

    /// Fetches the full alphabetical user directory (self excluded) from the
    /// public usernames index.
    func loadDirectory() async {
        do {
            let users = try await coordinator.fetchAllUsers()
            directory = users.map {
                DirectoryRow(id: $0.uid, username: $0.username,
                             state: coordinator.friendshipState(with: $0.uid))
            }
            directoryError = nil
        } catch {
            directoryError = friendlyMessage(for: error)
        }
    }

    /// Reloads the directory, the friends' published stats, and the local lists
    /// (pull-to-refresh).
    func refresh() async {
        await loadDirectory()
        await loadFriendStats()
    }

    /// Fetches every friend's published projection once (fetch-on-view, same
    /// staleness contract as the leaderboard) and rebuilds the rows with it.
    /// Deliberately NOT part of the 2s polling loop — that loop re-reads the
    /// local cache only and must stay free of Firestore reads.
    func loadFriendStats() async {
        friendStatsByUid = await coordinator.fetchFriendStats()
        await load()
    }

    /// Published stats per friend uid, fetched on appear and on refresh.
    private var friendStatsByUid: [String: PublicStatsDTO] = [:]

    /// Loads immediately, then re-queries on a short cadence while the view is
    /// visible so listener reconciles surface live. Cancelled with the view's .task.
    ///
    /// Order matters: the local cache paints first (instant), THEN the network
    /// round-trips (directory, friend stats) enrich it. Blocking the first
    /// paint on the network shows a false "No friends yet" on slow starts.
    func observeChanges() async {
        await load()
        await loadDirectory()
        await loadFriendStats()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(2))
            await load()
        }
    }

    // MARK: - Add Friend Flow (directory actions)

    /// Sends a request to a directory row. The full validation pipeline
    /// (including the authoritative reverse-request server read) runs in
    /// DataManager — local state may be stale.
    func addFriend(_ row: DirectoryRow) async {
        guard !pendingActionUids.contains(row.id) else { return }
        pendingActionUids.insert(row.id)
        searchError = nil
        searchSuccessMessage = nil
        defer { pendingActionUids.remove(row.id) }

        do {
            try await coordinator.sendFriendRequest(toHandle: row.username)
            searchSuccessMessage = "Request sent to @\(row.username)"
            // TUT-2 friends detection (Decision 2) — friend-request-send success (fallback second
            // site; FriendsView's appearance is the primary). A no-op in practice — the user has
            // already visited Friends to reach here — but the guard keeps it harmless.
            if TutorialProgress.shared.shouldAttempt(TutorialCatalog.friendsId) {
                Task { _ = try? await coordinator.completeTutorialStep(TutorialCatalog.friendsId) }
            }
            await load()
        } catch FriendError.incomingExists {
            searchError = FriendError.incomingExists.errorDescription
            shouldShowRequestsSegment = true
            await load()
        } catch {
            searchError = friendlyMessage(for: error)
        }
    }

    /// Accepts directly from the directory when the counterparty already
    /// sent a request (state == .incomingPending).
    func acceptFromDirectory(_ row: DirectoryRow) async {
        await accept(fromUid: row.id)
        if actionError == nil {
            searchSuccessMessage = "You're now friends with @\(row.username)"
        } else {
            searchError = actionError
            actionError = nil
        }
    }

    // MARK: - Safety (UGC-1b)

    /// Reports a directory user (D5 `.userProfile`). The row carries no displayName, so the
    /// snapshot is "@username" alone — the " / displayName" part is omitted (D5). Duplicate
    /// reports are silent success in DataManager (D6) → same toast.
    func reportDirectoryUser(_ row: DirectoryRow) async {
        searchError = nil
        do {
            try await coordinator.submitReport(
                context: .userProfile, reportedUid: row.id,
                contentSnapshot: "@\(row.username)", guildCode: nil, messageId: nil)
            searchSuccessMessage = "Report submitted"
        } catch {
            searchError = (error as? BlockError)?.errorDescription ?? friendlyMessage(for: error)
        }
    }

    /// Blocks a directory user (D4/D11). On success reloads friends + directory so the now-
    /// hidden row disappears (fetchAllUsers filters blocked uids — chokepoint 2).
    func blockDirectoryUser(_ row: DirectoryRow) async {
        searchError = nil
        do {
            try await coordinator.blockUser(row.id)
            await load()
            await loadDirectory()
        } catch {
            searchError = (error as? BlockError)?.errorDescription ?? friendlyMessage(for: error)
        }
    }

    // MARK: - Request / Friend Actions

    func accept(fromUid: String) async {
        await performAction(uid: fromUid) {
            try await self.coordinator.acceptIncomingRequest(fromUid: fromUid)
        }
    }

    func decline(fromUid: String) async {
        await performAction(uid: fromUid) {
            try await self.coordinator.declineIncomingRequest(fromUid: fromUid)
        }
    }

    func cancel(toUid: String) async {
        await performAction(uid: toUid) {
            try await self.coordinator.cancelSentRequest(toUid: toUid)
        }
    }

    func remove(friendUid: String) async {
        await performAction(uid: friendUid) {
            try await self.coordinator.removeFriend(friendUid: friendUid)
        }
    }

    // MARK: - Helpers

    private func performAction(uid: String, _ operation: () async throws -> Void) async {
        guard !pendingActionUids.contains(uid) else { return }
        pendingActionUids.insert(uid)
        actionError = nil
        defer { pendingActionUids.remove(uid) }

        do {
            try await operation()
            await load()
        } catch {
            actionError = friendlyMessage(for: error)
            await load() // The listener reconciles truth after a lost race.
        }
    }

    /// Strips a leading "@" and surrounding whitespace from the search input.
    private func normalizedInput() -> String {
        var raw = searchInput.trimmingCharacters(in: .whitespaces)
        if raw.hasPrefix("@") { raw = String(raw.dropFirst()) }
        return raw
    }

    private func friendlyMessage(for error: Error) -> String {
        if let friendError = error as? FriendError {
            return friendError.errorDescription ?? "Something went wrong."
        }
        if let usernameError = error as? UsernameError {
            return usernameError.errorDescription ?? "Something went wrong."
        }
        return FriendError.network(error.localizedDescription).errorDescription ?? "Something went wrong."
    }
}
