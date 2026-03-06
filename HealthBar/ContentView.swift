//
//  ContentView.swift
//  HealthBar
//
//  Created by Vishnu Nathan on 1/12/26.
//  Updated by Claude on 1/23/26 - Added TabView navigation
//

import SwiftUI
import SwiftData

/// Main content view with TabView navigation
///
/// Provides tab-based navigation between:
/// - Home (dashboard)
/// - Food Log (nutrition tracking)
/// - Profile (stats and settings)
struct ContentView: View {
    // Access SwiftData context
    @Environment(\.modelContext) private var modelContext

    // Selected tab state (0 = Home, 1 = Food, 2 = Profile)
    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // Home Tab
            HomeView(
                coordinator: AppCoordinator(modelContext: modelContext),
                selectedTab: $selectedTab
            )
            .tabItem {
                Label("Home", systemImage: "house.fill")
            }
            .tag(0)

            // Food Log Tab
            FoodLogView(coordinator: AppCoordinator(modelContext: modelContext))
                .tabItem {
                    Label("Food", systemImage: "fork.knife")
                }
                .tag(1)

            // Profile Tab
            ProfileView(coordinator: AppCoordinator(modelContext: modelContext))
                .tabItem {
                    Label("Profile", systemImage: "person.fill")
                }
                .tag(2)
        }
        .tint(DesignSystem.Colors.primary) // Selected tab color
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: FoodEntry.self, DailyGoal.self, UserProgress.self, DailyQuest.self, configurations: config)

    ContentView()
        .modelContainer(container)
}
