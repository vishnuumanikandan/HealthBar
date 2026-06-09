//
//  BadgeDefinition.swift
//  HealthBar
//
//  Created by Claude on 4/8/26.
//

import Foundation

/// Static definition for a badge. Not persisted — definitions live in code only.
/// BadgeProgress (@Model) tracks unlock state per user.
struct BadgeDefinition: Identifiable, Equatable {
    let id: String
    let emoji: String
    let title: String
    let description: String

    // MARK: - Static Definitions

    static let all: [BadgeDefinition] = [
        BadgeDefinition(
            id: "first_flame",
            emoji: "🔥",
            title: "First Flame",
            description: "Log your first meal"
        ),
        BadgeDefinition(
            id: "week_warrior",
            emoji: "📅",
            title: "Week Warrior",
            description: "Reach a 7-day streak"
        ),
        BadgeDefinition(
            id: "month_legend",
            emoji: "💪",
            title: "Month Legend",
            description: "Reach a 30-day streak"
        ),
        BadgeDefinition(
            id: "century",
            emoji: "🍽️",
            title: "Century",
            description: "Log 100 meals total"
        ),
        BadgeDefinition(
            id: "goal_getter",
            emoji: "🎯",
            title: "Goal Getter",
            description: "Complete all daily quests in one day"
        ),
        BadgeDefinition(
            id: "level_up",
            emoji: "⚡",
            title: "Level Up",
            description: "Reach level 5"
        ),
    ]

    /// Looks up a definition by id. Returns nil if no matching definition exists.
    static func find(id: String) -> BadgeDefinition? {
        all.first { $0.id == id }
    }
}
