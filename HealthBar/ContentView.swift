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

    /// Settings for theme-aware tab backgrounds.
    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeTheme.colors }

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
        Group {
            if authService.isLoggedIn {
                mainTabView
                    .transition(.opacity)
            } else {
                authFlow
                    .transition(.opacity)
            }
        }
        .preferredColorScheme(.light)
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
        VStack(spacing: 0) {
            TabView(selection: $selectedTab) {
                // Home Tab
                HomeView(
                    coordinator: AppCoordinator(modelContext: modelContext, authService: FirebaseAuthService.shared),
                    selectedTab: $selectedTab
                )
                .background(tc.primaryBackground.ignoresSafeArea())
                .toolbar(.hidden, for: .tabBar)
                .tag(0)

                // Food Log Tab
                FoodLogView(coordinator: AppCoordinator(modelContext: modelContext, authService: FirebaseAuthService.shared))
                    .background(tc.primaryBackground.ignoresSafeArea())
                    .toolbar(.hidden, for: .tabBar)
                    .tag(1)

                // Tools Tab
                ToolsView(toolsViewModel: toolsViewModel)
                    .background(tc.primaryBackground.ignoresSafeArea())
                    .toolbar(.hidden, for: .tabBar)
                    .tag(2)

                // Profile Tab
                ProfileView(
                    coordinator: AppCoordinator(modelContext: modelContext, authService: FirebaseAuthService.shared),
                    authService: FirebaseAuthService.shared,
                    onLogout: { authViewModel.logout() },
                    onCreateAccount: { showSignUpFromGuest = true }
                )
                .background(tc.primaryBackground.ignoresSafeArea())
                .toolbar(.hidden, for: .tabBar)
                .tag(3)
            }

            WoodenTabBar(selectedTab: $selectedTab)
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
        .task(id: authService.currentUserEmail) {
            guard let email = authService.currentUserEmail, !email.isEmpty else {
                showOnboarding = false
                return
            }
            let coordinator = AppCoordinator(modelContext: modelContext, authService: FirebaseAuthService.shared)

            if authService.isGuest {
                let completed = await coordinator.checkOnboardingCompleted()
                showOnboarding = !completed
                return
            }

            let localProfile = try? await coordinator.getUserProfile()
            if localProfile == nil {
                try? await coordinator.syncUserProfileFromFirestore()
            } else {
                Task { try? await coordinator.syncUserProfileFromFirestore() }
            }

            let completed = await coordinator.checkOnboardingCompleted()
            showOnboarding = !completed
        }
        .onChange(of: authService.isGuest) { _, isGuest in
            if !isGuest && showSignUpFromGuest {
                showSignUpFromGuest = false
            }
        }
        .onChange(of: authService.pendingMigrationUserId) { _, newUserId in
            guard let newUserId else { return }
            Task {
                let coordinator = AppCoordinator(
                    modelContext: modelContext,
                    authService: FirebaseAuthService.shared
                )
                do {
                    try await coordinator.migrateGuestData(to: newUserId)
                    authService.completeMigration(newUserId: newUserId)
                    coordinator.startFirestoreSyncForCurrentUser()
                    showSignUpFromGuest = false
                } catch {
                    authService.cancelMigration()
                    migrationError = "Failed to migrate data. Please try again."
                    showSignUpFromGuest = false
                }
            }
        }
    }
}

// MARK: - Wooden Tab Bar

/// Custom pixel-art wooden tab bar replacing the system tab bar.
struct WoodenTabBar: View {
    @Binding var selectedTab: Int
    var theme: TimeOfDayTheme = SettingsManager.shared.activeTheme

    private var tc: ThemeColors { theme.colors }

    private let tabs: [(icon: String, label: String, tag: Int)] = [
        ("house.fill", "Home", 0),
        ("fork.knife", "Food", 1),
        ("wrench.and.screwdriver.fill", "Tools", 2),
        ("person.fill", "Profile", 3)
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.tag) { tab in
                Button {
                    selectedTab = tab.tag
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 22))
                        Text(tab.label)
                            .font(DesignSystem.Typography.pixel(12))
                    }
                    .foregroundColor(selectedTab == tab.tag ? tc.tabActive : tc.tabInactive)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 4)
        .background(
            LinearGradient(
                stops: [
                    .init(color: tc.tabBarLight, location: 0),
                    .init(color: tc.tabBarLight, location: 0.06),
                    .init(color: tc.tabBarMid, location: 0.06),
                    .init(color: tc.tabBarMid, location: 0.94),
                    .init(color: tc.tabBarDark, location: 0.94),
                    .init(color: tc.tabBarDark, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
        // Top border line
        .overlay(alignment: .top) {
            Rectangle()
                .fill(tc.tabBarDark)
                .frame(height: 2)
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
