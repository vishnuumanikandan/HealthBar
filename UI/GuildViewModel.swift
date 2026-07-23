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
        /// D3b preset avatar — the member's snapshot from `GuildMemberDTO`. nil ⇒ initials.
        var avatarIcon: String? = nil
        var avatarColor: String? = nil

        var isOwnerRole: Bool { role == "owner" }

        /// Display name, falling back to the @username when no display name is set.
        var title: String { displayName.isEmpty ? "@\(username)" : displayName }
    }

    struct RequestRow: Identifiable, Equatable {
        let id: String          // requester uid
        let username: String
        let displayName: String
        /// D3b preset avatar — the requester's snapshot from `GuildJoinRequestDTO`. nil ⇒ initials.
        var avatarIcon: String? = nil
        var avatarColor: String? = nil

        var title: String { displayName.isEmpty ? "@\(username)" : displayName }
    }

    /// A row in the browsable guild directory (R7d). `id` is the guild code — the only
    /// key the join path needs, so the row carries no server state beyond what it renders.
    /// `private` guilds never appear here: the rules' `list` clause excludes them.
    struct GuildDirectoryRow: Identifiable, Equatable {
        let id: String          // guild code
        let name: String
        let description: String?
        let joinPolicy: String
        /// UGC-1b: the guild owner's uid — the report target for a directory-row report (D5).
        let ownerUid: String

        /// Request-policy guilds send an approval request rather than joining directly.
        var isRequestPolicy: Bool { joinPolicy == "request" }
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
    ///
    /// D4: session-local by contract. A request made in a PREVIOUS session renders as a
    /// plain "Request" button again; re-tapping surfaces the existing duplicate/lost-race
    /// error path. Not persisted — that is the shipped G-series behavior, not a new bug.
    var pendingRequestCode: String? = nil

    // MARK: - Directory (not-in-guild) State — R7d

    /// The browsable directory: joinable, non-`private` guilds, name-ordered.
    var guildDirectory: [GuildDirectoryRow] = []
    var directoryError: String? = nil
    /// Client-side search over the fetched set only (the fetch is capped, not paginated).
    var directorySearch: String = ""
    /// True during the FIRST directory fetch — distinguishes "still loading" from
    /// "loaded, and there genuinely are no open guilds".
    var isLoadingDirectory: Bool = false

    /// The directory filtered by `directorySearch`. Empty (or whitespace-only) input = all.
    /// Case-insensitive substring match on the guild name; never on the description.
    var filteredGuildDirectory: [GuildDirectoryRow] {
        let q = directorySearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return guildDirectory }
        return guildDirectory.filter { $0.name.lowercased().contains(q) }
    }

    // MARK: - Action State (in-guild)

    var actionError: String? = nil
    /// UGC-1b: transient "Report submitted" confirmation (guild report — directory + detail header).
    var reportConfirmation: String? = nil
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
            // R7d: the directory is the not-in-guild stage's content, so it loads with the
            // stage (fetch-on-view). refresh() reaches it through load() unchanged; guests
            // returned above and never get here (D5).
            await loadGuildDirectory()
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
                    isFriend: coordinator.friendshipState(with: dto.uid) == .friends,
                    avatarIcon: dto.avatarIcon,
                    avatarColor: dto.avatarColor
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
                .map { RequestRow(id: $0.uid, username: $0.username, displayName: $0.displayName,
                                  avatarIcon: $0.avatarIcon, avatarColor: $0.avatarColor) }
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

    // MARK: - Directory (R7d)

    /// Fetches the browsable directory. Guest-gated at the DataManager entry point (D5);
    /// on failure the previously fetched rows stay put behind the error banner rather than
    /// blanking the list into a misleading "no open guilds" empty state.
    func loadGuildDirectory() async {
        isLoadingDirectory = guildDirectory.isEmpty
        directoryError = nil
        defer { isLoadingDirectory = false }
        do {
            let dtos = try await coordinator.fetchGuildDirectory()
            // A guild with no code is unjoinable — drop it rather than render a dead row.
            guildDirectory = dtos.compactMap { dto in
                guard let code = dto.id else { return nil }
                return GuildDirectoryRow(id: code, name: dto.name,
                                         description: dto.description, joinPolicy: dto.joinPolicy,
                                         ownerUid: dto.ownerUid)
            }
        } catch {
            directoryError = friendlyMessage(for: error)
        }
    }

    // MARK: - Safety (UGC-1b)

    /// Reports a guild (D5 `.guild`): reportedUid is the owner's uid, guildCode is the code,
    /// snapshot is the name plus " — description" when a description is present. Deterministic-id
    /// duplicates are silent success in DataManager (D6) → same confirmation, no special casing.
    func reportGuild(ownerUid: String, code: String, name: String, description: String?) async {
        reportConfirmation = nil
        var snapshot = name
        if let description, !description.isEmpty { snapshot += " — \(description)" }
        do {
            try await coordinator.submitReport(
                context: .guild, reportedUid: ownerUid,
                contentSnapshot: snapshot, guildCode: code, messageId: nil)
            reportConfirmation = "Report submitted"
        } catch {
            actionError = (error as? BlockError)?.errorDescription ?? friendlyMessage(for: error)
        }
    }

    // MARK: - Join Flow

    /// Joins (open/private) or requests to join (request-policy) the code in the entry field.
    func join() async {
        // The in-flight guard stays AHEAD of the empty-code check, as before — a join in
        // flight must not repaint the field's validation error.
        guard !isJoining else { return }
        let code = joinCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty else {
            joinError = "Enter a guild code."
            return
        }
        await performJoin(code: code)
    }

    /// Joins (or requests) straight from a directory row — the row's id IS the guild code,
    /// so it needs no normalization. Same core, same single in-flight flag as the code path.
    func joinFromDirectory(_ row: GuildDirectoryRow) async {
        await performJoin(code: row.id, fromDirectory: true)
    }

    /// The shared join core. `isJoining` is the ONE in-flight flag: it disables the
    /// code-entry button and EVERY directory row action, so only one join runs at a time.
    private func performJoin(code: String, fromDirectory: Bool = false) async {
        guard !isJoining else { return }
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
            // A row can go stale between fetch and tap (disbanded, or switched to private).
            // Re-fetch so the dead row disappears with the error rather than lingering.
            if fromDirectory { await loadGuildDirectory() }
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
