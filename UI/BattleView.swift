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

    /// D4: the existing global-leaderboard VM, owned here to power the inline standings block.
    @State private var leaderboardVM: GlobalLeaderboardViewModel

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
    /// D2: friend to pre-select in ChallengeSheet (set by the matchup card's Challenge CTA).
    @State private var challengePreselect: DuelOpponentCandidate?
    /// D7: session-local collapse for the duel-history block (resets on view recreation).
    @State private var historyExpanded = false
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
        let uid = authService.currentUserEmail ?? ""
        self._viewModel = State(initialValue: BattleViewModel(coordinator: coordinator, myUid: uid))
        self._leaderboardVM = State(initialValue: GlobalLeaderboardViewModel(coordinator: coordinator, myUid: uid))
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
            await leaderboardVM.loadInitial()   // D4: inline standings board (idempotent)
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
            ChallengeSheet(coordinator: coordinator, preselected: challengePreselect) {
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
                arenaHead

                // Featured slot: an active duel's card wins; otherwise the R4b matchup preview
                // (me vs a random friend, or a labelled SAMPLE) when there is no active duel (D2).
                if let featured = viewModel.active.first {
                    featuredCard(featured)
                } else if let preview = viewModel.matchupPreview {
                    matchupPreviewCard(preview)
                }

                actionsRow

                macroGuessCard

                if viewModel.isEmpty && viewModel.didLoadOnce {
                    emptyState
                } else {
                    section("Incoming Challenges", viewModel.incoming) { incomingRow($0) }
                    section("Outgoing Challenges", viewModel.outgoing) { outgoingRow($0) }
                    // Featured duel is excluded from the Active section (D2).
                    section("Active Duels", Array(viewModel.active.dropFirst())) { activeRow($0) }
                    historyBlock   // D7: collapsible "Duel history" (replaces the Finished section)
                }

                standingsBlock   // D4: inline global standings (replaces the leaderboard row)
            }
            .padding(.horizontal, 22)
            .padding(.top, DesignSystem.Spacing.sm)
            .padding(.bottom, DesignSystem.Spacing.lg)
        }
        .refreshable { await viewModel.load() }
        // R2 §5: reserve the tab bar's height so the bottom duel sections clear the
        // translucent bar (the TabView's safeAreaInset doesn't reach this ScrollView).
        .contentMargins(.bottom, DesignSystem.Erewhon.tabBarContentHeight + 12, for: .scrollContent)
    }

    // MARK: - Arena head (D3)

    /// Mockup `.arena-head`: eyebrow cap + display title. No season/subtitle — those
    /// mockup stats don't exist in the app (D3).
    private var arenaHead: some View {
        VStack(spacing: 10) {
            Text("RANKED DUELS")
                .font(AppFont.display(11))
                .tracking(1.1)
                .foregroundColor(tc.primary)
            Text("The Arena")
                .font(AppFont.display(38))
                .foregroundColor(tc.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    // MARK: - Featured versus card (D4)

    /// Mockup `.versus`: two fighter columns around a `.vs-mid`, then ONE score compare
    /// row with paired share bars. Scores/lead/labels come from the DTO + the VM's
    /// rounded-tenths convention (BattleViewModel is not modified — R4 Files list); the
    /// avatars use neutral fills, not the mockup's rank metals (opponent rank isn't in
    /// DuelDTO — noted deviation). Tapping pushes that duel's Arena.
    private func featuredCard(_ duel: DuelDTO) -> some View {
        let myUid = authService.currentUserEmail ?? ""
        let name = viewModel.counterpartLabel(duel)
        let mine = duel.myScore(myUid)
        let theirs = duel.theirScore(myUid)
        let mineInt = Int(mine.rounded())
        let theirsInt = Int(theirs.rounded())
        let iLead = viewModel.iAmLeading(duel)
        let theyLead = Int((theirs * 10).rounded()) > Int((mine * 10).rounded())
        let subline = leagueSubline(duel.league)
        return VStack(spacing: 0) {
            // .duel — fighters + vs-mid
            HStack(alignment: .center, spacing: 0) {
                fighterColumn(initial: "Y", isMe: true, name: nil, subline: subline)
                vsMid
                fighterColumn(initial: initial(for: name), isMe: false, name: name, subline: subline)
            }
            // .compare — one crow + paired share bars
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    Text("\(mineInt)")
                        .font(AppFont.display(18))
                        .foregroundColor(iLead ? tc.primary : DesignSystem.Erewhon.social)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text("Duel score")
                        .font(AppFont.regular(11))
                        .foregroundColor(tc.textTertiary)
                        .frame(minWidth: 84)
                        .multilineTextAlignment(.center)
                    Text("\(theirsInt)")
                        .font(AppFont.display(18))
                        .foregroundColor(theyLead ? tc.primary : tc.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 6) {
                    compareBar(fraction: shareFraction(mine: mine, theirs: theirs, forMine: true),
                               color: DesignSystem.Erewhon.social, fromLeading: false)
                    compareBar(fraction: shareFraction(mine: mine, theirs: theirs, forMine: false),
                               color: tc.primary, fromLeading: true)
                }
            }
            .padding(.top, 24)
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        // borderColor ≠ activeColors.primary → flat hairline (not the accent "selected"
        // border); pixel family gets a faint-primary pixel border, matching the duel rows.
        .adaptiveCard(borderColor: tc.primary.opacity(0.25), fillColor: tc.cardBackground)
        .contentShape(Rectangle())
        .onTapGesture { arenaDuelId = duel.id }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Duel vs \(name), \(subline), you \(mineInt) — \(theirsInt)")
    }

    /// Mockup `.arena-actions`: primary "Find a match" → MatchmakingSheet, ghost
    /// "Challenge a friend" → ChallengeSheet (D2).
    private var actionsRow: some View {
        VStack(spacing: 11) {
            AppButton(title: "Find a match", style: .primary,
                      action: { showingMatchmaking = true }, icon: "bolt.horizontal.fill")
            AppButton(title: "Challenge a friend", style: .secondary,
                      action: { challengePreselect = nil; showingChallenge = true }, icon: "flag.2.crossed.fill")
        }
    }

    /// D4: inline global standings block (seg pickers + top 10 + my row + "View all"). Owns no
    /// logic — renders the BattleView-owned `GlobalLeaderboardViewModel`; "View all" opens the
    /// existing full board via the existing navigation destination.
    private var standingsBlock: some View {
        BattleStandingsBlock(viewModel: leaderboardVM, myUid: authService.currentUserEmail ?? "") {
            showingLeaderboard = true
        }
    }

    // MARK: - Matchup preview card (D2)

    /// The matchup preview: me vs one random friend (or a labelled SAMPLE), shown in the featured
    /// slot when there is no active duel. Reuses the versus/compare language; avatars are metal
    /// (tinted by each side's rr — REAL here, unlike the R4 featured card). "Challenge"
    /// pre-selects the friend in ChallengeSheet.
    private func matchupPreviewCard(_ p: BattleViewModel.MatchupPreview) -> some View {
        VStack(spacing: 0) {
            if p.isSample {
                sampleTag.padding(.bottom, 16)
            }
            HStack(alignment: .top, spacing: 0) {
                fighterColumn(initial: p.myInitial, isMe: true, name: nil,
                              subline: tierLabel(p.myRR), tint: erewhonRankMetal(forRR: p.myRR))
                vsMid
                fighterColumn(initial: p.theirInitial, isMe: false, name: p.opponentName,
                              subline: tierLabel(p.theirRR), tint: erewhonRankMetal(forRR: p.theirRR))
            }
            VStack(spacing: 14) {
                previewCompareRow("Days on goal", mine: "\(p.myDays)", theirs: "\(p.theirDays)",
                                  mineVal: Double(p.myDays), theirsVal: Double(p.theirDays))
                previewCompareRow("Streak", mine: "\(p.myStreak)", theirs: "\(p.theirStreak)",
                                  mineVal: Double(p.myStreak), theirsVal: Double(p.theirStreak))
                previewCompareRow("RR", mine: p.myRR.map { "\($0)" } ?? "—",
                                  theirs: p.theirRR.map { "\($0)" } ?? "—",
                                  mineVal: p.myRR.map(Double.init), theirsVal: p.theirRR.map(Double.init))
            }
            .padding(.top, 22)
            AppButton(title: p.isSample ? "Find an opponent" : "Challenge", style: .primary,
                      action: {
                          challengePreselect = p.candidate
                          showingChallenge = true
                      }, icon: "flag.2.crossed.fill")
                .padding(.top, 20)
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .adaptiveCard(borderColor: tc.primary.opacity(0.25), fillColor: tc.cardBackground)
    }

    /// Mockup `.crow` + `.cbars`: a labelled compare row with paired share bars. My value tints
    /// social (accent when I lead); theirs tints ink (accent when they lead) — same as the
    /// featured card. A nil (unpublished) side reads as "—" with neutral bars.
    private func previewCompareRow(_ label: String, mine: String, theirs: String,
                                   mineVal: Double?, theirsVal: Double?) -> some View {
        let iLead = leads(mineVal, theirsVal)
        let theyLead = leads(theirsVal, mineVal)
        return VStack(spacing: 8) {
            HStack(spacing: 12) {
                Text(mine)
                    .font(AppFont.display(18))
                    .foregroundColor(iLead ? tc.primary : DesignSystem.Erewhon.social)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Text(label)
                    .font(AppFont.regular(11))
                    .foregroundColor(tc.textTertiary)
                    .frame(minWidth: 84)
                    .multilineTextAlignment(.center)
                Text(theirs)
                    .font(AppFont.display(18))
                    .foregroundColor(theyLead ? tc.primary : tc.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 6) {
                compareBar(fraction: barShare(mineVal, theirsVal, forMine: true),
                           color: DesignSystem.Erewhon.social, fromLeading: false)
                compareBar(fraction: barShare(mineVal, theirsVal, forMine: false),
                           color: tc.primary, fromLeading: true)
            }
        }
    }

    /// Mockup eyebrow tag making the SAMPLE card unmistakable as a placeholder (never a real user).
    private var sampleTag: some View {
        HStack {
            Spacer()
            Text("SAMPLE MATCHUP")
                .font(AppFont.display(11))
                .tracking(1.1)
                .foregroundColor(tc.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(tc.segBackground))
            Spacer()
        }
    }

    /// Rank-tier label for a fighter sub-line ("Copper 2"); "Unranked" when rr is unpublished.
    private func tierLabel(_ rr: Int?) -> String {
        rr.map { Rank.rankTier(from: $0).displayName } ?? "Unranked"
    }

    /// True when `a` strictly leads `b` (both published).
    private func leads(_ a: Double?, _ b: Double?) -> Bool {
        guard let a, let b else { return false }
        return a > b
    }

    /// Share fraction for a preview compare bar. An unpublished side → neutral (both 0.5).
    private func barShare(_ mine: Double?, _ theirs: Double?, forMine: Bool) -> Double {
        guard let m = mine, let t = theirs else { return 0.5 }
        if Int(m) == Int(t) { return 0.5 }
        let total = m + t
        guard total > 0 else { return 0.5 }
        return min(0.92, max(0.08, (forMine ? m : t) / total))
    }

    // MARK: - Duel history (D7)

    /// Collapsible "Duel history" block: header shows the W–L–D record + net RR (display figures)
    /// with a chevron; collapsed by default; expanding reveals the existing finished rows
    /// unchanged. Hidden entirely when there are no finished duels.
    @ViewBuilder
    private var historyBlock: some View {
        if !viewModel.finished.isEmpty {
            let stats = viewModel.historyStats
            VStack(spacing: 0) {
                Button {
                    withAnimation(DesignSystem.Erewhon.ease(0.25)) { historyExpanded.toggle() }
                } label: {
                    historyHeader(stats)
                }
                .buttonStyle(.plain)

                if historyExpanded {
                    VStack(spacing: 11) {
                        ForEach(viewModel.finished) { finishedRow($0) }
                    }
                    .padding(.top, 14)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func historyHeader(_ stats: BattleViewModel.DuelHistoryStats) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.sm) {
                Text("Duel history")
                    .font(AppFont.display(15))
                    .foregroundColor(tc.textPrimary)
                Spacer()
                Text(stats.recordText)
                    .font(AppFont.display(15))
                    .foregroundColor(tc.textPrimary)
                Text(stats.netRRText)
                    .font(AppFont.display(13))
                    .foregroundColor(tc.textSecondary)
                Image(systemName: historyExpanded ? "chevron.up" : "chevron.down")
                    .font(AppFont.regular(12))
                    .foregroundColor(tc.textTertiary)
            }
            .padding(.bottom, 10)
            Rectangle()
                .fill(DesignSystem.Erewhon.lineSoft)
                .frame(height: 1)
        }
        .contentShape(Rectangle())
    }

    // MARK: - Fighter pieces (D4)

    /// Mockup `.fighter`: initials avatar, name (mine = the `.you-tag` pill), league sub-line.
    private func fighterColumn(initial: String, isMe: Bool, name: String?, subline: String, tint: Color? = nil) -> some View {
        VStack(spacing: 10) {
            favAvatar(initial: initial, tint: tint)
            if isMe {
                youTag
            } else if let name {
                Text(name)
                    .font(AppFont.bold(14))
                    .foregroundColor(tc.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Text(subline)
                .font(AppFont.regular(10))
                .foregroundColor(tc.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    /// Mockup `.fav`: rounded-square initials avatar. Neutral fill + hairline (no rank
    /// metal — opponent rank isn't tracked; D4 deviation).
    private func favAvatar(initial: String, tint: Color? = nil) -> some View {
        Text(initial)
            .font(AppFont.bold(23))
            .foregroundColor(tint != nil ? .white : tc.textPrimary)
            .frame(width: 60, height: 60)
            .background(RoundedRectangle(cornerRadius: 19).fill(tint ?? tc.segBackground))
            .overlay(
                RoundedRectangle(cornerRadius: tint != nil ? 14 : 19)
                    .stroke(tint != nil ? Color.white.opacity(0.25) : DesignSystem.Erewhon.line, lineWidth: 1)
                    .padding(tint != nil ? 5 : 0)
            )
    }

    /// Mockup `.you-tag`: social-tinted "YOU" pill (a badge — stays Hanken per D1).
    private var youTag: some View {
        Text("You")
            .font(AppFont.bold(9))
            .tracking(0.4)
            .textCase(.uppercase)
            .foregroundColor(DesignSystem.Erewhon.social)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6).fill(DesignSystem.Erewhon.social.opacity(0.14)))
    }

    /// Mockup `.vs-mid`: hairline verticals around the italic display "vs" (D1: "vs" mark).
    private var vsMid: some View {
        VStack(spacing: 8) {
            Rectangle().fill(DesignSystem.Erewhon.line).frame(width: 1, height: 26)
            Text("vs")
                .font(AppFont.display(22))
                .italic()
                .foregroundColor(tc.textSecondary)
            Rectangle().fill(DesignSystem.Erewhon.line).frame(width: 1, height: 26)
        }
        .padding(.horizontal, 6)
    }

    /// Mockup `.cbar`: a share bar whose inner fill grows from the center (leading for the
    /// opponent, trailing for me).
    private func compareBar(fraction: Double, color: Color, fromLeading: Bool) -> some View {
        GeometryReader { geo in
            ZStack(alignment: fromLeading ? .leading : .trailing) {
                Capsule().fill(tc.segBackground)
                Capsule().fill(color).frame(width: max(0, geo.size.width * fraction))
            }
        }
        .frame(height: 6)
    }

    // MARK: - Featured-card derivations (DTO + VM convention only)

    /// First letter for an initials avatar, stripping a leading "@" from `@handle` labels.
    private func initial(for label: String) -> String {
        let trimmed = label.hasPrefix("@") ? String(label.dropFirst()) : label
        return trimmed.first.map { String($0).uppercased() } ?? "?"
    }

    /// The fighter sub-line = league label (D4).
    private func leagueSubline(_ league: Int) -> String { "\(league)-DAY RANKED" }

    /// Mirrors ArenaViewModel.barFraction's clamp/tie convention for the featured card's
    /// paired bars. Reproduced locally because no ArenaViewModel exists here and
    /// BattleViewModel is not modified (R4 Files list); scores come from the DTO.
    private func shareFraction(mine: Double, theirs: Double, forMine: Bool) -> Double {
        let mi = Int((mine * 10).rounded()), ti = Int((theirs * 10).rounded())
        if mi == ti { return 0.5 }                        // covers 0–0 and any exact tie
        let total = mine + theirs
        guard total > 0 else { return 0.5 }
        return min(0.92, max(0.08, (forMine ? mine : theirs) / total))
    }

    /// Mockup `.sec-head`: display title (D1) + optional meta over a soft hairline.
    private func secHead(_ title: String, _ meta: String?) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(AppFont.display(15))
                    .foregroundColor(tc.textPrimary)
                Spacer()
                if let meta {
                    Text(meta)
                        .font(AppFont.regular(11))
                        .foregroundColor(tc.textTertiary)
                }
            }
            .padding(.bottom, 10)
            Rectangle()
                .fill(DesignSystem.Erewhon.lineSoft)
                .frame(height: 1)
        }
        .padding(.bottom, 14)
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
            VStack(spacing: 0) {
                secHead(title, nil)
                VStack(spacing: 11) {
                    ForEach(duels) { duel in
                        row(duel)
                    }
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
        let myUid = authService.currentUserEmail ?? ""
        let mine = Int(duel.myScore(myUid).rounded())
        let theirs = Int(duel.theirScore(myUid).rounded())
        let iLead = viewModel.iAmLeading(duel)
        let theyLead = Int((duel.theirScore(myUid) * 10).rounded()) > Int((duel.myScore(myUid) * 10).rounded())
        return duelCard {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                header(name: viewModel.counterpartLabel(duel), league: duel.league)
                if let endAt = duel.endAt {
                    countdown(label: "Ends", date: endAt)
                }
                // Duel score as display figures (D1); my score is the left figure (matching the
                // featured card + Arena). The header already names the opponent.
                HStack(spacing: 6) {
                    Text("\(mine)").font(AppFont.display(20)).foregroundColor(iLead ? tc.primary : tc.textPrimary)
                    Text("—").font(AppFont.display(20)).foregroundColor(tc.textTertiary)
                    Text("\(theirs)").font(AppFont.display(20)).foregroundColor(theyLead ? tc.primary : tc.textPrimary)
                }
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
                        .font(AppFont.display(12))
                        .foregroundColor(tc.textPrimary)
                    if let delta = viewModel.rrDeltaText(duel) {
                        Text(delta)
                            .font(AppFont.display(12))
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

// MARK: - D4/D5: inline global standings block

/// The embedded standings block on Battle (D4): sec-head + the existing metric/league seg pickers,
/// the top 10 rows plus my row appended when I'm outside them, and a "View all" footer that opens
/// the full board. Renders the BattleView-owned `GlobalLeaderboardViewModel` (unchanged) — no new
/// logic. Rows follow the mockup standings anatomy (D5): rank chip (podium metals + crown),
/// tier-tinted avatar, name + you-pill, tier sub-line, display value; global rows show no pips.
private struct BattleStandingsBlock: View {

    let viewModel: GlobalLeaderboardViewModel
    let myUid: String
    let onViewAll: () -> Void

    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }

    /// One rendered standing: the projection, its rank-chip position (nil → "—"), and whether it's me.
    private struct Standing: Identifiable {
        let dto: GlobalLeaderboardDTO
        let position: Int?
        let isMe: Bool
        var id: String { dto.id ?? "" }
    }

    /// Top 10 + my row appended when I'm outside them. My appended row's chip uses `myRRPosition`
    /// on the RR board and "—" on the wins/streak boards (no position API there).
    private var standings: [Standing] {
        let top = Array(viewModel.rows.prefix(10))
        var list = top.enumerated().map {
            Standing(dto: $0.element, position: $0.offset + 1, isMe: viewModel.isMe($0.element))
        }
        if let mine = viewModel.myEntry, let myId = mine.id, !top.contains(where: { $0.id == myId }) {
            list.append(Standing(dto: mine,
                                 position: (viewModel.metric == .rr) ? viewModel.myRRPosition : nil,
                                 isMe: true))
        }
        return list
    }

    var body: some View {
        VStack(spacing: 0) {
            secHead
            pickers.padding(.bottom, 14)
            rowsContent
            viewAllRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: sec-head

    private var secHead: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Standings").font(AppFont.display(15)).foregroundColor(tc.textPrimary)
                Spacer()
                Text(metricCaption).font(AppFont.regular(11)).foregroundColor(tc.textTertiary)
            }
            .padding(.bottom, 10)
            Rectangle().fill(DesignSystem.Erewhon.lineSoft).frame(height: 1)
        }
        .padding(.bottom, 14)
    }

    private var metricCaption: String {
        switch viewModel.metric {
        case .rr: return "Ranked Rating"
        case .wins: return "\(viewModel.league)-day wins"
        case .streak: return "\(viewModel.league)-day streak"
        }
    }

    // MARK: pickers (existing seg style)

    private var metricBinding: Binding<LeaderboardMetric> {
        Binding(get: { viewModel.metric }, set: { newValue in
            viewModel.metric = newValue
            Task { await viewModel.boardChanged() }
        })
    }
    private var leagueBinding: Binding<Int> {
        Binding(get: { viewModel.league }, set: { newValue in
            viewModel.league = newValue
            Task { await viewModel.boardChanged() }
        })
    }

    private var pickers: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            Picker("Metric", selection: metricBinding) {
                ForEach(LeaderboardMetric.allCases) { m in Text(m.rawValue).tag(m) }
            }
            .pickerStyle(.segmented)
            if viewModel.showsLeaguePicker {
                Picker("League", selection: leagueBinding) {
                    ForEach(DuelConstants.leagues, id: \.self) { d in Text("\(d)-Day").tag(d) }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    // MARK: rows

    @ViewBuilder
    private var rowsContent: some View {
        if viewModel.isLoading && !viewModel.hasLoaded {
            ProgressView().tint(tc.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignSystem.Spacing.lg)
        } else {
            let rows = standings
            if rows.isEmpty {
                // Empty board (day one) is not an error — a quiet empty row (D4/D6).
                Text("No one on this board yet — finish a ranked duel.")
                    .font(AppFont.regular(13))
                    .foregroundColor(tc.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 13)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, s in
                        standingRow(s, isLast: index == rows.count - 1)
                    }
                }
            }
        }
    }

    private func standingRow(_ s: Standing, isLast: Bool) -> some View {
        let metal = s.position.flatMap { metalColor($0) }
        let row = HStack(alignment: .center, spacing: 13) {
            rankChip(s.position, metal: metal)
            avatar(initial: initial(for: s.dto), tint: erewhonRankMetal(forRR: s.dto.rr))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Text(s.dto.displayName.isEmpty ? "@\(s.dto.username)" : s.dto.displayName)
                        .font(AppFont.bold(14)).foregroundColor(tc.textPrimary).lineLimit(1)
                    if s.isMe { youPill }
                }
                Text(Rank.rankTier(from: s.dto.rr).displayName)
                    .font(AppFont.regular(11)).foregroundColor(tc.textTertiary).lineLimit(1)
            }
            Spacer(minLength: DesignSystem.Spacing.sm)
            valueColumn(s.dto)
        }
        .padding(.vertical, 13)

        return Group {
            if s.isMe {
                row
                    .padding(.horizontal, 8)
                    .background(RoundedRectangle(cornerRadius: 12).fill(tc.cardBackground.mix(with: tc.primary, by: 0.09)))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(tc.primary.opacity(0.4), lineWidth: 1.5))
            } else {
                VStack(spacing: 0) {
                    row.padding(.horizontal, 4)
                    if !isLast { Rectangle().fill(DesignSystem.Erewhon.lineSoft).frame(height: 1) }
                }
            }
        }
    }

    private func rankChip(_ position: Int?, metal: Color?) -> some View {
        VStack(spacing: 1) {
            if position == 1 {
                Image(systemName: "crown.fill").font(.system(size: 10))
                    .foregroundColor(metal ?? DesignSystem.Colors.goldMid)
            }
            Text(position.map { "\($0)" } ?? "—")
                .font(AppFont.display(15))
                .foregroundColor(metal != nil ? .white : tc.textSecondary)
                .monospacedDigit()
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 8).fill(metal ?? tc.segBackground))
        }
        .frame(width: 30)
    }

    private func avatar(initial: String, tint: Color?) -> some View {
        Text(initial)
            .font(AppFont.bold(15))
            .foregroundColor(tint != nil ? .white : tc.textPrimary)
            .frame(width: 38, height: 38)
            .background(RoundedRectangle(cornerRadius: 12).fill(tint ?? tc.segBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(tint != nil ? Color.white.opacity(0.22) : DesignSystem.Erewhon.line, lineWidth: 1)
                    .padding(3)
            )
    }

    private var youPill: some View {
        Text("You")
            .font(AppFont.bold(9))
            .tracking(0.4)
            .textCase(.uppercase)
            .foregroundColor(tc.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6).fill(tc.primary.opacity(0.13)))
    }

    /// Trailing value in `display` + its caption; no pips (RR/wins/streak are unbounded) (D5).
    private func valueColumn(_ dto: GlobalLeaderboardDTO) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(viewModel.valueText(dto))
                .font(AppFont.display(viewModel.metric == .rr ? 17 : 20))
                .foregroundColor(tc.textPrimary)
                .lineLimit(1)
            Text(viewModel.captionText(dto))
                .font(AppFont.regular(10))
                .foregroundColor(tc.textTertiary)
        }
    }

    private func initial(for dto: GlobalLeaderboardDTO) -> String {
        let name = dto.displayName.isEmpty ? dto.username : dto.displayName
        return name.first.map { String($0).uppercased() } ?? "?"
    }

    /// Podium metals (D5): Erewhon rank-metal tokens for 1/2/3, nil off-podium.
    private func metalColor(_ position: Int) -> Color? {
        switch position {
        case 1: return DesignSystem.Erewhon.rankGold
        case 2: return DesignSystem.Erewhon.rankSilver
        case 3: return DesignSystem.Erewhon.rankBronze
        default: return nil
        }
    }

    // MARK: View all

    private var viewAllRow: some View {
        Button(action: onViewAll) {
            HStack {
                Text("View all")
                    .font(AppFont.bold(13))
                    .foregroundColor(tc.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(AppFont.regular(12))
                    .foregroundColor(tc.textTertiary)
            }
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Rank-tier avatar metal from `rr`, using the Erewhon rank-metal tokens (never hardcoded hexes).
/// `nil` → neutral fill. Only four metal tokens exist pre-R5/R6, so the top tiers share `rankGold`;
/// a decorative tint, not a precise per-rank ladder colour.
fileprivate func erewhonRankMetal(forRR rr: Int?) -> Color? {
    guard let rr else { return nil }
    switch Rank.getRank(from: rr) {
    case .stone: return nil
    case .copper: return DesignSystem.Erewhon.rankBronze
    case .iron: return DesignSystem.Erewhon.rankIron
    case .gold, .rankVII, .rankVIII, .rankIX: return DesignSystem.Erewhon.rankGold
    case .platinum, .diamond: return DesignSystem.Erewhon.rankSilver
    }
}
