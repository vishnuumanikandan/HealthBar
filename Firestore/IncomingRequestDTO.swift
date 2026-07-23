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

    /// Preset avatar (D3b): the sender's icon id + color id, stamped from the sender's
    /// local profile at send time — a display-only identity snapshot, exactly like
    /// `fromUsername`/`fromDisplayName`. Optional so pre-D3b requests still decode; nil ⇒
    /// initials fallback at every render. Written to the manual send dict ONLY when non-nil.
    var fromAvatarIcon: String? = nil
    var fromAvatarColor: String? = nil

    /// Firestore document ID — always the sender's uid.
    var id: String { fromUid }
}
