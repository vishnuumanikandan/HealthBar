//
//  BattleView.swift
//  HealthBar
//
//  Created by Claude on 7/3/26.
//

import SwiftUI

/// The Battle tab (D1a): lists the user's duels in four sections (incoming /
/// outgoing / active / finished) and opens the challenge sheet. Guests see the
/// existing sign-in card and trigger zero duel I/O. Fetch-on-view + pull-to-refresh.
struct BattleView: View {

    @State private var viewModel: BattleViewModel

    /// Retained to construct the ChallengeSheet.
    private let coordinator: AppCoordinator
    /// Read-only — gates the guest empty-state.
    private let authService: any AuthService
    /// Triggers the existing guest → signup path (provided by ContentView).
    private let onCreateAccount: () -> Void

    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }

    @State private var showingChallenge = false
    @State private var showingMatchmaking = false
    @State private var showingLeaderboard = false
    @State private var duelToForfeit: DuelDTO?
    /// Navigate by duelId (String is Hashable — navigationDestination(item:) requires Hashable,
    /// which DuelDTO is not; the destination looks the duel up). Keeps DuelDTO untouched.
    @State private var arenaDuelId: String?

    /// Macro Guess QTE (D1d) — presented from the Battle card; the gate reloads on finish.
    @State private var showMacroQTE = false
    @State private var macroGuessPlayedToday = false

    // MARK: - Init

    init(
        coordinator: AppCoordinator,
        authService: any AuthService,
        onCreateAccount: @escaping () -> Void = {}
    ) {
        self._viewModel = State(initialValue: BattleViewModel(
            coordinator: coordinator,
            myUid: authService.currentUserEmail ?? ""
        ))
        self.coordinator = coordinator
        self.authService = authService
        self.onCreateAccount = onCreateAccount
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                tc.primaryBackground.ignoresSafeArea()

                if authService.isGuest {
                    guestCard
                } else {
                    content
                }

                if let message = viewModel.toastMessage {
                    toast(message)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Battle")
                        .font(AppFont.bold(20))
                        .foregroundColor(tc.textPrimary)
                }
            }
            .navigationDestination(item: $arenaDuelId) { id in
                if let duel = viewModel.duels.first(where: { $0.id == id }) {
                    ArenaView(coordinator: coordinator, myUid: authService.currentUserEmail ?? "", duel: duel)
                } else {
                    Color.clear.onAppear { arenaDuelId = nil } // duel gone from the list
                }
            }
            .navigationDestination(isPresented: $showingLeaderboard) {
                GlobalLeaderboardView(coordinator: coordinator, myUid: authService.currentUserEmail ?? "")
            }
        }
        .task {
            // Guests never load; load once per appearance (pull-to-refresh re-loads).
            guard !authService.isGuest else { return }
            if !viewModel.didLoadOnce { await viewModel.load() }
            macroGuessPlayedToday = (await coordinator.todayQTEState())?.macroGuessPlayed ?? false
            consumePendingArena()
        }
        .onChange(of: DuelUIState.shared.pendingArenaDuelId) { _, id in
            guard id != nil else { return }
            consumePendingArena()
        }
        .sheet(item: currentResolutionBinding) { summary in
            DuelRecapSheet(summary: summary)
        }
        .sheet(isPresented: $showingChallenge) {
            ChallengeSheet(coordinator: coordinator) {
                Task { await viewModel.load() }
            }
        }
        .sheet(isPresented: $showingMatchmaking) {
            MatchmakingSheet(coordinator: coordinator, myUid: authService.currentUserEmail ?? "") { duel in
                // Reload so the new active duel is in the list, then push its Arena (D1c nav).
                Task {
                    await viewModel.load()
                    arenaDuelId = duel.id
                }
            }
        }
        .sheet(isPresented: $showMacroQTE) {
            MacroGuessQTESheet(coordinator: coordinator, dateKey: QTEDay.dateKey(for: Date())) {
                Task { macroGuessPlayedToday = (await coordinator.todayQTEState())?.macroGuessPlayed ?? false }
            }
        }
        .confirmationDialog(
            "Forfeit this duel?",
            isPresented: Binding(
                get: { duelToForfeit != nil },
                set: { if !$0 { duelToForfeit = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Forfeit", role: .destructive) {
                if let duel = duelToForfeit { Task { await viewModel.forfeit(duel) } }
                duelToForfeit = nil
            }
            Button("Cancel", role: .cancel) { duelToForfeit = nil }
        } message: {
            Text("Forfeiting counts as a loss and costs RR.")
        }
        .onChange(of: viewModel.toastMessage) { _, message in
            guard message != nil else { return }
            Task {
                try? await Task.sleep(for: .seconds(3))
                viewModel.toastMessage = nil
            }
        }
    }

    // MARK: - Guest State

    private var guestCard: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: "flag.2.crossed.fill") // TODO: replace with custom crossed-swords pixel asset
                .font(AppFont.regular(44))
                .foregroundColor(tc.textTertiary)

            Text("Sign in to duel")
                .font(AppFont.bold(20))
                .foregroundColor(tc.textPrimary)

            Text("Duels are head-to-head competitions with your friends and guild-mates. Create a free account to challenge someone.")
                .font(AppFont.regular(14))
                .foregroundColor(tc.textSecondary)
                .multilineTextAlignment(.center)

            AppButton(title: "Create Account", style: .primary, action: { onCreateAccount() })
        }
        .padding(DesignSystem.Spacing.lg)
        .adaptiveCard(borderColor: tc.primary.opacity(0.3), fillColor: tc.cardBackground)
        .padding(DesignSystem.Spacing.lg)
    }

    // MARK: - Main Content

    private var content: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.lg) {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    AppButton(title: "Challenge Someone", style: .primary,
                              action: { showingChallenge = true }, icon: "flag.2.crossed.fill")
                    AppButton(title: "Find Match", style: .secondary,
                              action: { showingMatchmaking = true }, icon: "bolt.horizontal.fill")
                }

                AppButton(title: "Leaderboard", style: .secondary,
                          action: { showingLeaderboard = true }, icon: "trophy.fill")

                macroGuessCard

                if viewModel.isEmpty && viewModel.didLoadOnce {
                    emptyState
                } else {
                    section("Incoming Challenges", viewModel.incoming) { incomingRow($0) }
                    section("Outgoing Challenges", viewModel.outgoing) { outgoingRow($0) }
                    section("Active Duels", viewModel.active) { activeRow($0) }
                    section("Finished", viewModel.finished) { finishedRow($0) }
                }
            }
            .padding(DesignSystem.Spacing.lg)
        }
        .refreshable { await viewModel.load() }
        // R2 §5: reserve the tab bar's height so the bottom duel sections clear the
        // translucent bar (the TabView's safeAreaInset doesn't reach this ScrollView).
        .contentMargins(.bottom, DesignSystem.Erewhon.tabBarContentHeight + 12, for: .scrollContent)
    }

    // MARK: - Macro Guess QTE (D1d)

    @ViewBuilder
    private var macroGuessCard: some View {
        if !viewModel.active.isEmpty && !macroGuessPlayedToday {
            Button { showMacroQTE = true } label: {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Image(systemName: "questionmark.circle.fill").foregroundColor(tc.primary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Macro Guess").font(AppFont.bold(14)).foregroundColor(tc.textPrimary)
                        Text("Guess right, score duel points").font(AppFont.regular(12)).foregroundColor(tc.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(AppFont.regular(12)).foregroundColor(tc.textTertiary)
                }
                .padding(DesignSystem.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .adaptiveCard(borderColor: tc.primary.opacity(0.25), fillColor: tc.cardBackground)
            }
            .buttonStyle(.plain)
        }
    }

    private var emptyState: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            Text("No duels yet — challenge a friend ⚔️")
                .font(AppFont.regular(15))
                .foregroundColor(tc.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignSystem.Spacing.xl)
    }

    // MARK: - Section scaffold

    @ViewBuilder
    private func section(_ title: String, _ duels: [DuelDTO], @ViewBuilder row: @escaping (DuelDTO) -> some View) -> some View {
        if !duels.isEmpty {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                Text(title)
                    .font(AppFont.bold(15))
                    .foregroundColor(tc.textPrimary)
                ForEach(duels) { duel in
                    row(duel)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Rows

    private func incomingRow(_ duel: DuelDTO) -> some View {
        let canAccept = viewModel.canAccept(duel)
        return duelCard {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                header(name: viewModel.counterpartLabel(duel), league: duel.league)
                countdown(label: "Responds", date: duel.respondBy)
                HStack(spacing: DesignSystem.Spacing.sm) {
                    // D2.6: Accept is gated by my active-duel cap for this league; Decline always allowed.
                    AppButton(title: "Accept", style: .primary, action: { Task { await viewModel.accept(duel) } },
                              isLoading: viewModel.isInFlight(duel), isDisabled: viewModel.isInFlight(duel) || !canAccept)
                    AppButton(title: "Decline", style: .secondary, action: { Task { await viewModel.decline(duel) } },
                              isDisabled: viewModel.isInFlight(duel))
                }
                .padding(.top, DesignSystem.Spacing.xs)
                if !canAccept {
                    Text("League full")
                        .font(AppFont.regular(10))
                        .foregroundColor(tc.textTertiary)
                }
            }
        }
    }

    private func outgoingRow(_ duel: DuelDTO) -> some View {
        duelCard {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                header(name: viewModel.counterpartLabel(duel), league: duel.league)
                countdown(label: "Responds", date: duel.respondBy)
                AppButton(title: "Cancel", style: .secondary, action: { Task { await viewModel.cancel(duel) } },
                          isLoading: viewModel.isInFlight(duel), isDisabled: viewModel.isInFlight(duel))
                    .padding(.top, DesignSystem.Spacing.xs)
            }
        }
    }

    private func activeRow(_ duel: DuelDTO) -> some View {
        duelCard {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                header(name: viewModel.counterpartLabel(duel), league: duel.league)
                if let endAt = duel.endAt {
                    countdown(label: "Ends", date: endAt)
                }
                Text(viewModel.scoreLine(duel))
                    .font(AppFont.bold(15))
                    .foregroundColor(viewModel.iAmLeading(duel) ? tc.primary : tc.textPrimary)
            }
        }
        .contextMenu {
            Button("Forfeit", role: .destructive) { duelToForfeit = duel }
        }
        .onTapGesture { arenaDuelId = duel.id }
    }

    private func finishedRow(_ duel: DuelDTO) -> some View {
        duelCard {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Text(viewModel.counterpartLabel(duel))
                        .font(AppFont.regular(14))
                        .foregroundColor(tc.textSecondary)
                    Spacer()
                    Text(viewModel.finishedLabel(duel).uppercased())
                        .font(AppFont.bold(12))
                        .foregroundColor(tc.textPrimary)
                    if let delta = viewModel.rrDeltaText(duel) {
                        Text(delta)
                            .font(AppFont.bold(12))
                            .foregroundColor(tc.textSecondary)
                    }
                }
                if viewModel.canRematch(duel) {
                    AppButton(title: "Rematch", style: .secondary,
                              action: { Task { await viewModel.rematch(duel) } },
                              isDisabled: viewModel.isInFlight(duel))
                }
            }
        }
        .onTapGesture {
            if duel.statusEnum == .resolved || duel.statusEnum == .forfeited { arenaDuelId = duel.id }
        }
    }

    // MARK: - Row pieces

    private func header(name: String, league: Int) -> some View {
        HStack {
            Text(name)
                .font(AppFont.bold(16))
                .foregroundColor(tc.textPrimary)
            Spacer()
            leagueBadge(league)
        }
    }

    private func leagueBadge(_ league: Int) -> some View {
        Text(leagueLabel(league))
            .font(AppFont.bold(10))
            .foregroundColor(tc.primary)
            .padding(.horizontal, DesignSystem.Spacing.sm)
            .padding(.vertical, 3)
            .background(tc.primary.opacity(0.15))
            .clipShape(Capsule())
    }

    private func leagueLabel(_ league: Int) -> String { "\(league)-DAY" }

    private func countdown(label: String, date: Date) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(AppFont.regular(12))
                .foregroundColor(tc.textTertiary)
            Text(date, style: .relative)
                .font(AppFont.regular(12))
                .foregroundColor(tc.textSecondary)
        }
    }

    private func duelCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(DesignSystem.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .adaptiveCard(borderColor: tc.primary.opacity(0.25), fillColor: tc.cardBackground)
    }

    // MARK: - Toast

    private func toast(_ message: String) -> some View {
        VStack {
            Spacer()
            Text(message)
                .font(AppFont.regular(14))
                .foregroundColor(.white)
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .background(Color.black.opacity(0.8))
                .clipShape(Capsule())
                .padding(.bottom, DesignSystem.Spacing.xl)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - D1c: Arena deep link + recap sheet

    /// Consume a Home→Battle Arena deep link once the target duel is available.
    private func consumePendingArena() {
        guard let id = DuelUIState.shared.pendingArenaDuelId else { return }
        if let duel = viewModel.duels.first(where: { $0.id == id }),
           duel.statusEnum == .active || duel.statusEnum == .resolved || duel.statusEnum == .forfeited {
            arenaDuelId = id
            DuelUIState.shared.pendingArenaDuelId = nil            // consume once
        } else if viewModel.didLoadOnce {
            DuelUIState.shared.pendingArenaDuelId = nil            // loaded but gone/ineligible
        }
        // else: not loaded yet — leave it for the post-load .task to consume.
    }

    /// Drives the recap sheet from the shared queue; dismissing one presents the next.
    private var currentResolutionBinding: Binding<DuelResolutionSummary?> {
        Binding(
            get: { DuelUIState.shared.pendingResolutions.first },
            set: { if $0 == nil { DuelUIState.shared.dequeueResolution() } }
        )
    }
}
