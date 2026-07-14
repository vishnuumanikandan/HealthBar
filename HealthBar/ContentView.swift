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

    /// R7b §1: drives the persistent top bar's scenePhase → .active refresh.
    @Environment(\.scenePhase) private var scenePhase

    // MARK: - Auth State

    /// Observable auth service singleton. Accessing `authService.isLoggedIn`
    /// in `body` causes SwiftUI to re-render when the value changes.
    @State private var authService = FirebaseAuthService.shared

    /// Shared ViewModel for the entire auth flow (LoginView + SignUpView).
    /// Created with the auth service so Views never touch the concrete type.
    @State private var authViewModel: AuthViewModel

    /// B1: navigation path for the auth-flow NavigationStack. Lets WelcomeView's CTAs push
    /// Login/SignUp (via ContentView) and lets `welcomeIsFrontmost` read the stack depth.
    @State private var authPath = NavigationPath()

    /// B1: whether the first-launch WelcomeView is the auth-stack root THIS session. Read
    /// ONCE from `hasSeenWelcome` at init (root stability) and never recomputed in `body`, so
    /// persisting the flag from a CTA doesn't flip the root mid-session — a pushed Login/SignUp
    /// pops back to Welcome. Set false once any authenticated session appears (grandfathering)
    /// so a later in-session logout lands on LoginView, not Welcome.
    @State private var showWelcomeRoot: Bool

    // MARK: - Tab State

    /// Currently selected tab (0 = Home, 1 = Food, 2 = Battle, 3 = Friends, 4 = Profile).
    /// (Tools moved off the tab bar into a Profile entry when Battle took the center slot.)
    @State private var selectedTab: Int = 0

    /// Settings for theme-aware tab backgrounds.
    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }

    /// R7b §1: the persistent top bar's view model. Optional + lazily built because its
    /// coordinator needs `modelContext` (an @Environment value unavailable at `init`); it is
    /// constructed once on first appear. Lifetime is local to ContentView — never promoted to
    /// Environment, never threaded into a tab.
    @State private var topBarViewModel: TopBarViewModel?

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
        // B1: read the welcome flag ONCE (root stability). The persisted flag takes effect
        // only on the next launch; this session's auth-stack root is fixed here.
        self._showWelcomeRoot = State(
            initialValue: !SettingsManager.shared.hasSeenWelcome
        )
    }

    // MARK: - Body

    var body: some View {
        Group {
            if authService.isLoggedIn {
                // R7b §1: the persistent top bar sits ABOVE the TabView (a VStack sibling), NOT
                // as a TabView top safeAreaInset. A TabView-level top inset does not push the
                // per-tab NavigationStack nav bars down, so the bar overlapped them — hiding the
                // principal titles and, critically, the Profile Settings gear. Placed above the
                // TabView, every tab's nav bar + content render below the bar, and it still
                // persists across tab switches and over pushed destinations (those live inside
                // the tabs' own NavigationStacks, which are inside this TabView).
                VStack(spacing: 0) {
                    PersistentTopBar(viewModel: topBarViewModel)
                    mainTabView
                }
                .transition(.opacity)
                .onAppear {
                    // B1 grandfathering: any authenticated session marks the welcome seen (so
                    // existing/just-authed users never see it) and pins the auth root to
                    // LoginView — an in-session logout then lands there, never on Welcome.
                    if !SettingsManager.shared.hasSeenWelcome {
                        SettingsManager.shared.hasSeenWelcome = true
                    }
                    showWelcomeRoot = false
                }
            } else {
                authFlow
                    .transition(.opacity)
            }
        }
        .preferredColorScheme(welcomeColorScheme)
    }

    // MARK: - B1 Welcome Routing

    /// True only while the fixed-dark WelcomeView is the frontmost auth screen (root, nothing
    /// pushed). Pushed Login/SignUp (path non-empty) and the logged-in app fall through.
    private var welcomeIsFrontmost: Bool {
        !authService.isLoggedIn && showWelcomeRoot && authPath.isEmpty
    }

    /// Force `.dark` under the fixed-dark Welcome so the status bar stays legible regardless
    /// of the user's theme; otherwise the user's own scheme, exactly as before B1.
    private var welcomeColorScheme: ColorScheme {
        welcomeIsFrontmost ? .dark : (settings.isCleanDark ? .dark : .light)
    }

    // MARK: - Auth Flow

    /// NavigationStack for the auth flow. Root is WelcomeView on first launch (B1) — until
    /// `hasSeenWelcome` is set — otherwise LoginView. Welcome's CTAs push `.signUp`/`.login`
    /// onto `authPath`; `navigationDestination` renders them (a pushed Login uses the nav-bar
    /// variant with its guest/sign-up section hidden). Popping a pushed screen returns to
    /// whichever root this session started with (root stability).
    @ViewBuilder
    private var authFlow: some View {
        NavigationStack(path: $authPath) {
            Group {
                if showWelcomeRoot {
                    WelcomeView(
                        onGetStarted: {
                            SettingsManager.shared.hasSeenWelcome = true
                            authPath.append(AuthDestination.signUp)
                        },
                        onLogIn: {
                            SettingsManager.shared.hasSeenWelcome = true
                            authPath.append(AuthDestination.login)
                        }
                    )
                } else {
                    LoginView(viewModel: authViewModel)
                }
            }
            .navigationDestination(for: AuthDestination.self) { destination in
                switch destination {
                case .signUp:
                    SignUpView(viewModel: authViewModel)
                case .login:
                    LoginView(viewModel: authViewModel, showNavBar: true)
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
                coordinator: AppCoordinator(modelContext: modelContext, authService: FirebaseAuthService.shared),
                selectedTab: $selectedTab,
                authService: FirebaseAuthService.shared,
                onCreateAccount: { showSignUpFromGuest = true }
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

            // Guilds Tab (R3a) — GuildView mounts as-is (its own NavigationStack + guest card).
            GuildView(
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
        // R2 D1: mount the custom bar as a bottom safe-area inset (was a VStack sibling).
        // This gives every tab's scroll content automatic bottom clearance (fixes the
        // Settings tap-target bug) and lets flat-theme content scroll under the
        // translucent bar. The bar branch is unchanged; only its container moved.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if settings.isCleanUI {
                CleanTabBar(selectedTab: $selectedTab)
            } else {
                WoodenTabBar(selectedTab: $selectedTab)
            }
        }
        // R7b §1 refresh triggers (exactly three; no new infrastructure): first appear, tab
        // switch, and scenePhase → .active. The VM (read by the top bar mounted above this
        // TabView in `body`) is built lazily here because `modelContext` is available in
        // `.task` but not at `init`. Known/accepted staleness: logging food while staying on one
        // tab updates the bar on the next trigger, not instantly.
        .task {
            if topBarViewModel == nil {
                topBarViewModel = TopBarViewModel(
                    coordinator: AppCoordinator(modelContext: modelContext, authService: FirebaseAuthService.shared)
                )
            }
            await topBarViewModel?.load()
        }
        .onChange(of: selectedTab) { _, _ in
            Task { await topBarViewModel?.load() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await topBarViewModel?.load() } }
        }
        // R2 §1 keyboard: a `.safeAreaInset` bottom bar otherwise rises with the keyboard.
        // Keep it anchored to the screen bottom (text entry lives in sheets/scroll views that
        // handle their own field reveal).
        .ignoresSafeArea(.keyboard, edges: .bottom)
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
                // R3a: tab 3 is now Guilds (Friends moved to a push off Home).
                // TODO-preview-friends: repoint to the pushed FriendsView when a hook exists.
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
        ("shield.fill", "Guilds", 3),
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

// MARK: - Clean Tab Bar (Erewhon)

/// Erewhon flat tab bar (name retained from the retired Clean era — R1 D3). Full-width
/// and translucent so scroll content passes under it, with a raised center Battle
/// control. Mounted via `.safeAreaInset(edge: .bottom)` (ContentView.mainTabView), which
/// supplies the home-indicator region automatically. Matches design/erewhon/arena.html.
struct CleanTabBar: View {
    @Binding var selectedTab: Int
    private var tc: ThemeColors { SettingsManager.shared.activeColors }

    @State private var battlePressed = false

    // Two side tabs per side of the center Battle slot. Outline SF Symbols to match the
    // mockup's 1.6-stroke line icons.
    private let leftTabs: [(icon: String, label: String, tag: Int)] = [
        ("house", "Home", 0),
        ("fork.knife", "Food", 1)
    ]
    private let rightTabs: [(icon: String, label: String, tag: Int)] = [
        ("shield", "Guilds", 3),
        ("person", "Profile", 4)
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(leftTabs, id: \.tag) { sideTab($0) }
            centerBattle
            ForEach(rightTabs, id: \.tag) { sideTab($0) }
        }
        .frame(height: DesignSystem.Erewhon.tabBarContentHeight)   // 64
        .padding(.top, 12)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(barBackground)
        .animation(DesignSystem.Erewhon.ease(0.35), value: selectedTab)
    }

    // MARK: Side tab
    @ViewBuilder
    private func sideTab(_ tab: (icon: String, label: String, tag: Int)) -> some View {
        let isActive = selectedTab == tab.tag
        Button {
            selectedTab = tab.tag
        } label: {
            VStack(spacing: 5) {
                Image(systemName: tab.icon)
                    .font(.system(size: 22, weight: .regular))
                    .offset(y: isActive ? -1 : 0)          // active icon lift
                Text(tab.label)
                    .font(isActive ? AppFont.bold(10) : AppFont.regular(10))
            }
            .foregroundColor(isActive ? tc.tabActive : tc.textTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.label)
    }

    // MARK: Center Battle button + caption
    private var centerBattle: some View {
        let isActive = selectedTab == 2
        return VStack(spacing: 4) {
            Button {
                selectedTab = 2
            } label: {
                RoundedRectangle(cornerRadius: 14)
                    .fill(isActive ? tc.primary : tc.cardBackground)
                    .frame(width: 46, height: 46)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(isActive ? tc.primary : DesignSystem.Erewhon.line, lineWidth: 1)
                    )
                    .overlay(
                        Image(systemName: "flag.2.crossed")   // TODO: custom crossed-swords glyph (unchanged from pre-R2)
                            .font(.system(size: 20, weight: .regular))
                            .foregroundColor(isActive ? DesignSystem.Erewhon.onAccent : tc.textSecondary)
                    )
                    .overlay(alignment: .topTrailing) { BattleTabBadge(tag: 2, tc: tc) }
                    .shadow(
                        color: isActive ? tc.primary.opacity(0.34) : DesignSystem.Erewhon.subtleShadow.color,
                        radius: isActive ? 8 : DesignSystem.Erewhon.subtleShadow.radius,
                        x: 0,
                        y: isActive ? 6 : DesignSystem.Erewhon.subtleShadow.y
                    )
                    .scaleEffect(battlePressed ? 0.95 : 1.0)
                    .animation(DesignSystem.Erewhon.ease(0.3), value: battlePressed)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in battlePressed = true }
                    .onEnded { _ in battlePressed = false }
            )
            .accessibilityLabel("Battle")

            Text("Battle")   // app vocabulary; mockup caption reads "Arena" (copy deviation — noted)
                .font(isActive ? AppFont.bold(10) : AppFont.regular(10))
                .foregroundColor(isActive ? tc.tabActive : tc.textTertiary)
        }
        .frame(width: 62)
        .offset(y: -3)       // raise ~3pt above the side-tab content top (mockup battle-btn top:9 vs content 12)
    }

    // MARK: Bar background — blur + bg fade + top hairline, extending into the bottom safe area.
    private var barBackground: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            LinearGradient(
                stops: [
                    .init(color: tc.primaryBackground, location: 0.0),          // solid at the bottom
                    .init(color: tc.primaryBackground.opacity(0.8), location: 0.3),
                    .init(color: tc.primaryBackground.opacity(0), location: 1.0) // transparent at the top
                ],
                startPoint: .bottom, endPoint: .top
            )
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(DesignSystem.Erewhon.lineSoft)
                .frame(height: 1)
        }
        .ignoresSafeArea(edges: .bottom)
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
