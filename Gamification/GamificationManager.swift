//
//  GamificationManager.swift
//  HealthBar
//
//  Created by Claude on 1/19/26.
//

import Foundation

/// Handles all gamification logic: XP, levels, streaks, ranks, and quests
///
/// Responsible for calculating progression, managing streaks, generating quests,
/// and awarding XP. Does NOT interact with persistence directly.
@Observable
final class GamificationManager {

    // MARK: - Constants

    /// XP required per level (Level 1 = 0-99 XP, Level 2 = 100-199 XP, etc.)
    private let xpPerLevel = 100

    // MARK: - Initialization

    init() {}

    // MARK: - XP & Level Calculations

    /// Calculates current level from total XP
    /// - Parameter totalXP: User's total lifetime XP
    /// - Returns: Current level (starts at 1)
    func calculateLevel(from totalXP: Int) -> Int {
        return (totalXP / xpPerLevel) + 1
    }

    /// Calculates XP needed for the next level
    /// - Parameter totalXP: User's current total XP
    /// - Returns: XP needed to reach next level
    func xpForNextLevel(currentXP: Int) -> Int {
        let currentLevel = calculateLevel(from: currentXP)
        let nextLevelXP = currentLevel * xpPerLevel
        return nextLevelXP - currentXP
    }

    /// Calculates XP progress within current level
    /// - Parameter totalXP: User's total XP
    /// - Returns: Progress percentage (0.0 to 1.0)
    func levelProgress(totalXP: Int) -> Double {
        let xpInCurrentLevel = totalXP % xpPerLevel
        return Double(xpInCurrentLevel) / Double(xpPerLevel)
    }

    /// Adds XP to user progress and checks for level up
    /// - Parameters:
    ///   - amount: XP to add
    ///   - progress: UserProgress object (will be modified)
    /// - Returns: Tuple indicating if user leveled up and their new level
    func addXP(amount: Int, to progress: inout UserProgress) -> (didLevelUp: Bool, newLevel: Int) {
        let oldLevel = calculateLevel(from: progress.totalXP)
        progress.totalXP += amount

        let newLevel = calculateLevel(from: progress.totalXP)
        let didLevelUp = newLevel > oldLevel

        // XP drives level only. Rank is derived from `rr` (Rank.getRank(from: rr)) and is
        // never touched here — adding XP must never change rank (RR-0a invariant).

        return (didLevelUp: didLevelUp, newLevel: newLevel)
    }

    // MARK: - Rank Calculations

    /// Gets the current rank from the user's Ranked Rating.
    /// - Parameter rr: User's RR (rank derives from RR only, never from XP).
    /// - Returns: Current Rank
    func getCurrentRank(from rr: Int) -> Rank {
        return Rank.getRank(from: rr)
    }

    // NOTE: `xpForNextRank` was removed in RR-0a. Rank no longer derives from XP, so
    // "XP to next rank" is meaningless. If a display needs "RR to next tier" it will be
    // an RR-based helper added with RR-0b — do not reintroduce an XP→rank derivation.

    // MARK: - Streak Management

    /// Updates streak based on last active date
    /// - Parameters:
    ///   - progress: UserProgress object (will be modified)
    ///   - currentDate: Current date (defaults to Date())
    /// - Returns: Updated current streak
    ///
    /// Streak logic:
    /// - Same day: no change
    /// - Next day: increment streak
    /// - 2+ days gap: reset to 1
    func updateStreak(for progress: inout UserProgress, currentDate: Date = Date()) -> Int {
        let calendar = Calendar.current
        let lastActive = calendar.startOfDay(for: progress.lastActiveDate)
        let today = calendar.startOfDay(for: currentDate)

        // Calculate day difference
        let dayDifference = calendar.dateComponents([.day], from: lastActive, to: today).day ?? 0

        switch dayDifference {
        case 0:
            // Same day - no change
            break
        case 1:
            // Next day - increment streak
            progress.currentStreak += 1
            if progress.currentStreak > progress.longestStreak {
                progress.longestStreak = progress.currentStreak
            }
        default:
            // Missed a day - reset to 1
            progress.currentStreak = 1
        }

        progress.lastActiveDate = currentDate
        return progress.currentStreak
    }

