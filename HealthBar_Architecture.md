
# HealthBar Architecture (Source of Truth)


You are a senior iOS architect and SwiftUI engineer.

You will help me build an iOS app called HealthBar:
- A gamified weight-loss and nutrition tracking RPG
- Written in SwiftUI using MVVM architecture
- Designed for long-term extensibility and AI integration

Constraints:
- Prefer clean architecture over speed
- Avoid unnecessary abstractions
- Comment code clearly
- Never introduce features I didn’t ask for
- Always explain file structure before writing code

If a decision has tradeoffs, explain them before choosing.
                
## Enforcement
If any requested feature conflicts with this document,
the correct behavior is to STOP and ask for clarification.
Do not guess or auto-correct architecture.

                                                
## App Purpose
HealthBar is a gamified nutrition and weight-loss iOS app that combines
accurate food tracking with RPG-style motivation systems.

## Tech Stack
- SwiftUI
- MVVM architecture
- Local-first persistence
- iOS 26.2, Xcode 16.0


## Architectural Rules
1. Nutrition logic and Gamification logic MUST be separate modules
2. ViewModels may not directly modify persistence
3. Models must be Codable and future AI-compatible
4. AI features are isolated and mocked until Phase 4
5. No social or leaderboard features until Phase 5

## Core Modules
- App
- Models
- Nutrition
- Gamification
- Persistence
- AI
- UI
- Resources

## Gamification Principles
- XP rewards healthy behavior, not perfection
- Streaks are protected (no harsh resets)
- Ranks are identity signals, not skill gates

## AI Policy
- AI assists, user has final control
- Confidence scores required
- Manual overrides always allowed
#HealthBar_Architecture.md
#HealthBar

# Created by Vishnu Nathan on 1/19/26.

