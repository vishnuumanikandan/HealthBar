//
//  FriendDTO.swift
//  HealthBar
//
//  Created by Claude on 6/9/26.
//

import Foundation

/// Data Transfer Object for a friend edge via Firestore.
///
/// Firestore path: users/{ownerUid}/friends/{friendUid}
/// The document ID is the friend's uid — one document per friend per user.
///
/// `friendUsername`/`friendDisplayName` are denormalized snapshots of the
/// counterparty's identity at accept time. A later display-name change does
/// not propagate to existing friend documents.
///
/// The document body contains exactly the four fields below (enforced by
/// security rules via `hasOnly`); the id is the document ID, not a field.
struct FriendDTO: Codable {
    var friendUid: String
    var friendUsername: String
    var friendDisplayName: String
    var since: Date

    /// Firestore document ID — always the friend's uid.
    var id: String { friendUid }
}
