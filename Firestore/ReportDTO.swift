//
//  ReportDTO.swift
//  HealthBar
//
//  Created by Claude on 7/15/26.
//

import FirebaseFirestore
import Foundation

/// The kind of content a report targets (UGC-1a). The `rawValue` is what travels
/// on the wire in `ReportDTO.contextType`; the reports rules pin it to this set.
enum ReportContext: String, Codable {
    case chatMessage = "chat_message"
    case userProfile = "user_profile"
    case guild       = "guild"
}

/// Data Transfer Object for a user-submitted moderation report (UGC-1a).
///
/// Firestore path: `reports/{reportId}` — a top-level, write-only mailbox owned
/// by NEITHER party (precedent: `duels`, narrowed to create-only). It cannot live
/// under the reporter (reporter-owned deletable evidence) nor the reported user
/// (visible to them). Clients may only CREATE; the operator reads via the console.
///
/// `reportId` is DETERMINISTIC per (reporter, target) so a duplicate report
/// collides on the same doc — and since the rules are create-only, the duplicate
/// is rejected as an update, which DataManager treats as silent idempotent success
/// ("already reported"). See D6.
///
/// `createdAt` uses @ServerTimestamp: written as the server sentinel (included in
/// the rules' `hasOnly` set, not type-checked — serverTimestamp precedent). The
/// optional `guildCode`/`messageId` omit when nil (synthesized `encodeIfPresent`),
/// so the written key set is always a subset of the allowed set.
struct ReportDTO: Codable {
    /// The reporter's uid (== request.auth.uid, enforced by rules).
    let reporterUid: String
    /// The reported user's uid. For `.guild` reports this is the guild's ownerUid.
    let reportedUid: String
    /// `ReportContext.rawValue` — the string form on the wire.
    let contextType: String
    /// The offending text, trimmed then truncated to `maxReportSnapshotLength`
    /// (composed and clamped in DataManager, the single site).
    let contentSnapshot: String
    /// Present for `.guild` and `.chatMessage` reports.
    let guildCode: String?
    /// Present for `.chatMessage` reports.
    let messageId: String?
    @ServerTimestamp var createdAt: Date?
}
