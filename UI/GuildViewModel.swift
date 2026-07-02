//
//  GuildViewModel.swift
//  HealthBar
//
//  Created by Claude on 6/18/26.
//

import Foundation

/// ViewModel for GuildView (Guilds Prompt G1).
///
/// Guild state is fetch-on-view / in-memory (no SwiftData model, no listeners),
/// matching the social-surface precedent. All mutations go through the coordinator;
/// this class maps DTOs to value-type rows so the view never holds a reference to
/// data that may have been deleted server-side.
@Observable
@MainActor
final class GuildViewModel {

    // MARK: - Stage

    enum Stage: Equatable {
        case loading
        case notInGuild
        case inGuild
    }

    // MARK: - Row Types

    struct MemberRow: Identifiable, Equatable {
        let id: String          // uid
        let username: String
        let displayName: String
        let role: String
        /// True when this row is the current user.
        let isMe: Bool
        /// True when this member is a friend (only friends are tappable to a profile).
        let isFriend: Bool

        var isOwnerRole: Bool { role == "owner" }

        /// Display name, falling back to the @username when no display name is set.
        var title: String { displayName.isEmpty ? "@\(username)" : displayName }
    }

    struct RequestRow: Identifiable, Equatable {
        let id: String          // requester uid
        let username: String
        let displayName: String

        var title: String { displayName.isEmpty ? "@\(username)" : displayName }
    }

    // MARK: - Dependencies

    private let coordinator: AppCoordinator

    // MARK: - State

    var stage: Stage = .loading
    var guild: GuildDTO? = nil
    var members: [MemberRow] = []
    var requests: [RequestRow] = []
    var isOwner: Bool = false

    /// Member count for the in-guild header.
    var memberCount: Int { members.count }

    // MARK: - Join (not-in-guild) State

    var joinCode: String = ""
    var joinError: String? = nil
    var isJoining: Bool = false

    /// Set after a successful request-to-join (session-local). Drives the
    /// "Request sent" pending banner; cleared on cancel or once we are a member.
    var pendingRequestCode: String? = nil

    // MARK: - Action State (in-guild)

    var actionError: String? = nil
    /// True while a guild-wide action (leave / disband) is in flight.
    var isActing: Bool = false
    /// Uids with an in-flight per-row action (approve / deny / kick).
    var pendingActionUids: Set<String> = []

    // MARK: - Init

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    var isGuest: Bool { coordinator.isGuest }

    // MARK: - Loading

    /// Resolves the current user's guild (O(1) lock read) and, if present, its
    /// roster and (for the owner of a request-policy guild) pending requests.
    func load() async {
        guard !coordinator.isGuest else {
            resetGuildState()
            stage = .notInGuild
            return
        }

        guard let g = await coordinator.myGuild(), let code = g.id else {
            resetGuildState()
            stage = .notInGuild
            return
        }

        let me = coordinator.currentUserId
        guild = g
        isOwner = (g.ownerUid == me)
        pendingRequestCode = nil   // We are a member now; clear any stale pending state.

        let memberDTOs = await coordinator.guildMembers(code: code)
        members = memberDTOs
            .map { dto in
                MemberRow(
                    id: dto.uid,
                    username: dto.username,
                    displayName: dto.displayName,
                    role: dto.role,
                    isMe: dto.uid == me,
                    isFriend: coordinator.friendshipState(with: dto.uid) == .friends
                )
            }
            .sorted { a, b in
                // Owner first, then by display name.
                if a.isOwnerRole != b.isOwnerRole { return a.isOwnerRole }
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }

        if isOwner && g.joinPolicy == "request" {
            let requestDTOs = await coordinator.joinRequests(code: code)
            requests = requestDTOs
                .map { RequestRow(id: $0.uid, username: $0.username, displayName: $0.displayName) }
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        } else {
            requests = []
        }

        stage = .inGuild
    }

    func refresh() async {
        await load()
    }

    private func resetGuildState() {
        guild = nil
        members = []
        requests = []
        isOwner = false
    }

    // MARK: - Join Flow

    /// Joins (open) or requests to join (request-policy) the entered code.
    func join() async {
        guard !isJoining else { return }
        let code = joinCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty else {
            joinError = "Enter a guild code."
            return
        }
        isJoining = true
        joinError = nil
        defer { isJoining = false }

        do {
            try await coordinator.joinGuild(code: code)
            await load()
            // If joinGuild succeeded but we are still not in a guild, it was a
            // request-policy guild — show the pending banner.
            if stage == .notInGuild {
                pendingRequestCode = code
            } else {
                joinCode = ""
            }
        } catch {
            joinError = friendlyMessage(for: error)
        }
    }

    /// Cancels the session's pending join request.
    func cancelPendingRequest() async {
        guard let code = pendingRequestCode else { return }
        joinError = nil
        do {
            try await coordinator.cancelMyJoinRequest(code: code)
            pendingRequestCode = nil
            joinCode = ""
        } catch {
            joinError = friendlyMessage(for: error)
        }
    }

    // MARK: - Owner Request Actions

    func approve(_ row: RequestRow) async {
        guard let code = guild?.id else { return }
        await performRowAction(uid: row.id) {
            let dto = GuildJoinRequestDTO(uid: row.id, username: row.username,
                                         displayName: row.displayName, createdAt: Date())
            try await self.coordinator.approveRequest(code: code, request: dto)
        }
    }

    func deny(_ row: RequestRow) async {
        guard let code = guild?.id else { return }
        await performRowAction(uid: row.id) {
            try await self.coordinator.denyRequest(code: code, requesterUid: row.id)
        }
    }

    func kick(_ row: MemberRow) async {
        guard let code = guild?.id else { return }
        await performRowAction(uid: row.id) {
            try await self.coordinator.kickMember(code: code, memberUid: row.id)
        }
    }

    // MARK: - Membership Actions

    func leave() async {
        guard let code = guild?.id else { return }
        await performGlobalAction {
            try await self.coordinator.leaveGuild(code: code)
        }
    }

    func disband() async {
        guard let code = guild?.id else { return }
        await performGlobalAction {
            try await self.coordinator.disbandGuild(code: code)
        }
    }

    // MARK: - Helpers

    private func performRowAction(uid: String, _ operation: () async throws -> Void) async {
        guard !pendingActionUids.contains(uid) else { return }
        pendingActionUids.insert(uid)
        actionError = nil
        defer { pendingActionUids.remove(uid) }
        do {
            try await operation()
            await load()
        } catch {
            actionError = friendlyMessage(for: error)
            await load()
        }
    }

    private func performGlobalAction(_ operation: () async throws -> Void) async {
        guard !isActing else { return }
        isActing = true
        actionError = nil
        defer { isActing = false }
        do {
            try await operation()
            await load()
        } catch {
            actionError = friendlyMessage(for: error)
            await load()
        }
    }

    private func friendlyMessage(for error: Error) -> String {
        if let guildError = error as? GuildError {
            return guildError.errorDescription ?? "Something went wrong."
        }
        return GuildError.network(error.localizedDescription).errorDescription ?? "Something went wrong."
    }
}
