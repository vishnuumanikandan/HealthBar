//
//  FeedbackDTO.swift
//  HealthBar
//
//  Created by Claude on 7/25/26.
//

import Foundation

/// Client-mirrored bounds for in-app feedback (FEEDBACK-1). `maxLength` is the
/// SAME 1…2000-char limit the firestore.rules feedback block pins
/// (`message.size() <= 2000`) — the two MUST move together. `counterThreshold`
/// is a UI affordance only: the live "N / 2000" counter appears once the draft
/// grows past it.
enum FeedbackLimits {
    /// Maximum feedback length. Mirrors the rules' `message.size() <= 2000`.
    static let maxLength = 2000
    /// The draft length past which the compose view reveals the live counter.
    static let counterThreshold = 1800
}

/// Data Transfer Object for a user-submitted piece of feedback (FEEDBACK-1).
///
/// Firestore path: `users/{uid}/feedback/{autoId}` — a private, create-only
/// drop-box. The owner may only CREATE (no client reads/updates/deletes); the
/// developer reads the collection via admin console collection-group queries.
/// There is zero cross-user surface and nothing in the app ever reads it.
///
/// Plain Codable: `createdAt` is a client-stamped `Date` (encodes to a Firestore
/// timestamp, which the create rule type-checks — deliberately NOT a
/// `@ServerTimestamp` sentinel), and the struct writes EXACTLY the four keys the
/// rule's `keys().hasOnly([...])` allows. DataManager owns validation + stamping;
/// the service writes it with an auto-id via `addDocument`.
struct FeedbackDTO: Codable {
    /// The feedback text, trimmed and length-validated (1…2000) in DataManager.
    let message: String
    /// Client-stamped submission time. Encodes to a Firestore timestamp.
    let createdAt: Date
    /// `CFBundleShortVersionString` at submit time, or "unknown".
    let appVersion: String
    /// Platform literal — "ios" for now.
    let platform: String
}
