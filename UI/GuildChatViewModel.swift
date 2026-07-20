//
//  GuildChatViewModel.swift
//  HealthBar
//
//  Created by Claude on 6/21/26.
//

import Foundation

/// ViewModel for GuildChatView (Guilds Prompt G3).
///
/// Owns the chat-screen lifecycle: `start()` registers the screen-scoped live
/// listener (the single ListenerRegistration lives in FirestoreServiceImpl, never
/// here — no Firestore type leaks into the view layer), `stop()` removes it. Both
/// are mandatory; a missing `stop()` leaks the listener.
///
/// Server-authoritative via local echo: a sent message appears instantly because
/// the SDK fires the listener from its local cache (createdAt nil ⇒ "sending…"
/// until the server resolves it). No parallel optimistic list is maintained.
@Observable
@MainActor
final class GuildChatViewModel {

    // MARK: - Dependencies

    private let coordinator: AppCoordinator
    private let code: String

    /// Whether the current user owns this guild (can delete any message).
    let isOwner: Bool

    /// The current user's uid (own-message styling + sender-delete check).
    let myUid: String

    // MARK: - State

    var messages: [GuildMessageDTO] = []
    var input: String = ""
    var isSending: Bool = false

    /// Transient error surfaced under the input (send/delete/report/block failures).
    var banner: String? = nil

    /// UGC-1c: set true after a successful report; the view presents the 1b-mirrored
    /// "Report submitted" confirmation, then resets it. Report has no pre-submit dialog
    /// (mirrors FriendProfileView, where Report fires directly and only Block confirms).
    var reportConfirmation: Bool = false

    /// Set when the listener hits a terminal error (kicked / left / disbanded
    /// while open) → the view shows a notice and pops.
    var wasEjected: Bool = false

    /// Friend uids (resolved once on start) — drives the friend-only sender tap.
    private var friendUids: Set<String> = []

    /// L3: set by stop(); guards the post-await listener registration in start() so a stop()
    /// that races an in-flight start() can't leave an orphan listener (this VM's guild-chat
    /// listener is deliberately outside the global registry, so stopAllListeners never reaps it).
    private var isStopped: Bool = false

    // MARK: - Init

    init(coordinator: AppCoordinator, code: String, isOwner: Bool, myUid: String) {
        self.coordinator = coordinator
        self.code = code
        self.isOwner = isOwner
        self.myUid = myUid
    }

    // MARK: - Lifecycle

    /// Resolve friends once, then start the live listener. Call from the view's `.task`.
    func start() async {
        isStopped = false
        friendUids = Set(((try? await coordinator.fetchFriends()) ?? []).map { $0.friendUid })
        // L3: if the view disappeared during the friends fetch, stop() already ran — don't
        // register an orphan listener. Check both the flag and Task cancellation (.task cancels on
        // disappear, but cancellation alone doesn't stop these post-await lines from running).
        guard !isStopped, !Task.isCancelled else { return }
        // The closures hop to the main actor before touching @MainActor state. The
        // service already dispatches on main, so this is a (harmless) double-hop
        // that also satisfies the non-isolated closure type.
        coordinator.startGuildChat(
            code: code,
            onUpdate: { [weak self] msgs in
                Task { @MainActor in self?.messages = msgs }
            },
            onError: { [weak self] _ in
                Task { @MainActor in self?.wasEjected = true }
            }
        )
    }

    /// Remove the listener. Call from the view's `.onDisappear` (mandatory).
    func stop() {
        isStopped = true
        coordinator.stopGuildChat()
    }

    // MARK: - Sending

    var canSend: Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 500 && !isSending && !wasEjected
    }

    func send() async {
        // Once ejected, sending is disabled — avoids a confusing post-kick
        // permission-denied before the eject UI lands.
        guard !wasEjected else { return }
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 500, !isSending else { return }

        isSending = true
        banner = nil
        defer { isSending = false }
        do {
            try await coordinator.sendGuildMessage(code: code, text: trimmed)
            input = ""   // The sent message arrives via the listener's local echo.
        } catch {
            banner = friendlyMessage(for: error)
        }
    }

    // MARK: - Moderation

    func canDelete(_ message: GuildMessageDTO) -> Bool {
        message.senderUid == myUid || isOwner
    }

    func delete(_ message: GuildMessageDTO) async {
        guard let msgId = message.id else { return }
        banner = nil
        do {
            try await coordinator.deleteGuildMessage(code: code, msgId: msgId)
        } catch {
            banner = friendlyMessage(for: error)
        }
    }

    /// UGC-1c: report this message (contextType `.chatMessage`). Mirrors
    /// FriendProfileViewModel.report — DataManager owns the deterministic
    /// `{myUid}_msg_{msgId}` id and the snapshot cap, and folds a duplicate report
    /// (permission-denied on the create-only doc) into silent success, so a normal
    /// return is the success case with no special handling here. `id != nil` is
    /// defense-in-depth: own (in-flight, id-nil) messages never expose Report.
    func report(_ message: GuildMessageDTO) async {
        guard !isOwnMessage(message) else { return }
        guard let msgId = message.id else { return }
        banner = nil
        do {
            try await coordinator.submitReport(
                context: .chatMessage,
                reportedUid: message.senderUid,
                contentSnapshot: message.text,
                guildCode: code,
                messageId: msgId
            )
            reportConfirmation = true
        } catch {
            banner = friendlyMessage(for: error)
        }
    }

    /// UGC-1c: block this message's sender. The UGC-1a side-effect order lives inside
    /// DataManager (unfriend, cancel requests/duels, record block) — never reimplemented
    /// here. Blocking does NOT touch guild membership (one-way visibility: I stop seeing
    /// them; they stay in the guild and still see me).
    func block(_ message: GuildMessageDTO) async {
        guard !isOwnMessage(message) else { return }
        banner = nil
        do {
            try await coordinator.blockUser(message.senderUid)
            // UGC-1c: immediate local UX; the UGC-1b listener closure filters all future snapshot events + history reloads.
            messages.removeAll { $0.senderUid == message.senderUid }
        } catch {
            banner = friendlyMessage(for: error)
        }
    }

    // MARK: - Helpers

    func isOwnMessage(_ message: GuildMessageDTO) -> Bool {
        message.senderUid == myUid
    }

    /// True when this sender is a friend (and not me) — only then is the row
    /// tappable to a profile, consistent with G1/G2.
    func canOpenProfile(_ message: GuildMessageDTO) -> Bool {
        message.senderUid != myUid && friendUids.contains(message.senderUid)
    }

    private func friendlyMessage(for error: Error) -> String {
        if let chatError = error as? GuildChatError {
            return chatError.errorDescription ?? "Something went wrong."
        }
        if let guildError = error as? GuildError {
            return guildError.errorDescription ?? "Something went wrong."
        }
        // UGC-1c: report/block failures throw BlockError; surface its own copy rather
        // than letting the fallthrough re-wrap it as a "Couldn't send…" chat error.
        if let blockError = error as? BlockError {
            return blockError.errorDescription ?? "Something went wrong."
        }
        return GuildChatError.network(error.localizedDescription).errorDescription ?? "Something went wrong."
    }
}