    /// Checks if streak should be reset (2+ days since last active)
    /// - Parameters:
    ///   - lastActiveDate: Date user was last active
    ///   - currentDate: Current date
    /// - Returns: True if streak should reset
    func shouldResetStreak(lastActiveDate: Date, currentDate: Date = Date()) -> Bool {
        let calendar = Calendar.current
        let dayDifference = calendar.dateComponents([.day], from: lastActiveDate, to: currentDate).day ?? 0
        return dayDifference >= 2
    }

    // MARK: - Streak Milestones

    /// Checks if a streak milestone should be awarded and claims it
    /// - Parameters:
    ///   - streak: Current streak count
    ///   - progress: UserProgress to update (will be modified)
    /// - Returns: The milestone that was claimed, or nil if none
    func checkForMilestone(streak: Int, progress: inout UserProgress) -> StreakMilestone? {
        // Check for next unclaimed milestone
        guard let milestone = StreakMilestone.nextUnclaimedMilestone(
            for: streak,
            claimedMilestones: progress.claimedMilestoneSet
        ) else {
            return nil
        }

        // Claim the milestone and award bonus XP
        progress.claim(milestone)
        _ = addXP(amount: milestone.bonusXP, to: &progress)

        return milestone
    }

    // MARK: - Quest Generation

    /// Generates 3 random daily quests
    /// - Parameter date: Date quests are for (defaults to today)
    /// - Returns: Array of 3 DailyQuest objects
    func generateDailyQuests(for date: Date = Date()) -> [DailyQuest] {
        var quests: [DailyQuest] = []

        // Define quest templates
        let questTemplates: [(title: String, description: String, xp: Int, type: String)] = [
            ("Log 3 Meals", "Track at least 3 food entries today", 30, "logging"),
            ("Stay Under Calorie Goal", "Keep calories at or below your daily target", 50, "nutrition"),
            ("Hit Protein Target", "Consume your daily protein goal", 40, "nutrition"),
            ("Maintain Purity", "Keep toxin score under your purity target", 60, "purity"),
            ("Capture All Meals", "Take photos of every food entry", 35, "logging"),
            ("Early Breakfast", "Log breakfast before 10 AM", 25, "streak"),
            ("Stay Balanced", "Meet all macro goals (protein, carbs, fat)", 70, "balance"),
            ("Clean Eating Streak", "All meals under 10 toxin score each", 55, "purity"),
            ("High Protein Meal", "Log a meal with 30g+ protein", 35, "nutrition"),
            ("Complete Your Day", "Meet all daily goals for bonus XP", 100, "achievement")
        ]

        // Randomly select 3 unique quests
        let selectedTemplates = questTemplates.shuffled().prefix(3)

        for template in selectedTemplates {
            let quest = DailyQuest(
                title: template.title,
                questDescription: template.description,
                xpReward: template.xp,
                isCompleted: false,
                date: date,
                questType: template.type
            )
            quests.append(quest)
        }

        return quests
    }

    // MARK: - Quest Progress Checking

    /// Checks and auto-completes quests based on daily progress
    /// - Parameters:
    ///   - quests: Today's quests (will be modified)
    ///   - entries: Today's food entries
    ///   - goal: Today's daily goal
    ///   - progress: User progress (for XP awards)
    /// - Returns: Total XP earned from newly completed quests
    func checkQuestProgress(
        quests: inout [DailyQuest],
        entries: [FoodEntry],
        goal: DailyGoal,
        progress: inout UserProgress
    ) -> Int {
        var totalXPEarned = 0

        for i in 0..<quests.count {
            // Skip already completed quests
            guard !quests[i].isCompleted else { continue }

            let questCompleted = isQuestCompleted(
                quest: quests[i],
                entries: entries,
                goal: goal
            )

            if questCompleted {
                quests[i].isCompleted = true
                let xpEarned = quests[i].xpReward
                _ = addXP(amount: xpEarned, to: &progress)
                totalXPEarned += xpEarned
            }
        }

        return totalXPEarned
    }

