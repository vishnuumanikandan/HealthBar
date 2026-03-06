# ViewModel Guide for HealthBar

## What is a ViewModel?

A **ViewModel** in SwiftUI/MVVM architecture is a class that:

1. **Holds UI state** (data the view needs to display)
2. **Handles user actions** (button taps, form submissions)
3. **Calls business logic** (through AppCoordinator)
4. **Transforms data** for the view (formatting, computed properties)

### Key Principle
**Views should be "dumb"** - they just display data and forward actions to the ViewModel.
**ViewModels should be "smart"** - they contain all presentation logic.

---

## Structure of a ViewModel

```swift
@Observable  // Makes the class reactive to SwiftUI
final class MyViewModel {

    // MARK: - Dependencies
    private let coordinator: AppCoordinator

    // MARK: - UI State
    var data: SomeData?
    var isLoading = false
    var errorMessage: String?

    // MARK: - Computed Properties (for UI)
    var displayText: String {
        // Transform data for display
        return data?.formattedValue ?? "N/A"
    }

    // MARK: - Initialization
    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    // MARK: - Actions
    func loadData() async {
        isLoading = true
        // Call coordinator for business logic
        isLoading = false
    }

    func handleButtonTap() {
        // Handle user action
    }
}
```

---

## How to Use a ViewModel in a View

### 1. Create the ViewModel in the View

```swift
struct MyView: View {
    @State private var viewModel: MyViewModel

    init(coordinator: AppCoordinator) {
        self.viewModel = MyViewModel(coordinator: coordinator)
    }

    var body: some View {
        // Use viewModel properties
        Text(viewModel.displayText)

        Button("Load") {
            Task {
                await viewModel.loadData()
            }
        }
    }
}
```

### 2. Key SwiftUI Patterns

#### `@Observable` (Modern, iOS 17+)
```swift
@Observable
final class MyViewModel {
    var count = 0  // Automatically observed
}

struct MyView: View {
    @State private var viewModel: MyViewModel
    // View updates automatically when viewModel.count changes
}
```

#### `task` modifier (load data when view appears)
```swift
.task {
    await viewModel.loadData()
}
```

#### `refreshable` (pull-to-refresh)
```swift
.refreshable {
    await viewModel.refresh()
}
```

---

## Examples from HealthBar

### Example 1: HomeViewModel (Display Data)

**Purpose:** Show today's nutrition summary

```swift
@Observable
final class HomeViewModel {
    private let coordinator: AppCoordinator

    var summary: TodaySummary?
    var isLoading = false

    // Computed property for UI
    var calorieProgressText: String {
        guard let summary else { return "-- / --" }
        return "\(summary.totalCalories) / \(summary.goal.calorieTarget)"
    }

    func loadData() async {
        isLoading = true
        summary = try? await coordinator.getTodaysSummary()
        isLoading = false
    }
}
```

**View:**
```swift
struct HomeView: View {
    @State private var viewModel: HomeViewModel

    var body: some View {
        VStack {
            Text(viewModel.calorieProgressText)
        }
        .task {
            await viewModel.loadData()
        }
    }
}
```

---

### Example 2: AddFoodViewModel (Form Handling)

**Purpose:** Add a new food entry

```swift
@Observable
final class AddFoodViewModel {
    private let coordinator: AppCoordinator

    var foodName = ""
    var calories = ""
    var isSubmitting = false

    var isFormValid: Bool {
        !foodName.isEmpty && Int(calories) != nil
    }

    func submitFood() async -> Bool {
        guard isFormValid else { return false }

        isSubmitting = true
        let success = try? await coordinator.addFoodEntry(
            name: foodName,
            calories: Int(calories)!,
            // ... other params
        )
        isSubmitting = false

        return success != nil
    }
}
```

**View:**
```swift
struct AddFoodView: View {
    @State private var viewModel: AddFoodViewModel

    var body: some View {
        Form {
            TextField("Food Name", text: $viewModel.foodName)
            TextField("Calories", text: $viewModel.calories)

            Button("Submit") {
                Task {
                    let success = await viewModel.submitFood()
                    if success {
                        // Dismiss or show success
                    }
                }
            }
            .disabled(!viewModel.isFormValid || viewModel.isSubmitting)
        }
    }
}
```

---

## Common Patterns

### 1. Loading State
```swift
var isLoading = false

func loadData() async {
    isLoading = true
    defer { isLoading = false }  // Always reset

    // Do work...
}
```

### 2. Error Handling
```swift
var errorMessage: String?

func loadData() async {
    do {
        data = try await coordinator.getData()
        errorMessage = nil
    } catch {
        errorMessage = error.localizedDescription
    }
}
```

### 3. Form Validation
```swift
var username = ""
var password = ""

var isFormValid: Bool {
    !username.isEmpty && password.count >= 8
}

var validationErrors: [String] {
    var errors: [String] = []
    if username.isEmpty { errors.append("Username required") }
    if password.count < 8 { errors.append("Password too short") }
    return errors
}
```

### 4. Success States
```swift
var showSuccessMessage = false

func submitForm() async {
    // ... submit logic ...
    showSuccessMessage = true

    // Auto-hide after delay
    Task {
        try await Task.sleep(for: .seconds(2))
        showSuccessMessage = false
    }
}
```

---

## Rules for ViewModels in HealthBar

### ✅ DO:
- Use `@Observable` for automatic SwiftUI reactivity
- Make all async operations `async` functions
- Use `AppCoordinator` for all business logic
- Add computed properties for UI formatting
- Handle validation in the ViewModel
- Keep error messages user-friendly

### ❌ DON'T:
- Don't call `DataManager` directly (use `AppCoordinator`)
- Don't put SwiftUI views inside ViewModels
- Don't do heavy computation on the main thread
- Don't store `@Published` properties (use `@Observable` instead)
- Don't make ViewModels conform to `ObservableObject` (outdated pattern)

---

## Testing ViewModels

ViewModels are easy to test because they're pure Swift classes:

```swift
func testLoadData() async throws {
    let mockCoordinator = MockAppCoordinator()
    let viewModel = HomeViewModel(coordinator: mockCoordinator)

    await viewModel.loadData()

    XCTAssertNotNil(viewModel.summary)
    XCTAssertFalse(viewModel.isLoading)
}
```

---

## Cheat Sheet

| Task | Code |
|------|------|
| Create ViewModel | `@Observable final class MyViewModel { ... }` |
| Use in View | `@State private var viewModel: MyViewModel` |
| Load on appear | `.task { await viewModel.load() }` |
| Pull-to-refresh | `.refreshable { await viewModel.refresh() }` |
| Two-way binding | `TextField("Name", text: $viewModel.name)` |
| Computed property | `var text: String { data?.value ?? "N/A" }` |
| Loading state | `if viewModel.isLoading { ProgressView() }` |
| Error handling | `if let error = viewModel.error { Text(error) }` |

---

## Next Steps

1. Create ViewModels for each screen in your app
2. Always pass `AppCoordinator` as a dependency
3. Keep Views simple (just display + forward actions)
4. Put all presentation logic in ViewModels

**Example ViewModel ideas for HealthBar:**
- `HomeViewModel` - Dashboard ✅ (created)
- `AddFoodViewModel` - Add food form ✅ (created)
- `QuestsViewModel` - Manage daily quests
- `ProgressViewModel` - View XP/level history
- `SettingsViewModel` - Update goals and preferences
