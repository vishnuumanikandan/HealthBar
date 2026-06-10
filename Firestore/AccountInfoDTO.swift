//
//  AccountInfoDTO.swift
//  HealthBar
//
//  Created by Claude on 4/8/26.
//

import Foundation

/// Data Transfer Object for the account/info Firestore document.
///
/// Written at sign-up and updated in AccountView when the user changes their
/// display name or email. Read on login to sync displayName into UserProfile.
///
/// Firestore path: users/{userId}/account/info (fixed document ID "info")
struct AccountInfoDTO: Codable {
    var displayName: String
    var username: String?
    var email: String
    var createdAt: Date
    var lastUsernameChangeAt: Date?
    var lastDisplayNameChangeAt: Date?
}