    /// Checks if a specific quest is completed
    /// - Parameters:
    ///   - quest: The quest to check
    ///   - entries: Today's food entries
    ///   - goal: Today's daily goal
    /// - Returns: True if quest criteria are met
    private func isQuestCompleted(quest: DailyQuest, entries: [FoodEntry], goal: DailyGoal) -> Bool {
        switch quest.title {
        case "Log 3 Meals":
            return entries.count >= 3

        case "Stay Under Calorie Goal":
            let totalCalories = entries.reduce(0) { $0 + $1.calories }
            return totalCalories <= goal.calorieTarget

        case "Hit Protein Target":
            let totalProtein = entries.reduce(0.0) { $0 + $1.protein }
            return totalProtein >= goal.proteinTarget

        case "Maintain Purity":
            return NutritionManager.dailyToxinScore(from: entries) <= goal.purityTarget

        case "Capture All Meals":
            return !entries.isEmpty && entries.allSatisfy { $0.photoData != nil }

        case "Early Breakfast":
            let calendar = Calendar.current
            let tenAM = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: Date())!
            return entries.contains { $0.date < tenAM }

        case "Stay Balanced":
            let totalProtein = entries.reduce(0.0) { $0 + $1.protein }
            let totalCarbs = entries.reduce(0.0) { $0 + $1.carbs }
            let totalFat = entries.reduce(0.0) { $0 + $1.fat }
            return totalProtein >= goal.proteinTarget &&
                   totalCarbs >= goal.carbTarget &&
                   totalFat >= goal.fatTarget

        case "Clean Eating Streak":
            return !entries.isEmpty && entries.allSatisfy { $0.toxinScore < 10 }

        case "High Protein Meal":
            return entries.contains { $0.protein >= 30.0 }

        case "Complete Your Day":
            let totalCalories = entries.reduce(0) { $0 + $1.calories }
            let totalProtein = entries.reduce(0.0) { $0 + $1.protein }
            let dailyToxin = NutritionManager.dailyToxinScore(from: entries)
            return totalCalories <= goal.calorieTarget &&
                   totalProtein >= goal.proteinTarget &&
                   dailyToxin <= goal.purityTarget

        default:
            return false
        }
    }

    /// Manually completes a quest and awards XP
    /// - Parameters:
    ///   - quest: Quest to complete (will be modified)
    ///   - progress: User progress (will be modified)
    /// - Returns: XP earned from quest
    func completeQuest(quest: inout DailyQuest, progress: inout UserProgress) -> Int {
        guard !quest.isCompleted else { return 0 }

        quest.isCompleted = true
        let xpEarned = quest.xpReward
        _ = addXP(amount: xpEarned, to: &progress)

        return xpEarned
    }

    // MARK: - Daily XP Rewards

    /// Awards XP for meeting daily goals
    /// - Parameters:
    ///   - progress: User progress (will be modified)
    ///   - metGoals: Whether goals were met
    /// - Returns: XP awarded (50 for meeting goals, 0 otherwise)
    func awardDailyGoalXP(to progress: inout UserProgress, metGoals: Bool) -> Int {
        guard metGoals else { return 0 }

        let xpReward = 50
        _ = addXP(amount: xpReward, to: &progress)
        return xpReward
    }

    // MARK: - Helper Methods

    /// Checks if it's a new day (quests should reset)
    /// - Parameters:
    ///   - lastDate: Last date quests were generated
    ///   - currentDate: Current date
    /// - Returns: True if it's a new day
    func shouldResetQuests(lastDate: Date, currentDate: Date = Date()) -> Bool {
        let calendar = Calendar.current
        let lastDay = calendar.startOfDay(for: lastDate)
        let today = calendar.startOfDay(for: currentDate)

        return today > lastDay
    }
}
