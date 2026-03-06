//
//  Rank.swift
//  HealthBar
//
//  Created by Claude on 1/19/26.
//

import Foundation

/// Represents user rank tiers based on total XP earned
///
/// Ranks are identity signals and motivational milestones, not skill gates.
/// Each rank has an associated XP threshold required to achieve it.
enum Rank: String, Codable, CaseIterable {
    case iron = "iron"
    case bronze = "bronze"
    case silver = "silver"
    case gold = "gold"
    case diamond = "diamond"

    /// XP threshold required to achieve this rank
    var xpThreshold: Int {
        switch self {
        case .iron:
            return 0
        case .bronze:
            return 500
        case .silver:
            return 1500
        case .gold:
            return 3500
        case .diamond:
            return 7500
        }
    }

    /// Calculates the appropriate rank based on total XP
    /// - Parameter totalXP: User's total lifetime XP
    /// - Returns: The highest rank the user has achieved
    static func getRank(from totalXP: Int) -> Rank {
        // Iterate through ranks in reverse order (highest to lowest)
        // Return the first rank whose threshold is met
        for rank in Rank.allCases.reversed() {
            if totalXP >= rank.xpThreshold {
                return rank
            }
        }

        // Fallback to iron (should never reach here due to iron = 0)
        return .iron
    }

    /// Display name for the rank (capitalized)
    var displayName: String {
        return self.rawValue.capitalized
    }
}
