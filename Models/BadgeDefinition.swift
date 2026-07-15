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
    // D0-interim: SF Symbols pending custom emblem artwork (workstream D)
    let symbolName: String
    let title: String
    let description: String

    // MARK: - Static Definitions

    static let all: [BadgeDefinition] = [
        BadgeDefinition(
            id: "first_flame",
            symbolName: "flame.fill",
            title: "First Flame",
            description: "Log your first meal"
        ),
        BadgeDefinition(
            id: "week_warrior",
            symbolName: "calendar",
            title: "Week Warrior",
            description: "Reach a 7-day streak"
        ),
        BadgeDefinition(
            id: "month_legend",
            symbolName: "dumbbell.fill",
            title: "Month Legend",
            description: "Reach a 30-day streak"
        ),
        BadgeDefinition(
            id: "century",
            symbolName: "fork.knife",
            title: "Century",
            description: "Log 100 meals total"
        ),
        BadgeDefinition(
            id: "goal_getter",
            symbolName: "target",
            title: "Goal Getter",
            description: "Complete all daily quests in one day"
        ),
        BadgeDefinition(
            id: "level_up",
            symbolName: "bolt.fill",
            title: "Level Up",
            description: "Reach level 5"
        ),
    ]

    /// Looks up a definition by id. Returns nil if no matching definition exists.
    static func find(id: String) -> BadgeDefinition? {
        all.first { $0.id == id }
    }
}
