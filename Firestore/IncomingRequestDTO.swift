//
//  IncomingRequestDTO.swift
//  HealthBar
//
//  Created by Claude on 6/9/26.
//

import Foundation

/// Data Transfer Object for an incoming friend request via Firestore.
///
/// Firestore path: users/{toUid}/friendRequests/{fromUid}
/// The document ID is the sender's uid — one pending request per sender.
///
/// The sender stamps its own identity (`fromUsername`/`fromDisplayName`) at
/// send time, so the recipient never reads the sender's private account data.
///
/// The document body contains exactly the four fields below (enforced by
/// security rules via `hasOnly`); the id is the document ID, not a field.
struct IncomingRequestDTO: Codable {
    var fromUid: String
    var fromUsername: String
    var fromDisplayName: String
    var createdAt: Date

    /// Firestore document ID — always the sender's uid.
    var id: String { fromUid }
}
