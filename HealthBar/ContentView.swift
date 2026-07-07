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

    /// Currently selected tab (0 = Home, 1 = Food, 2 = Battle, 3 = Friends, 4 = Profile).
    /// (Tools moved off the tab bar into a Profile entry when Battle took the center slot.)
    @State private var selectedTab: Int = 0

    /// Settings for theme-aware tab backgrounds.
    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }

    // MARK: - Username Gate State

    /// True when the current authenticated (non-guest) user has no claimed username.
    @State private var showClaimUsername: Bool = false

    // MARK: - Onboarding State

    /// True when the current user has no completed UserProfile. Triggers fullScreenCover.
    @State private var showOnboarding: Bool = false

    // MARK: - Guest → Auth Upgrade State

    /// Non-nil when guest→auth data migration failed. Shown as an alert.
    @State private var migrationError: String? = nil

    /// True when a guest user taps "Create Account" in ProfileView.
    @State private var showSignUpFromGuest: Bool = false

    /// PREVIEW ONLY — driven by the "--preview-friend-profile" launch argument.
    @State private var showPreviewFriendProfile: Bool = false

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
        .preferredColorScheme(settings.isCleanDark ? .dark : .light)
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
                    selectedTab: $selectedTab,
                    authService: FirebaseAuthService.shared
                )
                .background(tc.primaryBackground.ignoresSafeArea())
                .toolbar(.hidden, for: .tabBar)
                .tag(0)

                // Food Log Tab
                FoodLogView(coordinator: AppCoordinator(modelContext: modelContext, authService: FirebaseAuthService.shared))
                    .background(tc.primaryBackground.ignoresSafeArea())
                    .toolbar(.hidden, for: .tabBar)
                    .tag(1)

                // Battle Tab (D1a) — center slot
                BattleView(
                    coordinator: AppCoordinator(modelContext: modelContext, authService: FirebaseAuthService.shared),
                    authService: FirebaseAuthService.shared,
                    onCreateAccount: { showSignUpFromGuest = true }
                )
                .background(tc.primaryBackground.ignoresSafeArea())
                .toolbar(.hidden, for: .tabBar)
                .tag(2)

                // Friends Tab
                FriendsView(
                    coordinator: AppCoordinator(modelContext: modelContext, authService: FirebaseAuthService.shared),
                    authService: FirebaseAuthService.shared,
                    onCreateAccount: { showSignUpFromGuest = true }
                )
                .background(tc.primaryBackground.ignoresSafeArea())
                .toolbar(.hidden, for: .tabBar)
                .tag(3)

                // Profile Tab
                ProfileView(
                    coordinator: AppCoordinator(modelContext: modelContext, authService: FirebaseAuthService.shared),
                    authService: FirebaseAuthService.shared,
                    onLogout: { authViewModel.logout() },
                    onCreateAccount: { showSignUpFromGuest = true }
                )
                .background(tc.primaryBackground.ignoresSafeArea())
                .toolbar(.hidden, for: .tabBar)
                .tag(4)
            }

            if settings.isCleanUI {
                CleanTabBar(selectedTab: $selectedTab)
            } else {
                WoodenTabBar(selectedTab: $selectedTab)
            }
        }
        .tint(DesignSystem.Colors.primary)
        .overlay(alignment: .top) {
            if let badge = BadgeToastQueue.shared.currentToast {
                BadgeToastView(badge: badge, onDismiss: { BadgeToastQueue.shared.dismiss() })
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: BadgeToastQueue.shared.currentToast?.id)
        .fullScreenCover(isPresented: $showClaimUsername) {
            ClaimUsernameView(
                coordinator: AppCoordinator(modelContext: modelContext, authService: FirebaseAuthService.shared)
            ) {
                showClaimUsername = false
                Task {
                    let coordinator = AppCoordinator(modelContext: modelContext, authService: FirebaseAuthService.shared)
                    let completed = await coordinator.checkOnboardingCompleted()
                    showOnboarding = !completed
                }
            }
        }
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
        // PREVIEW ONLY — the "--preview-friend-profile" launch argument
        // auto-opens the placeholder friend's profile sheet so the UI can be
        // iterated/screenshotted from the CLI. Remove with PlaceholderFriend.
        .sheet(isPresented: $showPreviewFriendProfile) {
            FriendProfileView(
                coordinator: AppCoordinator(modelContext: modelContext, authService: FirebaseAuthService.shared),
                friendUid: PlaceholderFriend.uid,
                username: PlaceholderFriend.username,
                displayName: PlaceholderFriend.displayName
            )
        }
        // Clean-log QTE (D1d): presented root-level so a qualifying low-toxin meal logged from
        // ANY flow (Home quick-add, Food log, Describe-a-meal) surfaces the same power moment.
        // DataManager sets the pending state; `.sheet(item:)` clears it on dismiss.
        .sheet(item: Binding(
            get: { DuelUIState.shared.pendingCleanLogQTE },
            set: { DuelUIState.shared.pendingCleanLogQTE = $0 }
        )) { pending in
            CleanLogQTESheet(
                coordinator: AppCoordinator(modelContext: modelContext, authService: FirebaseAuthService.shared),
                pending: pending,
                dateKey: QTEDay.dateKey(for: Date())
            )
        }
        .task {
            switch ProcessInfo.processInfo.environment["HB_PREVIEW"] {
            case "friend-profile":
                try? await Task.sleep(for: .seconds(1))
                showPreviewFriendProfile = true
            case "friends-tab", "leaderboard":
                // FriendsView handles the leaderboard push itself.
                selectedTab = 3
            default:
                break
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
                showClaimUsername = false
                return
            }
            let coordinator = AppCoordinator(modelContext: modelContext, authService: FirebaseAuthService.shared)

            if authService.isGuest {
                showClaimUsername = false
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

            let needsUsername = await coordinator.needsUsername()
            showClaimUsername = needsUsername
            showOnboarding = needsUsername ? false : !(await coordinator.checkOnboardingCompleted())
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
        ("flag.2.crossed.fill", "Battle", 2), // TODO: swap for a custom crossed-swords pixel asset
        ("person.2.fill", "Friends", 3),
        ("person.fill", "Profile", 4)
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
                            .overlay(alignment: .topTrailing) { BattleTabBadge(tag: tab.tag, tc: tc) }
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

// MARK: - Clean Tab Bar

/// Clean floating-island tab bar for the minimalist UI style.
/// Rounded container with pill-shaped active indicator. No textures or pixel fonts.
struct CleanTabBar: View {
    @Binding var selectedTab: Int
    private var tc: ThemeColors { SettingsManager.shared.activeColors }
    private var isDark: Bool { SettingsManager.shared.isCleanDark }

    private let tabs: [(icon: String, label: String, tag: Int)] = [
        ("house.fill", "Home", 0),
        ("fork.knife", "Food", 1),
        ("flag.2.crossed.fill", "Battle", 2), // TODO: swap for a custom crossed-swords pixel asset
        ("person.2.fill", "Friends", 3),
        ("person.fill", "Profile", 4)
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(tabs, id: \.tag) { tab in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            selectedTab = tab.tag
                        }
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 19, weight: .medium))
                                .scaleEffect(selectedTab == tab.tag ? 1.08 : 1.0)
                                .overlay(alignment: .topTrailing) { BattleTabBadge(tag: tab.tag, tc: tc) }
                            Text(tab.label)
                                .font(.system(size: 10, weight: selectedTab == tab.tag ? .medium : .regular, design: .rounded))
                        }
                        .foregroundColor(selectedTab == tab.tag ? tc.tabActive : tc.tabInactive)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            Group {
                                if selectedTab == tab.tag {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(tc.primary.opacity(0.15))
                                } else {
                                    Color.clear
                                }
                            }
                        )
                    }
                }
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(tc.tabBarMid)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(isDark ? 0.06 : 0), lineWidth: 0.5)
                    )
            )
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
        .background(tc.primaryBackground.ignoresSafeArea(edges: .bottom))
    }
}

// MARK: - Duel Tab Badge (D1c)

/// Active-duel count badge with an unseen-changes pulse, overlaid on the Battle tab icon in
/// both tab bars. Self-observes `DuelUIState`; absent when the count is 0 (guests are always
/// 0 via `reset()`). Extracted to one view so both bars share identical badge behavior.
private struct BattleTabBadge: View {
    let tag: Int
    let tc: ThemeColors
    @State private var duelUI = DuelUIState.shared
    @State private var animate = false

    var body: some View {
        if tag == 2 && duelUI.activeDuelCount > 0 {
            Text("\(duelUI.activeDuelCount)")
                .font(AppFont.bold(9))
                .foregroundColor(.white)
                .frame(width: 16, height: 16)
                .background(Circle().fill(tc.tabActive))
                .scaleEffect(duelUI.hasUnseenChanges && animate ? 1.25 : 1.0)
                .offset(x: 9, y: -7)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                        animate = true
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
