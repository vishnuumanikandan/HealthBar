//
//  FriendRequest.swift
//  HealthBar
//
//  Created by Claude on 6/9/26.
//

import Foundation
import SwiftData

/// Local cache of a pending friend request, mirrored from Firestore.
///
/// One model holds both directions:
/// - `direction == "incoming"` — mirrored from `users/{userId}/friendRequests/{otherUid}`;
///   `displayName` carries the sender's identity snapshot.
/// - `direction == "outgoing"` — mirrored from `users/{userId}/sentRequests/{otherUid}`;
///   `displayName` is nil (the sender never reads the recipient's account data).
///
/// **Written only by the snapshot listeners' reconcile** in DataManager — never
/// optimistically. Each listener's reconcile MUST filter by `userId` AND its own
/// `direction` so the incoming listener never deletes outgoing rows and vice-versa.
///
/// Uniqueness key: (userId, otherUid, direction), enforced by the reconcile upsert.
@Model
final class FriendRequest {

    // MARK: - Identity

    /// Firebase UID of the owning user (me). Defaults to "legacy" for lightweight migration.
    var userId: String = "legacy"

    /// Firebase UID of the counterparty (sender for incoming, recipient for outgoing).
    var otherUid: String = ""

    /// Either "incoming" or "outgoing".
    var direction: String = "incoming"

    // MARK: - Snapshot

    /// The counterparty's username (sender's for incoming, searched handle for outgoing).
    var username: String = ""

    /// The counterparty's display name. Nil for outgoing requests.
    var displayName: String? = nil

    /// When the request was created (server time).
    var createdAt: Date = Date.distantPast

    // MARK: - Init

    init(userId: String, otherUid: String, direction: String, username: String, displayName: String?, createdAt: Date) {
        self.userId = userId
        self.otherUid = otherUid
        self.direction = direction
        self.username = username
        self.displayName = displayName
        self.createdAt = createdAt
    }
}
