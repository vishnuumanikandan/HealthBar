//
//  UserProfileDTO.swift
//  HealthBar
//
//  Created by Claude on 3/31/26.
//

import Foundation

/// Data Transfer Object for UserProfile cloud sync via Firestore.
///
/// Plain Codable struct with zero SwiftData dependencies.
/// Mirrors every persisted field of the UserProfile @Model except:
///   - `userId` — encoded in the Firestore path (users/{userId}/profile/userProfile), not the body
///   - `id` — not stored in Firestore (single document per user, path is the key)
///
/// Firestore path: users/{userId}/profile/userProfile (fixed document ID "userProfile")
struct UserProfileDTO: Codable {

    // MARK: - Fields (mirrors UserProfile, minus userId and id)

    var displayName: String
    /// Preset avatar (D3a): icon id + color id. Optional so pre-D3a profile docs
    /// still decode; nil ⇒ initials fallback.
    var avatarIcon: String?
    var avatarColor: String?
    var sex: String
    var age: Int
    var weightKg: Double
    var heightCm: Double
    var goalWeightKg: Double
    var weeklyPaceLbs: Double
    var activityLevel: String
    var dietStyle: String
    var mealsPerDay: Int
    var allergies: [String]
    var sleepQuality: String
    var stressLevel: String
    var aiTip: String
    var setupCompleted: Bool
    var createdAt: Date
    var updatedAt: Date

    // MARK: - Conversion: UserProfile → UserProfileDTO

    init(from profile: UserProfile) {
        self.displayName = profile.displayName
        self.avatarIcon = profile.avatarIcon
        self.avatarColor = profile.avatarColor
        self.sex = profile.sex
        self.age = profile.age
        self.weightKg = profile.weightKg
        self.heightCm = profile.heightCm
        self.goalWeightKg = profile.goalWeightKg
        self.weeklyPaceLbs = profile.weeklyPaceLbs
        self.activityLevel = profile.activityLevel
        self.dietStyle = profile.dietStyle
        self.mealsPerDay = profile.mealsPerDay
        self.allergies = profile.allergies
        self.sleepQuality = profile.sleepQuality
        self.stressLevel = profile.stressLevel
        self.aiTip = profile.aiTip
        self.setupCompleted = profile.setupCompleted
        self.createdAt = profile.createdAt
        self.updatedAt = profile.updatedAt
    }

    // MARK: - Conversion: UserProfileDTO → UserProfile

    /// Creates a UserProfile SwiftData model from this DTO.
    /// - Parameter userId: The authenticated user's ID (stamped onto the new profile).
    func toUserProfile(userId: String) -> UserProfile {
        let profile = UserProfile(
            userId: userId,
            sex: sex,
            age: age,
            weightKg: weightKg,
            heightCm: heightCm,
            goalWeightKg: goalWeightKg,
            weeklyPaceLbs: weeklyPaceLbs,
            activityLevel: activityLevel,
            dietStyle: dietStyle,
            mealsPerDay: mealsPerDay,
            allergies: allergies,
            sleepQuality: sleepQuality,
            stressLevel: stressLevel,
            aiTip: aiTip,
            setupCompleted: setupCompleted,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        profile.displayName = displayName
        profile.avatarIcon = avatarIcon
        profile.avatarColor = avatarColor
        return profile
    }

    // MARK: - Diff Helper

    /// Returns true if any persisted field in this DTO differs from the given UserProfile.
    /// Used by syncUserProfileFromFirestore to avoid unnecessary SwiftData rewrites.
    func differsFrom(_ profile: UserProfile) -> Bool {
        return displayName != profile.displayName
            || avatarIcon != profile.avatarIcon
            || avatarColor != profile.avatarColor
            || sex != profile.sex
            || age != profile.age
            || weightKg != profile.weightKg
            || heightCm != profile.heightCm
            || goalWeightKg != profile.goalWeightKg
            || weeklyPaceLbs != profile.weeklyPaceLbs
            || activityLevel != profile.activityLevel
            || dietStyle != profile.dietStyle
            || mealsPerDay != profile.mealsPerDay
            || allergies != profile.allergies
            || sleepQuality != profile.sleepQuality
            || stressLevel != profile.stressLevel
            || aiTip != profile.aiTip
            || setupCompleted != profile.setupCompleted
    }
}
