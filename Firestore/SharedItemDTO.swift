//
//  SharedItemDTO.swift
//  HealthBar
//
//  Created by Claude on 6/12/26.
//

import FirebaseFirestore
import Foundation

/// Data Transfer Object for a meal/recipe share delivered into a friend's inbox
/// (Friend System Phase 9).
///
/// Firestore path: users/{recipientUid}/sharedItems/{shareId}
///
/// `shareId` is a fresh UUID per send — re-sharing the same meal twice is two
/// shares (intentional resends; no dedupe). The doc ID is read back via
/// `@DocumentID` (never an encoded field), so the written body matches the
/// rules' `hasOnly` set exactly.
///
/// SNAPSHOT, not reference: the share embeds the content JSON the SavedMeal/
/// SavedRecipe DTOs already produce (`componentsJSON`/`ingredientsJSON`). A
/// later edit by the sender does not affect delivered shares. Photos never
/// travel (the source DTOs already exclude `photoData`). The sender stamps
/// their own identity; the recipient never reads the sender's private data.
///
/// `createdAt` uses @ServerTimestamp: written as the server sentinel, decoded
/// as the resolved Date.
struct SharedItemDTO: Codable, Identifiable {
    /// Firestore document ID (= shareId). Populated on read, omitted on write.
    @DocumentID var id: String?

    var fromUid: String
    var fromUsername: String
    var fromDisplayName: String

    /// "meal" or "recipe".
    var kind: String

    /// The meal/recipe name.
    var name: String

    /// `componentsJSON` (meal) or `ingredientsJSON` (recipe) — the
    /// `[SavedMealComponent]` JSON both source DTOs already produce.
    var contentJSON: String

    /// Recipe servings; 1 for meals (ignored on meal import).
    var yield: Int

    /// Recipe purity 0–100; 0 for meals (ignored on meal import).
    var purityScore: Int

    @ServerTimestamp var createdAt: Date?

    /// Display name to show for the sender — display name when present, else handle.
    var senderName: String {
        fromDisplayName.isEmpty ? "@\(fromUsername)" : fromDisplayName
    }
}

// MARK: - Memberwise inits for the source DTOs (import path)
//
// SavedMealDTO / SavedRecipeDTO declare a custom `init(from:)`, which suppresses
// the synthesized memberwise initializer. Import needs to build one with a FRESH
// id (never the sender's), so these extension inits provide the field-wise
// constructor WITHOUT modifying the DTO files themselves. The import then flows
// through the existing `toSavedMeal(userId:)` / `addSavedMeal(_:)` pipeline.

extension SavedMealDTO {
    init(id: String, name: String, componentsJSON: String, createdAt: Date) {
        self.id = id
        self.name = name
        self.componentsJSON = componentsJSON
        self.createdAt = createdAt
    }
}

extension SavedRecipeDTO {
    init(id: String, name: String, yield: Int, ingredientsJSON: String, purityScore: Int, createdAt: Date) {
        self.id = id
        self.name = name
        self.yield = yield
        self.ingredientsJSON = ingredientsJSON
        self.purityScore = purityScore
        self.createdAt = createdAt
    }
}
