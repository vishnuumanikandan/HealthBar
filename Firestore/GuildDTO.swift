//
//  GuildDTO.swift
//  HealthBar
//
//  Created by Claude on 6/18/26.
//

import Foundation

/// Data Transfer Objects for guilds (Guilds Prompt G1).
///
/// A guild is the app's first shared entity not owned by a single user. It lives
/// in the top-level `guilds/{guildCode}` collection (NOT under `users/{uid}/`),
/// with two subcollections — `members` and `joinRequests` — and a separate
/// top-level one-guild lock at `guildMemberships/{uid}`.
///
/// All four DTOs are plain Codable value types in the existing style. Identity
/// fields (`username`/`displayName`) are denormalized, display-only snapshots
/// stamped by the writer; all logic keys on uids. `createdAt`/`joinedAt` are
/// written with the server-timestamp sentinel and decoded with `.estimate` so a
/// just-written (still-pending) value still decodes.

/// Guild-wide constants (R7d).
enum GuildConstants {
    /// Cap on the browsable directory fetch. The query is unpaginated (the known
    /// directory-reads debt class); beyond this, guilds are silently truncated and
    /// only the fetched set is searchable.
    static let directoryFetchCap = 100
}

/// A guild document at `guilds/{guildCode}`.
///
/// `id` is the Firestore document ID (= the shareable guild code). It is NOT a
/// stored field — the security rules pin the guild body to exactly
/// `[name, ownerUid, joinPolicy, description, createdAt, memberCount]` — so it is
/// populated from `snapshot.documentID` on read and never encoded into the document.
struct GuildDTO: Codable {
    /// The guild code (Firestore document ID). Set on read, absent in the body.
    var id: String?
    var name: String
    var ownerUid: String
    /// `"open"`, `"request"`, or `"private"` (R7d).
    ///
    /// `open` and `request` are listed in the browsable directory; `private` is
    /// hidden from it (enforced by the rules' `list` clause, not just the client)
    /// and joins by code exactly like an `open` guild.
    var joinPolicy: String
    var description: String?
    var createdAt: Date
    /// Live roster size, maintained atomically by every membership batch
    /// (GUILD-CAP-1). The rules enforce the hard cap against this field.
    ///
    /// `nil` means a pre-backfill LEGACY doc that predates this field — readers
    /// MUST treat nil as UNKNOWN (fall through to server enforcement), NEVER as 0.
    /// Backfilled by `scripts/backfill-member-count.js`.
    var memberCount: Int?
}

/// The one-guild lock at `guildMemberships/{uid}` (uid == document ID).
///
/// This is the authoritative "this user is in exactly one guild" record and the
/// O(1) "my guild" lookup. Because the document ID is the uid, a user physically
/// cannot hold two — a second create is rejected by the create-only rule. Written
/// and deleted in the SAME batch as the member document on every join/leave.
struct GuildMembershipDTO: Codable {
    var uid: String
    var guildCode: String
    /// `"owner"` or `"member"`.
    var role: String
    var joinedAt: Date

    /// Firestore document ID — always the member's uid.
    var id: String { uid }
}

/// A roster entry at `guilds/{guildCode}/members/{uid}` (uid == document ID).
struct GuildMemberDTO: Codable {
    var uid: String
    var username: String
    var displayName: String
    /// `"owner"` or `"member"`.
    var role: String
    var joinedAt: Date

    /// Firestore document ID — always the member's uid.
    var id: String { uid }
}

/// A pending join request at `guilds/{guildCode}/joinRequests/{uid}` (uid == document ID).
struct GuildJoinRequestDTO: Codable {
    var uid: String
    var username: String
    var displayName: String
    var createdAt: Date

    /// Firestore document ID — always the requester's uid.
    var id: String { uid }
}
