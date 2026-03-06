//
//  StreakMilestone.swift
//  HealthBar
//
//  Created by Claude on 2/2/26.
//

import Foundation

/// Represents streak milestone thresholds for bonus XP rewards
///
/// Users earn bonus XP when they reach these milestones.
/// Each milestone can only be claimed once (tracked in UserProgress).
enum StreakMilestone: Int, CaseIterable, Codable {
    case week = 7
    case month = 30
    case century = 100

    /// Bonus XP awarded for reaching this milestone
    var bonusXP: Int {
        switch self {
        case .week: return 50
        case .month: return 200
        case .century: return 500
        }
    }

    /// Title displayed in the celebration toast
    var title: String {
        switch self {
        case .week: return "7 Day Streak!"
        case .month: return "30 Day Warrior!"
        case .century: return "Century Champion!"
        }
    }

    /// Celebration message displayed below the title
    var message: String {
        switch self {
        case .week:
            return "You've been consistent for a full week. Keep it up!"
        case .month:
            return "A whole month of dedication. You're unstoppable!"
        case .century:
            return "100 days! You've achieved legendary status."
        }
    }

    /// Returns the next unclaimed milestone for a given streak
    /// - Parameters:
    ///   - streak: Current streak count
    ///   - claimedMilestones: Set of already claimed milestone raw values
    /// - Returns: The next milestone to claim, or nil if none available
    static func nextUnclaimedMilestone(for streak: Int, claimedMilestones: Set<Int>) -> StreakMilestone? {
        for milestone in StreakMilestone.allCases {
            if streak >= milestone.rawValue && !claimedMilestones.contains(milestone.rawValue) {
                return milestone
            }
        }
        return nil
    }
}
