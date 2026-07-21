//
//  ProfileView.swift
//  HealthBar
//
//  Created by Claude on 1/23/26.
//

import SwiftUI
import SwiftData

/// Profile screen showing user stats and settings
///
/// Features:
/// - User avatar (placeholder)
/// - Current stats (XP, Level, Rank, Streaks)
/// - Settings section with navigation to goal editing
struct ProfileView: View {

    // MARK: - Properties

    /// The view model managing this view's state
    @State private var viewModel: ProfileViewModel

    /// Coordinator for navigation
    private let coordinator: AppCoordinator

    /// R7b §2: presents the pushed SettingsView. The settings section moved off Profile behind
    /// the toolbar gear; all the individual sheet/cover state moved into SettingsView with it.
    @State private var showingSettings = false

    /// Selected badge for detail sheet
    @State private var selectedBadge: BadgeDefinition? = nil

    /// Settings manager for app-wide settings
    @State private var settings = SettingsManager.shared

    /// Theme colors shortcut
    private var tc: ThemeColors { settings.activeColors }

    /// Callback that ends the auth session and returns to LoginView.
    /// Provided by ContentView — ProfileView never references the auth service directly.
    private let onLogout: () -> Void

    /// Callback invoked when a guest user taps "Create Account" in the upsell banner.
    /// ContentView presents the sign-up sheet in response.
    private let onCreateAccount: () -> Void

    /// Auth service reference — read-only, used only to check isGuest and isNewUser.
    /// ProfileView never calls methods on this directly.
    private let authService: any AuthService

    // MARK: - Initialization

