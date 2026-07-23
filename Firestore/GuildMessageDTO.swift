//
//  GuildMessageDTO.swift
//  HealthBar
//
//  Created by Claude on 6/21/26.
//

import Foundation

/// Data Transfer Object for one guild chat message (Guilds Prompt G3).
///
/// Firestore path: guilds/{guildCode}/messages/{msgId} (msgId = Firestore auto-id).
///
/// `id` is the document ID — NOT a stored field (the rules pin the body to
/// `[senderUid, senderUsername, senderDisplayName, text, createdAt]`), so it is
/// populated from `snapshot.documentID` on read (same approach as `GuildDTO`).
///
/// `createdAt` is OPTIONAL on purpose: a just-sent message fires the listener from
/// the local cache before the server resolves the timestamp; decoded with the
/// default `.none` behavior the pending sentinel comes back as `nil`, which the UI
/// renders as "sending…". A non-optional `Date` would make that local-echo doc
/// fail to decode and disappear until the server round-trip — the opposite of the
/// instant local echo we want. The write stamps `FieldValue.serverTimestamp()`
/// (in the service layer, via a dictionary), so this field is read-only here.
///
/// Identity (`senderUsername`/`senderDisplayName`) is a display-only snapshot
/// stamped by the sender; all logic keys on `senderUid`.
struct GuildMessageDTO: Codable, Identifiable {
    /// Firestore document ID (= msgId). Set on read; absent from the written body.
    var id: String? = nil
    var senderUid: String
    var senderUsername: String
    var senderDisplayName: String
    /// Preset avatar (D3b): the sender's icon/color id, a display-only identity snapshot
    /// stamped per message at send time (like `senderUsername`/`senderDisplayName`), never
    /// rewritten. Optional so pre-D3b messages decode nil ⇒ initials fallback in the non-own
    /// chat bubble. Written to the manual send dict ONLY when non-nil.
    var senderAvatarIcon: String? = nil
    var senderAvatarColor: String? = nil
    var text: String
    /// Server time; `nil` while the write is still pending (drives "sending…").
    var createdAt: Date?
}
