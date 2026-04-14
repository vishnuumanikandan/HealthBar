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

    // MARK: - Guest → Auth Upgrade State

    /// Non-nil when guest→auth data migration failed. Shown as an alert.
    @State private var migrationError: String? = nil

    /// True when a guest user taps "Create Account" in ProfileView.
    @State private var showSignUpFromGuest: Bool = false

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

            // Profile Tab — receives logout closure and guest state so it can
            // end the session and show guest-mode UI without referencing
            // FirebaseAuthService directly.
            ProfileView(
                coordinator: AppCoordinator(modelContext: modelContext, authService: FirebaseAuthService.shared),
                authService: FirebaseAuthService.shared,
                onLogout: { authViewModel.logout() },
                onCreateAccount: { showSignUpFromGuest = true }
            )
            .tabItem {
                Label("Profile", systemImage: "person.fill")
            }
            .tag(3)
        }
        .tint(DesignSystem.Colors.primary)
        .overlay(alignment: .top) {
            if let badge = BadgeToastQueue.shared.currentToast {
                BadgeToastView(badge: badge, onDismiss: { BadgeToastQueue.shared.dismiss() })
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: BadgeToastQueue.shared.currentToast?.id)
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView(
                coordinator: AppCoordinator(modelContext: modelContext, authService: FirebaseAuthService.shared),
                authService: authService
            )
        }
        // Sign-up sheet presented when a guest taps "Create Account" in ProfileView.
        .sheet(isPresented: $showSignUpFromGuest) {
            NavigationStack {
                SignUpView(viewModel: authViewModel)
            }
        }
        .alert("Migration Failed", isPresented: .init(
            get: { migrationError != nil },
            set: { if !$0 { migrationError = nil } }
        )) {
            Button("OK", role: .cancel) { migrationError = nil }
        } message: {
            Text(migrationError ?? "")
        }
        // Re-runs whenever currentUserEmail changes:
        //   nil → "guest"   (guest mode entered)
        //   "guest" → uid   (migration completed, real auth active)
        //   nil → uid       (normal login / account creation)
        .task(id: authService.currentUserEmail) {
            guard let email = authService.currentUserEmail, !email.isEmpty else {
                showOnboarding = false
                return
            }
            let coordinator = AppCoordinator(modelContext: modelContext, authService: FirebaseAuthService.shared)

            if authService.isGuest {
                // Guest mode: skip all Firestore operations, check onboarding locally.
                let completed = await coordinator.checkOnboardingCompleted()
                showOnboarding = !completed
                return
            }

            // Authenticated user: sync profile from Firestore, then check onboarding.
            // If no local profile exists, block on Firestore fetch first.
            // If local profile exists, sync Firestore in background — don't block UI.
            let localProfile = try? await coordinator.getUserProfile()
            if localProfile == nil {
                try? await coordinator.syncUserProfileFromFirestore()
            } else {
                Task { try? await coordinator.syncUserProfileFromFirestore() }
            }

            let completed = await coordinator.checkOnboardingCompleted()
            showOnboarding = !completed
        }
        // Watches for guest→auth migration signal. Fires when a guest user signs up
        // and pendingMigrationUserId becomes non-nil.
        .onChange(of: authService.pendingMigrationUserId) { _, newUserId in
            guard let newUserId else { return }
            Task {
                let coordinator = AppCoordinator(
                    modelContext: modelContext,
                    authService: FirebaseAuthService.shared
                )
                do {
                    // Step 1–3: migrate SwiftData records from "guest" → real userId.
                    try await coordinator.migrateGuestData(to: newUserId)
                    // Step 4: drop guest mode, adopt real identity.
                    authService.completeMigration(newUserId: newUserId)
                    // Step 5: explicitly start Firestore sync (task(id: currentUserEmail)
                    // will also re-fire, but belt+suspenders for the sync init).
                    coordinator.startFirestoreSyncForCurrentUser()
                } catch {
                    // Migration failed: keep guest mode, show error.
                    authService.cancelMigration()
                    migrationError = "Failed to migrate data. Please try again."
                }
            }
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
