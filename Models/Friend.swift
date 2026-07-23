//
//  Friend.swift
//  HealthBar
//
//  Created by Claude on 6/9/26.
//

import Foundation
import SwiftData

/// Local cache of a friend edge, mirrored from Firestore.
///
/// One record per (userId, friendUid) pair. Synced from
/// `users/{userId}/friends/{friendUid}` — **written only by the snapshot
/// listener's reconcile** in DataManager. Never inserted, updated, or deleted
/// optimistically by mutation paths.
///
/// `username`/`displayName` are denormalized snapshots of the friend's
/// identity at accept time and may lag a later rename (acceptable).
///
/// Uniqueness is enforced in DataManager's reconcile: it upserts by
/// (userId, friendUid) and never inserts a duplicate.
@Model
final class Friend {

    // MARK: - Identity

    /// Firebase UID of the owning user (me). Defaults to "legacy" for lightweight migration.
    var userId: String = "legacy"

    /// Firebase UID of the friend.
    var friendUid: String = ""

    // MARK: - Snapshot

    /// The friend's username at accept time.
    var username: String = ""

    /// The friend's display name at accept time.
    var displayName: String = ""

    /// The friend's preset avatar (D3b): icon id + color id, a display-only snapshot mirrored
    /// from `FriendDTO.friendAvatarIcon/Color` by the reconcile. Optional + inline nil default =
    /// lightweight SwiftData migration; nil (pre-D3b edge, or no avatar chosen) ⇒ initials at the
    /// friends-list row and the `.friend` challenge candidate. NEVER backfilled — an accept-time
    /// snapshot, so a friend's later avatar change does not propagate to an existing edge.
    var avatarIcon: String? = nil
    var avatarColor: String? = nil

    /// When the friendship was created (server time).
    var since: Date = Date.distantPast

    // MARK: - Init

    init(userId: String, friendUid: String, username: String, displayName: String, since: Date,
         avatarIcon: String? = nil, avatarColor: String? = nil) {
        self.userId = userId
        self.friendUid = friendUid
        self.username = username
        self.displayName = displayName
        self.avatarIcon = avatarIcon
        self.avatarColor = avatarColor
        self.since = since
    }
}