    init(
        coordinator: AppCoordinator,
        authService: any AuthService,
        onLogout: @escaping () -> Void,
        onCreateAccount: @escaping () -> Void = {}
    ) {
        self.coordinator = coordinator
        self.authService = authService
        self.onLogout = onLogout
        self.onCreateAccount = onCreateAccount
        self._viewModel = State(initialValue: ProfileViewModel(coordinator: coordinator, authService: authService))
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                // Background color
                tc.primaryBackground
                    .ignoresSafeArea()

                if viewModel.isLoading {
                    loadingView
                } else if let error = viewModel.errorMessage {
                    errorView(error)
                } else {
                    contentView
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            // R7c §4: the "Profile" title is gone (the in-content head is the header), but the gear
            // remains — so this root keeps its nav bar rather than hiding it.
            .toolbar {
                // R7b §2: the gear opens the pushed SettingsView (the settings section moved
                // off Profile). Icon-only, so it carries an explicit accessibility label.
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(AppFont.regular(17))
                            .foregroundColor(tc.textPrimary)
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .refreshable {
                await viewModel.refresh()
            }
            .task {
                // Load data when view appears
                await viewModel.loadUserData()
            }
            .sheet(item: $selectedBadge) { badge in
                BadgeDetailSheet(
                    definition: badge,
                    progress: viewModel.badgeProgressList.first { $0.badgeId == badge.id }
                )
            }
            // R7b §2: settings are a pushed screen now (FriendsView push precedent), inside
            // Profile's existing NavigationStack.
            .navigationDestination(isPresented: $showingSettings) {
                SettingsView(
                    coordinator: coordinator,
                    authService: authService,
                    onLogout: onLogout,
                    existingProfile: viewModel.existingProfile
                )
            }
            // R7b §2: one on-return reload replaces the per-sheet reloads that moved into
            // SettingsView — Daily Goals / Health Profile edits show once Profile reappears.
            .onChange(of: showingSettings) { _, showing in
                if !showing {
                    Task { await viewModel.loadUserData() }
                }
            }
        }
    }

    // MARK: - Subviews

    /// Loading indicator
    private var loadingView: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading your profile...")
                .font(AppFont.regular(16))
                .foregroundColor(tc.textSecondary)
        }
    }

    /// Error view
    private func errorView(_ message: String) -> some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Image(systemName: "exclamationmark.triangle")
                .font(AppFont.regular(64))
                .foregroundStyle(DesignSystem.Colors.danger)

            VStack(spacing: DesignSystem.Spacing.sm) {
                Text("Error Loading Profile")
                    .font(AppFont.bold(22))
                    .foregroundColor(tc.textPrimary)

                Text(message)
                    .font(AppFont.regular(16))
                    .foregroundColor(tc.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DesignSystem.Spacing.xl)
            }

            AppButton(
                title: "Try Again",
                style: .primary,
                action: {
                    Task {
                        await viewModel.loadUserData()
                    }
                }
            )
            .padding(.horizontal, DesignSystem.Spacing.xl)
        }
        .padding()
    }

    /// Main content when data is loaded
    private var contentView: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.lg) {
                // Guest mode upsell banner — shown above all other content
                if authService.isGuest {
                    guestBanner
                }
                // D1 section order: Header → RANK → GUILD → STATS → BADGES → GOAL CALENDAR.
                // Each section (except the header) carries its own leading rule + uppercase
                // label; guildSection and calendarSection hide themselves entirely when empty.
                headerSection
                rankSection
                guildSection
                statsSection
                badgesSection
                calendarSection
            }
            .padding(DesignSystem.Spacing.lg)
        }
        // R2 §5 conditional: the tab bar is mounted as a `.safeAreaInset` on the TabView,
        // but that inset does not propagate through this tab's NavigationStack to the
        // ScrollView. Reserve the bar's height as scroll-content margin so the bottom
        // Settings rows (About / Sign Out) clear the bar and stay tappable in both
        // families (fixes the Finding-#1 tap-target bug).
        .contentMargins(.bottom, DesignSystem.Erewhon.tabBarContentHeight + 12, for: .scrollContent)
    }

    // MARK: - Guest Banner

    /// Shown at the top of the profile when the user has no account.
    /// Explains local-only storage and offers a path to sign up.
    private var guestBanner: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Your data is stored locally on this device. It may be lost if the app is deleted. Create a free account to back up your progress.")
                .font(AppFont.regular(12))
                .foregroundColor(tc.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            AppButton(
                title: "Create Account",
                style: .primary,
                action: { onCreateAccount() }
            )
        }
        .padding(DesignSystem.Spacing.md)
        .adaptiveCard(borderColor: tc.macroBarCarbs, fillColor: tc.cardBackground)
    }

    // MARK: - Header Section

    /// Identity header: avatar, displayName, @username (username row stays hidden for guests,
    /// as today). D2 removed the rank pill and its `crown.fill` from the header — the Rank
    /// Journey card is now rank's single home.
    private var headerSection: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            // Avatar — pixel-bordered square portrait
            ZStack {
                AdaptiveCardShapeStyle()
                    .fill(DesignSystem.Colors.adaptiveGradient(light: tc.buttonLight, mid: tc.buttonMid, dark: tc.buttonDark))
                    .frame(width: 100, height: 100)

                Text(viewModel.userInitials)
                    .font(AppFont.bold(42))
                    .foregroundColor(.white)
            }
            .clipShape(AdaptiveCardShapeStyle())

            Text(viewModel.displayName)
                .font(AppFont.bold(22))
                .foregroundColor(tc.textPrimary)

            if let username = viewModel.username, !username.isEmpty {
                Text("@\(username)")
                    .font(AppFont.regular(14))
                    .foregroundColor(tc.textSecondary)
            }
        }
        .padding(.vertical, DesignSystem.Spacing.md)
    }

    // MARK: - Section Chrome (D1)

    /// D1: a bold 3pt rounded separator between sections, full content width. Token-colored —
    /// D8 permits this small primitive (and the calendar cells) outside adaptiveCard.
    private var sectionRule: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(tc.textTertiary.opacity(0.2))
            .frame(height: 3)
            .frame(maxWidth: .infinity)
    }

    /// D1: uppercase section label, styled with an existing secondary text token.
    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(AppFont.bold(13))
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundColor(tc.textSecondary)
    }

    // MARK: - Rank Section (D3 + D4)

    /// RANK section: the Rank Journey card and the slim level strip.
    private var rankSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            sectionRule
            sectionLabel("Rank")
            rankJourneyCard
            levelStrip
        }
    }

    /// D3 Rank Journey card — driven purely by `userProgress.rr` via Rank.swift's API. Renders
    /// only once progress is loaded (no invented default RR, no force-unwrap); before load the
    /// region participates in the page's loading state.
    @ViewBuilder
    private var rankJourneyCard: some View {
        if let journey = viewModel.rankJourney {
            // rankMetal returns nil for Stone (and nil rr); FriendProfileView.rankColor is the
            // canonical per-rank switch, but D8 forbids new hex here, so fall back to the neutral
            // textTertiary token (the established `?? tc.textTertiary` FriendsView pattern).
            let accent = DesignSystem.Erewhon.rankMetal(forRR: journey.rr) ?? tc.textTertiary
            VStack(spacing: DesignSystem.Spacing.md) {
                HStack(spacing: DesignSystem.Spacing.md) {
                    RankPlaque(rank: journey.rank, size: 48)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(journey.tierTitle)
                            .font(AppFont.bold(22))
                            .foregroundColor(tc.textPrimary)
                        Text(journey.subline)
                            .font(AppFont.regular(13))
                            .foregroundColor(tc.textSecondary)
                            .monospacedDigit()
                    }

                    Spacer()
                }

                if journey.isPeak {
                    // Peak state: bar + caption replaced by a single line (D3).
                    Text("Peak of the ladder")
                        .font(AppFont.bold(14))
                        .foregroundColor(accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    // Progress bar: fill = (rr − currentTierFloor) / Rank.rrPerTier, clamped 0…1.
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            AdaptivePillShapeStyle()
                                .fill(accent.opacity(0.18))
                            AdaptivePillShapeStyle()
                                .fill(accent)
                                .frame(width: max(0, geo.size.width * journey.fill))
                        }
                    }
                    .frame(height: 8)

                    // Caption: left = current tier name; right = "<remaining> RR to <next>"
                    // (ascending — next tier in-rank, or the next rank's tier 1 at tier 3).
                    HStack {
                        Text(journey.tierTitle)
                        Spacer()
                        Text(journey.captionRight)
                    }
                    .font(AppFont.regular(12))
                    .foregroundColor(tc.textSecondary)
                    .monospacedDigit()
                }
            }
            .padding(DesignSystem.Spacing.md)
            .adaptiveCard(borderColor: accent.opacity(0.4), fillColor: tc.cardBackground)
        }
    }

    /// D4 level strip — the existing XP-progress data restyled into a slim card. One row
    /// "Level N · x / 100 XP · Level N+1 →" over a thin bar (existing gradient tokens).
    private var levelStrip: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            HStack(spacing: DesignSystem.Spacing.xs) {
                Text("Level \(viewModel.currentLevel)")
                    .font(AppFont.bold(13))
                    .foregroundColor(tc.textPrimary)
                Text("·")
                    .font(AppFont.regular(13))
                    .foregroundColor(tc.textTertiary)
                Text("\(viewModel.xpWithinLevel) / 100 XP")
                    .font(AppFont.regular(13))
                    .foregroundColor(tc.textSecondary)
                    .monospacedDigit()
                Spacer()
                Text("Level \(viewModel.nextLevel) →")
                    .font(AppFont.regular(13))
                    .foregroundColor(tc.textTertiary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    AdaptivePillShapeStyle()
                        .fill(tc.primary.opacity(0.3))
                    AdaptivePillShapeStyle()
                        .fill(DesignSystem.Colors.adaptiveGradient(light: tc.buttonLight, mid: tc.buttonMid, dark: tc.buttonDark))
                        .frame(width: max(0, geo.size.width * viewModel.levelProgress))
                }
            }
            .frame(height: 6)
        }
        .padding(DesignSystem.Spacing.md)
        .adaptiveCard(borderColor: tc.primary.opacity(0.3), fillColor: tc.cardBackground)
    }

    // MARK: - Guild Section (D6)

    /// GUILD section — display-only guild row. Hidden ENTIRELY (rule + label + row) when the
    /// user has no guild, when the fetch failed, or for guests (all collapse `loadedGuild` to nil).
    @ViewBuilder
    private var guildSection: some View {
        if let guild = viewModel.loadedGuild {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                sectionRule
                sectionLabel("Guild")
                HStack(spacing: DesignSystem.Spacing.md) {
                    Image(systemName: "shield.fill")
                        .font(AppFont.bold(20))
                        .foregroundColor(tc.primary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(guild.name)
                            .font(AppFont.bold(16))
                            .foregroundColor(tc.textPrimary)
                        Text("Guild")
                            .font(AppFont.regular(12))
                            .foregroundColor(tc.textSecondary)
                    }
                    Spacer()
                }
                // TODO-guild-row-tap: GUILD-UI-1 — display-only, no tap action this prompt.
                .padding(DesignSystem.Spacing.md)
                .adaptiveCard(borderColor: tc.primary.opacity(0.3), fillColor: tc.cardBackground)
            }
        }
    }

    // MARK: - Stats Section (D5)

    /// STATS section — a 2×2 grid: Meals Logged, Total XP, Longest Streak, Duel Record.
    /// (Current Streak headlines Home; Level lives in the strip — both were removed here.) The
    /// Duel cell is omitted for guests (D9), leaving a 3-cell grid.
    private var statsSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            sectionRule
            sectionLabel("Stats")

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: DesignSystem.Spacing.md) {
                // Meals Logged (F1a) — nil (load failure) renders "—".
                pixelStatCell(
                    icon: "fork.knife",
                    title: "Meals Logged",
                    value: viewModel.mealsLogged.map { "\($0)" } ?? "—",
                    iconColor: tc.primary
                )

                // Total XP
                pixelStatCell(
                    icon: "star.fill",
                    title: "Total XP",
                    value: viewModel.totalXPText,
                    iconColor: tc.primary
                )

                // Longest Streak — "—" if progress is unavailable.
                pixelStatCell(
                    icon: "flame.fill",
                    title: "Longest Streak",
                    value: viewModel.userProgress.map { "\($0.longestStreak) day\($0.longestStreak == 1 ? "" : "s")" } ?? "—",
                    iconColor: tc.macroBarFat
                )

                // Duel Record — guest-hidden (D9).
                if !authService.isGuest {
                    duelRecordCell
                }
            }
        }
    }

    /// D5 Duel Record cell: wins–losses, wins green / losses red, en-dash separator. Both
    /// counters exist locally (`UserProgress.duelWins` / `.duelLosses` — the publishMyStats
    /// source), so this is always a W–L cell; wins nil (progress unavailable) → "—".
    @ViewBuilder
    private var duelRecordCell: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "trophy.fill")
                .font(AppFont.bold(20))
                .foregroundColor(tc.primary)

            if let wins = viewModel.duelWins, let losses = viewModel.duelLosses {
                HStack(spacing: 2) {
                    Text("\(wins)")
                        .foregroundColor(DesignSystem.Colors.growth)
                    Text("–")
                        .foregroundColor(tc.textTertiary)
                    Text("\(losses)")
                        .foregroundColor(DesignSystem.Colors.danger)
                }
                .font(AppFont.bold(20))
                .monospacedDigit()
            } else {
                Text("—")
                    .font(AppFont.bold(20))
                    .foregroundColor(tc.textPrimary)
            }

            Text("Duel Record")
                .font(AppFont.regular(12))
                .foregroundColor(tc.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(DesignSystem.Spacing.md)
        .adaptiveCard(borderColor: tc.primary.opacity(0.6), fillColor: tc.cardBackground)
    }

    /// Pixel-styled stat cell for the stats grid
    private func pixelStatCell(
        icon: String,
        title: String,
        value: String,
        iconColor: Color
    ) -> some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: icon)
                .font(AppFont.bold(20))
                .foregroundColor(iconColor)

            Text(value)
                .font(AppFont.bold(20))
                .foregroundColor(tc.textPrimary)

            Text(title)
                .font(AppFont.regular(12))
                .foregroundColor(tc.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(DesignSystem.Spacing.md)
        .adaptiveCard(borderColor: iconColor.opacity(0.6), fillColor: tc.cardBackground)
    }

    // MARK: - Badges Section (D2)

    /// BADGES section — the badge grid, unchanged except a FriendProfileView-style gold
    /// earned/total counter in the section header. Own page counts from `badgeProgressList`
    /// (NOT publishedBadgeCount — that is the friend-view concept).
    private var badgesSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            sectionRule
            HStack {
                sectionLabel("Badges")
                Spacer()
                Text("\(viewModel.earnedBadgeCount)/\(viewModel.totalBadgeCount)")
                    .font(AppFont.bold(13))
                    .foregroundColor(DesignSystem.Colors.goldMid)
                    .monospacedDigit()
            }

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: DesignSystem.Spacing.md) {
                ForEach(BadgeDefinition.all) { badge in
                    let progress = viewModel.badgeProgressList.first { $0.badgeId == badge.id }
                    let earned = progress?.isUnlocked == true

                    Button {
                        selectedBadge = badge
                    } label: {
                        VStack(spacing: DesignSystem.Spacing.xs) {
                            BadgeEmblem(badge, size: 34, isLocked: !earned)
                            Text(badge.title)
                                .font(AppFont.regular(11))
                                .foregroundColor(earned ? tc.textPrimary : tc.textTertiary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(DesignSystem.Spacing.sm)
                        .adaptiveCard(
                            borderColor: earned ? tc.primaryDark : tc.primary.opacity(0.3),
                            fillColor: tc.cardBackground
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }

    // MARK: - Goal Calendar Section (D7)

    /// GOAL CALENDAR section — current month only (`// TODO-calendar-month-nav` — not built).
    /// Hidden entirely when the calendar load failed (`calendarDays == nil`, D10). Every day
    /// state is prebuilt in the VM; the view maps them 1:1 with zero per-cell computation.
    @ViewBuilder
    private var calendarSection: some View {
        if let days = viewModel.calendarDays {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                sectionRule
                sectionLabel("Goal Calendar")
                calendarCard(days)
            }
        }
    }

    private func calendarCard(_ days: [DayCellState]) -> some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            // Header: month + year left, "<n> days hit" right (D7).
            HStack {
                Text(viewModel.calendarMonthTitle)
                    .font(AppFont.bold(16))
                    .foregroundColor(tc.textPrimary)
                Spacer()
                Text("\(viewModel.calendarDaysHit) days hit")
                    .font(AppFont.regular(12))
                    .foregroundColor(tc.textSecondary)
                    .monospacedDigit()
            }

            // Weekday initials header (ordered from Calendar.current.firstWeekday, not Sunday).
            HStack(spacing: DesignSystem.Spacing.xs) {
                ForEach(Array(viewModel.weekdayInitials.enumerated()), id: \.offset) { _, initial in
                    Text(initial)
                        .font(AppFont.regular(11))
                        .foregroundColor(tc.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }

            // 7-column grid: leading blanks align the 1st, then the day cells.
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: DesignSystem.Spacing.xs), count: 7),
                spacing: DesignSystem.Spacing.xs
            ) {
                ForEach(Array(0..<viewModel.calendarLeadingBlanks), id: \.self) { _ in
                    Color.clear.frame(height: 34)
                }
                ForEach(days, id: \.dayNumber) { day in
                    dayCell(day)
                }
            }
        }
        .padding(DesignSystem.Spacing.md)
        .adaptiveCard(borderColor: tc.primary.opacity(0.3), fillColor: tc.cardBackground)
    }

    /// One calendar day cell. met = green fill + on-accent numeral; past-unmet / no-goal =
    /// muted gray fill; future = dashed faint outline; today = an accent ring over its live
    /// state. Token-colored RoundedRectangles (a D8-permitted small primitive).
    private func dayCell(_ day: DayCellState) -> some View {
        let fill: Color
        let numeral: Color
        switch day.state {
        case .met:
            fill = tc.primary
            numeral = DesignSystem.Erewhon.onAccent
        case .unmet:
            fill = tc.textTertiary.opacity(0.15)
            numeral = tc.textSecondary
        case .future:
            fill = Color.clear
            numeral = tc.textTertiary
        }

        return Text("\(day.dayNumber)")
            .font(AppFont.regular(12))
            .foregroundColor(numeral)
            .monospacedDigit()
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(RoundedRectangle(cornerRadius: 8).fill(fill))
            .overlay {
                if day.state == .future {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(tc.textTertiary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3]))
                }
            }
            .overlay {
                if day.isToday {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(tc.primary, lineWidth: 2)
                }
            }
    }

}

