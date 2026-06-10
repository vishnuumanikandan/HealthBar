//
//  SentRequestDTO.swift
//  HealthBar
//
//  Created by Claude on 6/9/26.
//

import Foundation

/// Data Transfer Object for the sender's mirror of an outgoing friend request.
///
/// Firestore path: users/{fromUid}/sentRequests/{toUid}
/// The document ID is the recipient's uid — one pending request per recipient.
///
/// Stores only the recipient's `@username` (which the sender searched) — the
/// sender does not know the recipient's display name (no cross-user read).
///
/// The document body contains exactly the three fields below (enforced by
/// security rules via `hasOnly`); the id is the document ID, not a field.
struct SentRequestDTO: Codable {
    var toUid: String
    var toUsername: String
    var createdAt: Date

    /// Firestore document ID — always the recipient's uid.
    var id: String { toUid }
}
