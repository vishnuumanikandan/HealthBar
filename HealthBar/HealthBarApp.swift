//
//  HealthBarApp.swift
//  HealthBar
//
//  Created by Vishnu Nathan on 1/12/26.
//

import SwiftUI
import SwiftData

@main
struct HealthBarApp: App {
    // SwiftData container for persistence
    let modelContainer: ModelContainer

    init() {
        do {
            // Schema configuration to enable automatic lightweight migration
            let schema = Schema([
                FoodEntry.self,
                DailyGoal.self,
                UserProgress.self,
                DailyQuest.self,
                PersonalBaseline.self,
                MoodEntry.self
            ])

            let modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false
            )

            // Set up SwiftData with migration support
            let container = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
            modelContainer = container

            // Set up default data for new users on first launch
            Task {
                let coordinator = AppCoordinator(modelContext: container.mainContext)
                try? await coordinator.setupApp()
            }
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(modelContainer)
        }
    }
}
