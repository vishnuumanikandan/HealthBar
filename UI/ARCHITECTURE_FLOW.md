# HealthBar Architecture Flow

## The Complete Picture

```
┌─────────────────────────────────────────────────────────────┐
│                         SwiftUI VIEWS                       │
│  (HomeView, AddFoodView, QuestsView, etc.)                  │
│                                                             │
│  - Display data                                             │
│  - Handle user input                                        │
│  - Forward actions to ViewModel                             │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      │ @State
                      ▼
┌─────────────────────────────────────────────────────────────┐
│                        VIEW MODELS                          │
│  (HomeViewModel, AddFoodViewModel, etc.)                    │
│                                                             │
│  - Hold UI state (loading, errors, data)                    │
│  - Format data for display                                  │
│  - Validate user input                                      │
│  - Call AppCoordinator for logic                            │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      │ coordinator.method()
                      ▼
┌─────────────────────────────────────────────────────────────┐
│                      APP COORDINATOR                        │
│  (AppCoordinator.swift)                                     │
│                                                             │
│  - Orchestrates complex workflows                           │
│  - Coordinates between managers                             │
│  - Handles multi-step operations                            │
└───┬─────────────────┬─────────────────┬─────────────────────┘
    │                 │                 │
    │ fetch/save      │ calculate       │ compute XP/quests
    ▼                 ▼                 ▼
┌─────────┐      ┌──────────┐     ┌──────────────┐
│  DATA   │      │NUTRITION │     │ GAMIFICATION │
│ MANAGER │      │ MANAGER  │     │   MANAGER    │
└─────────┘      └──────────┘     └──────────────┘
│                │                │
│ SwiftData      │ Pure logic     │ Pure logic
│ CRUD only      │ Calculations   │ XP/Ranks/Quests
│                │                │
▼                │                │
┌─────────┐      │                │
│SwiftData│      │                │
│ Models  │◄─────┴────────────────┘
└─────────┘
```

---

## Data Flow Example: Adding a Food Entry

### 1. **User Action (View)**
```swift
// AddFoodView.swift
Button("Add Food") {
    Task {
        await viewModel.submitFood()  // ← User taps button
    }
}
```

### 2. **ViewModel Handles Action**
```swift
// AddFoodViewModel.swift
func submitFood() async {
    // Validate form
    guard isFormValid else { return }

    // Call coordinator
    let result = try await coordinator.addFoodEntry(
        name: foodName,
        calories: Int(calories)!,
        // ... other fields
    )

    // Update UI state
    showSuccessMessage = true
}
```

### 3. **Coordinator Orchestrates**
```swift
// AppCoordinator.swift
func addFoodEntry(...) async throws -> (entry: FoodEntry, xpEarned: Int) {
    // Step 1: Save to database
    let entry = try await dataManager.addFoodEntry(...)

    // Step 2: Check quests
    let quests = try await dataManager.getTodaysQuests()
    let entries = try await dataManager.fetchTodaysEntries()
    let goal = try await getCurrentGoal()
    var progress = try await dataManager.getUserProgress()

    // Step 3: Calculate quest completion (gamification logic)
    let xpEarned = gamificationManager.checkQuestProgress(
        quests: &quests,
        entries: entries,
        goal: goal,
        progress: &progress
    )

    // Step 4: Save updates
    try await dataManager.saveQuests()
    try await dataManager.saveUserProgress()

    return (entry: entry, xpEarned: xpEarned)
}
```

### 4. **Managers Do Their Jobs**

**DataManager** (Persistence):
```swift
func addFoodEntry(...) async throws -> FoodEntry {
    let entry = FoodEntry(...)
    modelContext.insert(entry)
    try modelContext.save()
    return entry
}
```

**GamificationManager** (Game Logic):
```swift
func checkQuestProgress(...) -> Int {
    // Check each quest
    // Award XP if completed
    // Return total XP earned
}
```

### 5. **View Updates Automatically**
```swift
// SwiftUI automatically re-renders when @Observable properties change
if viewModel.showSuccessMessage {
    Text("Food added! +\(viewModel.xpEarned) XP")
}
```

---

## Separation of Concerns

### ✅ Each Layer Has One Job

| Layer | Responsibility | Example |
|-------|----------------|---------|
| **View** | Display & Input | Show buttons, text fields |
| **ViewModel** | UI State & Formatting | `"1500 / 2000 cal"` |
| **AppCoordinator** | Orchestration | "Add food, then check quests" |
| **DataManager** | Persistence | Save/Load from SwiftData |
| **NutritionManager** | Nutrition Logic | Calculate total calories |
| **GamificationManager** | Game Logic | Award XP, check streaks |
| **Models** | Data Structures | FoodEntry, DailyGoal, etc. |

---

## Why This Architecture?

### ✅ Benefits

1. **Testable**
   - Each manager can be tested independently
   - ViewModels can be tested without UI
   - Easy to mock dependencies

2. **Maintainable**
   - Clear separation: Nutrition ≠ Gamification
   - Change one module without affecting others
   - Easy to find where logic lives

3. **Scalable**
   - Add new features without rewriting
   - AI module can be plugged in later
   - Social features don't pollute core logic

4. **Follows Architecture Document**
   - ✅ Nutrition and Gamification are separate
   - ✅ MVVM pattern
   - ✅ ViewModels don't directly modify persistence
   - ✅ Models are Codable and future-proof

---

## Quick Reference: Where Does This Code Go?

| What You're Doing | Where It Goes |
|-------------------|---------------|
| Display data | **View** (SwiftUI) |
| Format text for UI | **ViewModel** (computed property) |
| Handle button tap | **ViewModel** (action method) |
| Validate form | **ViewModel** (validation method) |
| Save to database | **DataManager** |
| Calculate calories | **NutritionManager** |
| Award XP | **GamificationManager** |
| Multi-step workflow | **AppCoordinator** |
| Define data structure | **Models** |

---

## Common Questions

### Q: Why not just use DataManager directly in ViewModels?
**A:** AppCoordinator handles **workflows** that need multiple managers.
Example: Adding food needs DataManager (save) + GamificationManager (check quests).

### Q: Can ViewModels call multiple managers?
**A:** No. Always go through AppCoordinator. This keeps dependencies clear.

### Q: Where do I put business rules?
**A:**
- Nutrition rules → **NutritionManager**
- Game rules → **GamificationManager**
- Multi-step workflows → **AppCoordinator**

### Q: What if I need data in multiple views?
**A:**
- Option 1: Pass `AppCoordinator` to each view (recommended)
- Option 2: Use SwiftUI `@Environment` for coordinator
- Never share ViewModels between views

---

## Next Steps

1. ✅ Read `VIEWMODEL_GUIDE.md` for ViewModel patterns
2. ✅ Create ViewModels for each screen
3. ✅ Always use `AppCoordinator` for business logic
4. ✅ Keep Views simple (just display + forward)
5. ✅ Keep Managers focused (one responsibility each)

**You're ready to build! 🚀**
