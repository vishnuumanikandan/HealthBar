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

    /// Preset avatar (D3b): the friend's icon id + color id, a display-only identity
    /// snapshot stamped at accept time — like `friendUsername`/`friendDisplayName`.
    ///
    /// NO BACKFILL: these are written only when the friend edge is CREATED (the accept
    /// batch), never rewritten when the counterparty later changes avatars. A friendship
    /// formed BEFORE D3b has no avatar keys on its edge docs → decodes nil → renders
    /// initials permanently (the friends-list row + the `.friend` challenge candidate both
    /// read this snapshot). Written to the manual accept dict ONLY when non-nil.
    var friendAvatarIcon: String? = nil
    var friendAvatarColor: String? = nil

    /// Firestore document ID — always the friend's uid.
    var id: String { friendUid }
}
