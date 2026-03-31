//
//  ContentView.swift
//  HealthBar
//
//  Created by Vishnu Nathan on 1/12/26.
//  Updated by Claude on 1/23/26 - Added TabView navigation
//  Updated by Claude on 1/19/26 - Added auth routing
//

import SwiftUI
import SwiftData

/// Root view of the app.
///
/// Gates the main TabView behind authentication. When `authService.isLoggedIn`
/// is `false`, the auth flow (LoginView → SignUpView via NavigationStack) is
/// shown instead. The switch is automatic — no imperative navigation needed.
///
/// The `AuthViewModel` and `FirebaseAuthService` instances are created once here
/// and live for the app session. ProfileView receives an `onLogout` closure so
/// it can trigger logout without depending on `FirebaseAuthService` directly.
struct ContentView: View {

    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext

    // MARK: - Auth State

    /// Observable auth service singleton. Accessing `authService.isLoggedIn`
    /// in `body` causes SwiftUI to re-render when the value changes.
    @State private var authService = FirebaseAuthService.shared

    /// Shared ViewModel for the entire auth flow (LoginView + SignUpView).
    /// Created with the auth service so Views never touch the concrete type.
    @State private var authViewModel: AuthViewModel

    // MARK: - Tab State

    /// Currently selected tab (0 = Home, 1 = Food, 2 = Tools, 3 = Profile).
    @State private var selectedTab: Int = 0

    /// Shared state for the Tools tab (carries TDEE from Calculator 1 → Calculator 8).
    @State private var toolsViewModel = ToolsViewModel()

    // MARK: - Onboarding State

    /// True when the current user has no completed UserProfile. Triggers fullScreenCover.
    @State private var showOnboarding: Bool = false

    // MARK: - Initialization

    init() {
        // AuthViewModel is initialized here so the same instance is shared
        // across LoginView and SignUpView (email typed on one carries to the other).
        self._authViewModel = State(
            initialValue: AuthViewModel(authService: FirebaseAuthService.shared)
        )
    }

    // MARK: - Body

    var body: some View {
        if authService.isLoggedIn {
            mainTabView
                .transition(.opacity)
        } else {
            authFlow
                .transition(.opacity)
        }
    }

    // MARK: - Auth Flow

    /// NavigationStack wrapping LoginView (root) and SignUpView (destination).
    ///
    /// LoginView uses `NavigationLink(value: AuthDestination.signUp)` to push
    /// SignUpView. The `navigationDestination` modifier here handles the routing.
    @ViewBuilder
    private var authFlow: some View {
        NavigationStack {
            LoginView(viewModel: authViewModel)
                .navigationDestination(for: AuthDestination.self) { destination in
                    switch destination {
                    case .signUp:
                        SignUpView(viewModel: authViewModel)
                    }
                }
        }
    }

    // MARK: - Main Tab View

    @ViewBuilder
    private var mainTabView: some View {
        TabView(selection: $selectedTab) {
            // Home Tab
            HomeView(
                // Firebase UID now flows through as userId — no longer an email address
                coordinator: AppCoordinator(modelContext: modelContext, authService: FirebaseAuthService.shared),
                selectedTab: $selectedTab
            )
            .tabItem {
                Label("Home", systemImage: "house.fill")
            }
            .tag(0)

            // Food Log Tab
            FoodLogView(coordinator: AppCoordinator(modelContext: modelContext, authService: FirebaseAuthService.shared))
                .tabItem {
                    Label("Food", systemImage: "fork.knife")
                }
                .tag(1)

            // Tools Tab — fitness calculators (no data persistence needed)
            ToolsView(toolsViewModel: toolsViewModel)
                .tabItem {
                    Label("Tools", systemImage: "wrench.and.screwdriver.fill")
                }
                .tag(2)

            // Profile Tab — receives logout closure so it can end the session
            // without referencing FirebaseAuthService directly.
            ProfileView(
                coordinator: AppCoordinator(modelContext: modelContext, authService: FirebaseAuthService.shared),
                onLogout: { authViewModel.logout() }
            )
            .tabItem {
                Label("Profile", systemImage: "person.fill")
            }
            .tag(3)
        }
        .tint(DesignSystem.Colors.primary)
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView(
                coordinator: AppCoordinator(modelContext: modelContext, authService: FirebaseAuthService.shared),
                authService: authService
            )
        }
        .task(id: authService.isLoggedIn) {
            guard authService.isLoggedIn else {
                showOnboarding = false
                return
            }
            let coordinator = AppCoordinator(modelContext: modelContext, authService: FirebaseAuthService.shared)

            // If no local profile exists, try restoring from Firestore first (blocking).
            // If local profile exists, sync Firestore in the background — don't block UI.
            let localProfile = try? await coordinator.getUserProfile()
            if localProfile == nil {
                try? await coordinator.syncUserProfileFromFirestore()
            } else {
                Task { try? await coordinator.syncUserProfileFromFirestore() }
            }

            let completed = await coordinator.checkOnboardingCompleted()
            showOnboarding = !completed
        }
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: FoodEntry.self, DailyGoal.self, UserProgress.self, DailyQuest.self,
        configurations: config
    )

    ContentView()
        .modelContainer(container)
}
