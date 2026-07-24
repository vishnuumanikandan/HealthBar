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
    let title: String
    let description: String

    // MARK: - Static Definitions

    static let all: [BadgeDefinition] = [
        BadgeDefinition(
            id: "first_flame",
            title: "First Flame",
            description: "Log your first meal"
        ),
        BadgeDefinition(
            id: "week_warrior",
            title: "Week Warrior",
            description: "Reach a 7-day streak"
        ),
        BadgeDefinition(
            id: "month_legend",
            title: "Month Legend",
            description: "Reach a 30-day streak"
        ),
        BadgeDefinition(
            id: "century",
            title: "Century",
            description: "Log 100 meals total"
        ),
        BadgeDefinition(
            id: "goal_getter",
            title: "Goal Getter",
            description: "Complete all daily quests in one day"
        ),
        BadgeDefinition(
            id: "level_up",
            title: "Level Up",
            description: "Reach level 5"
        ),
        BadgeDefinition(
            id: "tutorial_complete",
            title: "Tutorial Complete",
            description: "Complete all six first quests"
        ),
    ]

    /// Looks up a definition by id. Returns nil if no matching definition exists.
    static func find(id: String) -> BadgeDefinition? {
        all.first { $0.id == id }
    }
}
