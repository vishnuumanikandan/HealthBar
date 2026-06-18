//
//  CheerDTO.swift
//  HealthBar
//
//  Created by Claude on 6/12/26.
//

import FirebaseFirestore
import Foundation

/// Data Transfer Object for a single cheer (💪) on a friend's feed event
/// (Friend System Phase 8).
///
/// Firestore path: users/{ownerUid}/feedEvents/{eventId}/cheers/{cheererUid}
///
/// The document ID is the cheerer's uid ⇒ one cheer per person per event,
/// idempotent by construction (same trick as friend requests). `id` is a
/// COMPUTED property (= cheererUid), never an encoded field, so the written
/// payload matches the rules' `hasOnly` set exactly.
///
/// Cross-user write, zero cross-user private reads: the cheerer stamps their
/// own identity snapshot. `username`/`displayName` are display-only — logic
/// keys on `cheererUid`, never the snapshots.
///
/// `createdAt` uses @ServerTimestamp: written as the server sentinel (the
/// client never stamps its own time) and decoded as the resolved Date.
struct CheerDTO: Codable {
    var cheererUid: String
    var username: String
    var displayName: String
    @ServerTimestamp var createdAt: Date?

    /// Firestore document ID — always the cheerer's uid.
    var id: String { cheererUid }
}
