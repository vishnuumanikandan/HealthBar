//
//  FriendError.swift
//  HealthBar
//
//  Created by Claude on 6/9/26.
//

import Foundation

/// Errors surfaced by the friend-request flow (Friend System Phase 2).
/// Mirrors the UsernameError pattern from Phase 1.
enum FriendError: LocalizedError {
    case userNotFound
    case cannotFriendSelf
    case alreadyFriends
    case incomingExists
    /// UGC-1b (D8): the recipient has blocked me (or I them). Surfaced when a well-formed
    /// friend-request create is denied by the rules' blockedEither() guard. Copy is
    /// deliberately soft — block state is never disclosed.
    case blocked
    case network(String)

    var errorDescription: String? {
        switch self {
        case .userNotFound:    return "No user with that username was found."
        case .cannotFriendSelf: return "You can't add yourself as a friend."
        case .alreadyFriends:  return "You're already friends with this user."
        case .incomingExists:  return "They already sent you a request — accept it instead."
        case .blocked:         return "You can't send requests to this player."
        case .network(let m):  return "Couldn't reach the server. Try again. (\(m))"
        }
    }
}