// MARK: - BadgeDetailSheet

/// Sheet shown when tapping a badge in the badge grid.
struct BadgeDetailSheet: View {

    let definition: BadgeDefinition
    let progress: BadgeProgress?

    @Environment(\.dismiss) private var dismiss

    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }

    var body: some View {
        NavigationStack {
            ZStack {
                tc.primaryBackground.ignoresSafeArea()

                VStack(spacing: DesignSystem.Spacing.lg) {
                    BadgeEmblem(definition, size: 80, isLocked: !(progress?.isUnlocked ?? false))
                        .padding(.top, DesignSystem.Spacing.lg)

                    VStack(spacing: DesignSystem.Spacing.sm) {
                        Text(definition.title)
                            .font(AppFont.bold(22))
                            .foregroundColor(tc.textPrimary)

                        Text(definition.description)
                            .font(AppFont.regular(16))
                            .foregroundColor(tc.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, DesignSystem.Spacing.xl)
                    }

                    if let progress = progress, progress.isUnlocked, let date = progress.unlockedAt {
                        HStack(spacing: DesignSystem.Spacing.xs) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(tc.primary)
                            Text("Unlocked \(date.formatted(date: .abbreviated, time: .omitted))")
                                .font(AppFont.regular(14))
                                .foregroundColor(tc.textSecondary)
                        }
                    } else {
                        HStack(spacing: DesignSystem.Spacing.xs) {
                            Image(systemName: "lock.fill")
                                .foregroundColor(tc.textTertiary)
                            Text("Not yet unlocked")
                                .font(AppFont.regular(14))
                                .foregroundColor(tc.textTertiary)
                        }
                    }

                    Spacer()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Badge")
                        .font(AppFont.bold(20))
                        .foregroundColor(tc.textPrimary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Profile View") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: FoodEntry.self, DailyGoal.self, UserProgress.self, DailyQuest.self, configurations: config)
    let context = container.mainContext

    // Add sample progress data
    let sampleProgress = UserProgress(
        totalXP: 1250,
        currentStreak: 7,
        longestStreak: 12,
        lastActiveDate: Date()
    )

    let sampleGoal = DailyGoal(
        date: Date(),
        calorieTarget: 2000,
        proteinTarget: 150.0,
        carbTarget: 200.0,
        fatTarget: 65.0,
        purityTarget: 30
    )

    context.insert(sampleProgress)
    context.insert(sampleGoal)

    let coordinator = AppCoordinator(modelContext: context)

    return ProfileView(coordinator: coordinator, authService: LocalAuthService.shared, onLogout: {})
}
