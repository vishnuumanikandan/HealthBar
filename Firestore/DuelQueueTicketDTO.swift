//
//  DuelQueueTicketDTO.swift
//  HealthBar
//
//  Created by Claude on 7/4/26.
//

import Foundation

/// Data Transfer Object for a top-level `duelQueue/{uid}` document (D2 — matchmaking).
///
/// Doc-id-as-lock (one ticket per user; the `guildMemberships` precedent). A ticket is a
/// shared/locking object: it must be discoverable by strangers and claimable cross-user,
/// neither of which fits under `users/{uid}/`. Tickets are readable by any authenticated
/// user (open matchmaking) and ephemeral (≤10 min TTL).
///
/// Following the guild/duel convention for shared top-level collections, this is a plain
/// Codable value type: `id` is the Firestore document ID (= owner uid; set from
/// `documentID` on read, never encoded into the body), and server timestamps
/// (`createdAt`/`claimedAt`) are written as `FieldValue.serverTimestamp()` by the service
/// layer — NOT via a `@ServerTimestamp` wrapper, because the create rule pins the document
/// to an exact field set and a wrapper would write an extra sentinel key on create.
///
/// The claim (`claimedBy`/`claimedAt`/`matchedDuelId`) is written cross-user by the claimer
/// inside the same transaction that creates the matchmade duel and deletes the claimer's own
/// ticket. The claimed ticket then doubles as the waiting player's match notification (they
/// poll their own ticket, see `claimedBy`, fetch the duel, delete their ticket).
struct DuelQueueTicketDTO: Codable, Identifiable, Equatable {
    /// Firestore document ID (= owner uid). Set from `snapshot.documentID` on read;
    /// never written into the body.
    var id: String?

    /// Owner uid (== doc id). The sole identity key.
    var uid: String

    // Display snapshots (display-only; all logic keys on uid).
    var username: String
    var displayName: String

    /// RR snapshot at enqueue (self-reported, same posture as every published stat; the
    /// rules bound it to a sane range).
    var rr: Int

    /// League duration in days — one of `DuelConstants.leagues`.
    var league: Int

    /// Server-written enqueue time. Optional so a just-created (still-pending sentinel)
    /// value decodes as nil rather than throwing.
    var createdAt: Date?

    /// Client-computed `now + DuelConstants.queueTicketTTL` — the lazy-TTL cutoff (rules
    /// can't do timestamp arithmetic, so the client writes it).
    var expiresAt: Date

    /// `""` = unclaimed (empty-string sentinel — Firestore cannot query a MISSING field,
    /// so this is NEVER optional). Set to the claimer's uid by the claim transaction.
    var claimedBy: String

    /// Server timestamp set by the claimer alongside `claimedBy`. Absent while unclaimed.
    var claimedAt: Date?

    /// The duel id the claimer created. Set alongside `claimedBy`. Absent while unclaimed.
    var matchedDuelId: String?

    // MARK: - Convenience (client-side)

    /// True once a searcher has claimed this ticket (I am the waiting side of a match).
    var isClaimed: Bool { !claimedBy.isEmpty }

    /// True when this ticket is past its TTL cutoff (skipped by searchers, lazily deletable).
    var isExpiredNow: Bool { Date() > expiresAt }
}
