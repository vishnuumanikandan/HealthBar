//
//  FeedEventDTO.swift
//  HealthBar
//
//  Created by Claude on 6/11/26.
//

import FirebaseFirestore
import Foundation

/// Data Transfer Object for a friend activity-feed milestone event (Friend
/// System Phase 7).
///
/// Firestore path: users/{ownerUid}/feedEvents/{eventId}
///
/// The document ID is DETERMINISTIC — `"<type>_<value>"` (e.g. `level_12`,
/// `badge_first_flame`, `rank_gold`, `streak_30`). Re-emitting the same
/// milestone collides on the same ID, so emission is idempotent (overwrite /
/// rejected-as-update, never a duplicate). `id` is therefore a COMPUTED
/// property derived from the body fields — never an encoded field — so the
/// written payload matches the rules' `hasOnly` set exactly (same pattern as
/// FriendDTO / IncomingRequestDTO).
///
/// Owner-computed, owner-published; friend-gated reads. The `username`/
/// `displayName` snapshots are display decoration only — identity is the
/// `ownerUid` from the path, never these strings.
///
/// `createdAt` uses @ServerTimestamp: written as the server sentinel (the
/// client never stamps its own time — avoids clock skew in ordering) and
/// decoded as the server-resolved Date.
struct FeedEventDTO: Codable {
    var type: String
    var value: String
    var username: String
    var displayName: String
    @ServerTimestamp var createdAt: Date?

    /// Firestore document ID — deterministic `"<type>_<value>"`.
    var id: String { "\(type)_\(value)" }
}

/// Client-side resolution of a feed event's `type`+`value` to display text and
/// an SF Symbol name (Friend System Phase 7+). Shared by `FeedItem` (friends'
/// feed) and `OwnEventItem` (the owner's receipts strip) so the two never diverge.
///
/// `text` returns nil when the event no longer resolves (a removed badge/rank
/// id), which callers use to drop it. Never crashes.
enum FeedEventDisplay {
    static func text(type: String, value: String) -> String? {
        switch type {
        case "badge":
            guard let def = BadgeDefinition.find(id: value) else { return nil }
            return "earned \(def.title)"
        case "level":
            return "reached Level \(value)"
        case "rank":
            guard let rank = Rank(rawValue: value) else { return nil }
            return "ranked up to \(rank.displayName)"
        case "streak":
            return "hit a \(value)-day streak"
        default:
            return nil
        }
    }

    static func symbolName(type: String, value: String) -> String {
        switch type {
        case "badge": return "medal.fill"
        case "level": return "star.fill"
        case "rank": return "shield.fill"
        case "streak": return "flame.fill"
        default: return "sparkles"
        }
    }
}

/// One merged, display-ready feed row: a friend's published event tagged with
/// the friend's uid (the subcollection it came from). Plain in-memory value —
/// never persisted, mirroring the leaderboard's fetch-on-view model.
///
/// `friendUid` is the identity key (e.g. for opening the profile); the name
/// snapshots are decoration. `resolvedText` resolves `type`+`value` to display
/// text locally — returning nil for events that no longer resolve (a removed
/// badge or rank), which the feed assembly drops.
struct FeedItem: Identifiable {
    let friendUid: String
    let eventId: String
    let type: String
    let value: String
    let username: String
    let displayName: String
    let createdAt: Date

    // Cheers (Phase 8) — populated by the cheer fan-out after the item is built
    // (and mutated in-memory by the UI after a successful cheer/uncheer write).
    // Default to a cheer-less item so existing construction sites compile.
    var cheerCount: Int = 0
    var didCheer: Bool = false
    var recentCheererNames: [String] = []

    /// Unique across the merged feed: two friends can each have a `level_12`
    /// event, so the row identity (and the per-row cheer in-flight flag) must
    /// include the friend.
    var id: String { "\(friendUid)_\(eventId)" }

    init(dto: FeedEventDTO, friendUid: String) {
        self.friendUid = friendUid
        self.eventId = dto.id
        self.type = dto.type
        self.value = dto.value
        self.username = dto.username
        self.displayName = dto.displayName
        self.createdAt = dto.createdAt ?? .distantPast
    }

    /// The name to show — display name when present, else the @handle.
    var name: String {
        displayName.isEmpty ? "@\(username)" : displayName
    }

    /// Client-side display resolution. nil ⇒ the event no longer resolves
    /// (unknown badge/rank id) and the feed drops it.
    var resolvedText: String? { FeedEventDisplay.text(type: type, value: value) }

    /// A type-appropriate SF Symbol name for the row's leading badge.
    var symbolName: String { FeedEventDisplay.symbolName(type: type, value: value) }
}

/// One of the owner's OWN recent events, for the "Your milestones" receipts
/// strip (Friend System Phase 8) — resolved display fields plus the cheers it
/// has received. Plain in-memory value; no cheer button (self-cheer is
/// impossible). Keys on `eventId` alone — every event here belongs to one user,
/// so deterministic ids never collide within the strip.
struct OwnEventItem: Identifiable {
    let eventId: String
    let type: String
    let value: String
    let createdAt: Date
    let cheerCount: Int
    let recentCheererNames: [String]

    var id: String { eventId }

    var resolvedText: String? { FeedEventDisplay.text(type: type, value: value) }
    var symbolName: String { FeedEventDisplay.symbolName(type: type, value: value) }
}
