# HealthBar

Gamified nutrition and weight-loss tracking iOS app with RPG-style progression (XP, ranks, quests, streaks, badges).

## Tech Stack

- SwiftUI, iOS 26.2, Xcode 16.0
- MVVM with central AppCoordinator
- SwiftData for local persistence
- Firebase Auth (Google Sign-In) + Firestore cloud sync
- OpenFoodFacts API for barcode scanning

## Build & Run

```bash
# Build
xcodebuild -project HealthBar.xcodeproj -scheme HealthBar -sdk iphonesimulator -configuration Debug build

# Run tests
xcodebuild -project HealthBar.xcodeproj -scheme HealthBar -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' test

# List available simulators
xcrun simctl list devices available
```

## Architecture

```
Views → ViewModels → AppCoordinator → Managers → SwiftData
```

**AppCoordinator** (`App/AppCoordinator.swift`) is the central orchestrator. ViewModels call it for all business logic. It coordinates three managers:

- **DataManager** (`Persistence/DataManager.swift`) — SwiftData CRUD only. All fetches scoped to `currentUserId`. Never call from Views or ViewModels directly.
- **NutritionManager** (`Nutrition/NutritionManager.swift`) — Pure calculation logic (calories, macros, goals). No persistence access.
- **GamificationManager** (`Gamification/GamificationManager.swift`) — XP, levels, ranks, streaks, quests, badges. No persistence access.

## Module Layout

```
App/              AppCoordinator, APIConfig, SettingsManager
Auth/             FirebaseAuthService, LocalAuthService, AuthViewModel, Login/SignUp views
Models/           SwiftData models (FoodEntry, DailyGoal, UserProgress, etc.)
Firestore/        DTO types for Firestore sync
Nutrition/        NutritionManager, FoodDatabase, BarcodeService
Gamification/     GamificationManager
Persistence/      DataManager
Notifications/    NotificationManager
Resources/        DesignSystem, TimeOfDayTheme
UI/               All views and their ViewModels
UI/Components/    Reusable UI components (toasts, cards, pills)
HealthBar/        App entry point (HealthBarApp.swift, ContentView.swift, assets)
```

## Key Patterns

- **ViewModels are `@Observable` classes**, injected with `AppCoordinator`. Views hold them as `@State`.
- **Views are dumb** — display data and forward actions to the ViewModel.
- **Auth gating** is in `ContentView.swift` — checks `FirebaseAuthService.shared.isLoggedIn`.
- **User isolation** — DataManager scopes all queries to the authenticated user. Unauthenticated calls return empty or throw.
- **Firestore sync** — DataManager syncs to Firestore via DTOs in `Firestore/`. Local SwiftData is source of truth.

## Rules

1. Nutrition logic and Gamification logic stay in separate modules — never merge them.
2. ViewModels never touch DataManager or SwiftData directly — always go through AppCoordinator.
3. Models must be Codable.
4. Don't add features that weren't asked for.
5. If a change conflicts with this architecture, stop and ask before proceeding.
6. XP rewards healthy behavior, not perfection. Streaks are protected (no harsh resets). Ranks are identity signals, not skill gates.
