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

    /// R7b §4b: presents the full ranked ladder from the tappable rank block in arenaHead.
    @State private var showingRankLadder = false

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
            // R7c §4: no nav-bar title on the tab root — "THE ARENA" in `arenaHead` is the header,
            // and the root's toolbar held nothing else, so the empty bar is hidden rather than left
            // reserving space. Root only: the pushed Arena keeps its own bar and back button.
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $arenaDuelId) { id in
                if let duel = viewModel.duels.first(where: { $0.id == id }) {
                    ArenaView(coordinator: coordinator, myUid: authService.currentUserEmail ?? "", duel: duel)
                } else {
                    Color.clear.onAppear { arenaDuelId = nil } // duel gone from the list
                }
            }
        }
        // R7a §4: the rank-up moment, over the whole tab. Deferred (never dropped) while
        // anything is covering the Battle tab — see `canPresentRankUp`.
        .overlay {
            if let rankUp = viewModel.pendingRankUp, canPresentRankUp {
                RankUpOverlay(from: rankUp.from, to: rankUp.to) {
                    viewModel.dismissRankUp()
                }
                // The stored RR advances the moment it is SHOWN, not on dismiss: a kill
                // mid-overlay must not replay forever, a kill before it must replay.
                .onAppear { viewModel.markRankUpPresented() }
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
        // R7b §4b: the ranked ladder, opened by tapping the rank block in arenaHead.
        .sheet(isPresented: $showingRankLadder) {
            RankLadderSheet(currentRR: viewModel.myRR)
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

    /// R7a §4 presentation precedence: the celebration only appears when the Battle tab is
    /// frontmost with nothing covering it. Every sheet, dialog and pushed destination wins
    /// first — the duel-resolution recap sheet above all. It is DEFERRED, not dropped:
    /// `pendingRankUp` survives in the view model until it becomes presentable.
    private var canPresentRankUp: Bool {
        DuelUIState.shared.pendingResolutions.isEmpty
            && !showingChallenge
            && !showingMatchmaking
            && !showMacroQTE
            && !showingRankLadder   // R7b §4b: the celebration waits behind the ladder sheet too.
            && duelToForfeit == nil
            && arenaDuelId == nil
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

    // MARK: - Arena head (D3) + rank block (R7a §3)

    /// Mockup `.arena-head`: eyebrow cap + display title. No season/subtitle — those
    /// mockup stats don't exist in the app (D3). R7a hangs the rank block beneath it.
    private var arenaHead: some View {
        VStack(spacing: 10) {
            Text("RANKED DUELS")
                .font(AppFont.display(11))
                .tracking(1.1)
                .foregroundColor(tc.primary)
            Text("The Arena")
                .font(AppFont.display(38))
                .foregroundColor(tc.textPrimary)
            // R7b §4b: the whole rank block is one tap target → the ranked-ladder sheet.
            // `.contentShape` makes the full frame (well over 44pt) tappable; the explicit
            // label replaces the block's inner figures for VoiceOver.
            Button {
                showingRankLadder = true
            } label: {
                rankBlock
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityLabel("View the ranked ladder")
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    /// R7a §3: my rank — plaque, tier name, RR figure, and progress within the CURRENT tier.
    /// `myRR == nil` (the progress fetch failed) renders an em-dash skeleton with an empty
    /// bar and no captions: a rank is never invented from nil, and no plaque is shown.
    @ViewBuilder
    private var rankBlock: some View {
        if let rr = viewModel.myRR {
            let progress = BattleViewModel.rankProgress(rr: rr)
            VStack(spacing: 6) {
                HStack(spacing: 12) {
                    RankPlaque(rank: progress.tier.rank, size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(progress.tier.displayName.uppercased())
                            .font(AppFont.display(26))
                            .foregroundColor(tc.textPrimary)
                        Text(progress.caption)
                            .font(AppFont.regular(11))
                            .foregroundColor(tc.textSecondary)
                    }
                    Spacer(minLength: 8)
                    rrFigure("\(rr)")
                }
                rankTrack(fraction: progress.fraction)
                HStack(spacing: 0) {
                    Text("\(progress.floor)")
                    Spacer()
                    // No ceiling at the summit — there is nothing above it.
                    if !progress.isTopRank { Text("\(progress.ceiling)") }
                }
                .font(AppFont.regular(10))
                .foregroundColor(tc.textTertiary)
            }
        } else {
            VStack(spacing: 6) {
                HStack(spacing: 12) {
                    Text("—")
                        .font(AppFont.display(26))
                        .foregroundColor(tc.textSecondary)
                    Spacer(minLength: 8)
                    rrFigure("—")
                }
                rankTrack(fraction: 0)
            }
        }
    }

    /// The right-aligned RR figure with its unit.
    private func rrFigure(_ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value)
                .font(AppFont.display(20))
                .foregroundColor(tc.textPrimary)
            Text("RR")
                .font(AppFont.regular(11))
                .foregroundColor(tc.textSecondary)
        }
    }

    /// Sunk track + hairline, live-accent capsule fill. Animates on value change (the
    /// ArenaView tug-of-war precedent).
    private func rankTrack(fraction: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(tc.segBackground)
                    .overlay(Capsule().stroke(DesignSystem.Erewhon.line, lineWidth: 1))
                Capsule()
                    .fill(tc.primary)
                    .frame(width: max(0, geo.size.width * fraction))
            }
        }
        .frame(height: 8)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: fraction)
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

    /// D4: inline global standings block (seg pickers + top 10 + my row). Owns no logic —
    /// renders the BattleView-owned `GlobalLeaderboardViewModel`. R4c removed the "View all"
    /// footer; the full-screen board is retired now that the ladder lives inline.
    private var standingsBlock: some View {
        BattleStandingsBlock(viewModel: leaderboardVM, myUid: authService.currentUserEmail ?? "", coordinator: coordinator)
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
                              subline: tierLabel(p.myRR), tint: DesignSystem.Erewhon.rankMetal(forRR: p.myRR))
                vsMid
                fighterColumn(initial: p.theirInitial, isMe: false, name: p.opponentName,
                              subline: tierLabel(p.theirRR), tint: DesignSystem.Erewhon.rankMetal(forRR: p.theirRR))
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
            Text("No duels yet — challenge a friend")
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

// MARK: - R7a §4: rank-up moment

/// The rank-up celebration: the DESTINATION tier's plaque, two accent rings expanding out
/// of it, "RANK UP", and the `from → to` caption. Auto-dismisses; a tap anywhere dismisses.
///
/// Reduce Motion renders the settled frame outright — no spring, no expansion, no rise —
/// with the dismissal paths unchanged.
///
/// There is no demotion counterpart, by design. The ladder only celebrates upward.
private struct RankUpOverlay: View {

    let from: RankTier
    let to: RankTier
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }

    /// Motion constants (R7a §4).
    private static let plaqueSize: CGFloat = 54
    private static let plaqueFromScale: CGFloat = 0.8
    private static let ringDuration: Double = 0.6
    private static let titleRise: CGFloat = 8
    private static let autoDismissAfter: Double = 2.5
    /// Ring inset out from the plaque box, and its settled opacity.
    private static let rings: [(inset: CGFloat, opacity: Double)] = [(10, 0.35), (18, 0.15)]

    /// The scrim is dark in BOTH families, so the text on it is light in both — `tc.textPrimary`
    /// would be near-black in Erewhon Light and vanish. Values from the mock's rank-up frame.
    private static let onScrim = Color(hex: "#EDEFF3")
    private static let onScrimSecondary = Color(hex: "#B6BCC6")

    /// Drives every entrance property at once. Under Reduce Motion each animation below
    /// resolves to `nil`, so flipping this snaps straight to the settled frame.
    @State private var settled = false

    /// The plaque springs; the rings and the title ease. Both are switched off entirely
    /// under Reduce Motion — note an explicit `.animation(_:value:)` fires with or without
    /// `withAnimation`, so the gate has to live in the animation itself, not at the call.
    private var plaqueMotion: Animation? {
        reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.8)
    }
    private var entranceMotion: Animation? {
        reduceMotion ? nil : DesignSystem.Erewhon.ease(Self.ringDuration)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()

            VStack(spacing: 9) {
                ZStack {
                    // Two accent rings, expanding out of the plaque into their settled insets.
                    ForEach(Array(Self.rings.enumerated()), id: \.offset) { _, ring in
                        let diameter = Self.plaqueSize + ring.inset * 2
                        Circle()
                            .stroke(tc.primary, lineWidth: 1)
                            .frame(width: diameter, height: diameter)
                            .scaleEffect(settled ? 1 : Self.plaqueSize / diameter)
                            .opacity(settled ? ring.opacity : 0)
                    }
                    .animation(entranceMotion, value: settled)

                    RankPlaque(rank: to.rank, size: Self.plaqueSize)
                        .scaleEffect(settled ? 1 : Self.plaqueFromScale)
                        .animation(plaqueMotion, value: settled)
                }

                VStack(spacing: 5) {
                    Text("RANK UP")
                        .font(AppFont.display(28))
                        .foregroundColor(Self.onScrim)

                    HStack(spacing: 5) {
                        Text(from.displayName)
                        Text("→").foregroundColor(tc.primary)
                        Text(to.displayName)
                    }
                    .font(AppFont.regular(12))
                    .foregroundColor(Self.onScrimSecondary)
                }
                // Fades in with an 8pt rise, landing with the rings.
                .opacity(settled ? 1 : 0)
                .offset(y: settled ? 0 : Self.titleRise)
                .animation(entranceMotion, value: settled)
            }
        }
        // The scrim swallows every touch — nothing passes through to the tab beneath.
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }
        .task {
            settled = true
            try? await Task.sleep(for: .seconds(Self.autoDismissAfter))
            onDismiss()
        }
    }
}

// MARK: - D4/D5: inline global standings block

/// The embedded standings block on Battle (D4): sec-head + the existing metric/league seg pickers,
/// and the top 10 rows plus my row appended when I'm outside them. Renders the BattleView-owned
/// `GlobalLeaderboardViewModel` (unchanged) — no new logic. Rows follow the mockup standings
/// anatomy (D5): rank chip (podium metals + crown), tier-tinted avatar, name + you-pill, tier
/// sub-line, display value; global rows show no pips.
private struct BattleStandingsBlock: View {

    let viewModel: GlobalLeaderboardViewModel
    let myUid: String

    /// Retained to build the FriendProfileView sheet (NAV-1b).
    let coordinator: AppCoordinator

    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }

    /// Standing whose read-only profile sheet is open (NAV-1b).
    @State private var profileStanding: Standing? = nil

    /// One rendered standing: the projection and whether it's me. Position is computed from the
    /// row's index within the current page (LB-PAGE-1), no longer stored on the standing.
    private struct Standing: Identifiable {
        let dto: GlobalLeaderboardDTO
        let isMe: Bool
        var id: String { dto.id ?? "" }
    }

    /// Scroll anchor pinned at the top of the box — a page change scrolls back to it.
    private let topAnchorID = "lb-battle-top"

    /// The current page's rows as `Standing`s. LB-PAGE-1: no appended my-row — the pinned footer
    /// owns "me"; if I fall on the displayed page I still appear inline (self-highlighted, inert).
    private var standingRows: [Standing] {
        viewModel.rows.map { Standing(dto: $0, isMe: viewModel.isMe($0)) }
    }

    var body: some View {
        VStack(spacing: 0) {
            secHead
            pickers.padding(.bottom, 14)
            boardContent
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // NAV-1b: tap a non-self standing → read-only profile sheet.
        .sheet(item: $profileStanding) { standing in
            if let uid = standing.dto.id {
                FriendProfileView(
                    coordinator: coordinator,
                    friendUid: uid,
                    username: standing.dto.username,
                    displayName: standing.dto.displayName,
                    onRemoved: { Task { await viewModel.refresh() } }
                )
            }
        }
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

    // MARK: board content (box + pinned footer, or a state outside the box)

    /// The loading / empty states stay OUTSIDE the box (no box chrome around nothing); a populated
    /// board renders the scrolling box with the pinned footer below it.
    @ViewBuilder
    private var boardContent: some View {
        if viewModel.isLoading && !viewModel.hasLoaded {
            ProgressView().tint(tc.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignSystem.Spacing.lg)
        } else if standingRows.isEmpty {
            // Empty board (day one) is not an error — a quiet empty row, no box chrome (D4/D6).
            Text("No one on this board yet — finish a ranked duel.")
                .font(AppFont.regular(13))
                .foregroundColor(tc.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 13)
        } else {
            standingsBox
            pinnedFooter.padding(.top, 10)
        }
    }

    // MARK: the box (internally-scrolling, paged)

    private var standingsBox: some View {
        // LB-PAGE-1: deliberate nested-scroll exception (user ruling; Clash-style boxed board). Revisit if it fights the outer scroll. DO NOT replace with outer scrolling.
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Top anchor — a page change resets the scroll here (see onChange below).
                    Color.clear.frame(height: 0).id(topAnchorID)
                    ForEach(Array(standingRows.enumerated()), id: \.element.id) { index, s in
                        standingRow(s,
                                    position: viewModel.currentPageStartPosition + index,
                                    isLast: index == standingRows.count - 1)
                    }
                    pager   // the LAST element inside the scroll content (reached at the bottom)
                }
                .padding(.horizontal, 12)
                .padding(.top, 2)
            }
            .onChange(of: viewModel.pageIndex) { _, _ in
                proxy.scrollTo(topAnchorID, anchor: .top)
            }
        }
        .frame(height: DesignSystem.Metrics.leaderboardBoxHeight)
        .background(RoundedRectangle(cornerRadius: 16).fill(tc.cardBackground))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(DesignSystem.Erewhon.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: pager

    private var pager: some View {
        VStack(spacing: 0) {
            Rectangle().fill(DesignSystem.Erewhon.lineSoft).frame(height: 1)
            HStack(spacing: 26) {
                // `‹` fetches nothing (prev is always cache-served) so it never spins.
                pagerArrow("chevron.left", enabled: viewModel.canGoPrev, loading: false) {
                    Task { await viewModel.prevPage() }
                }
                Text("PAGE \(viewModel.pageIndex + 1)")
                    .font(AppFont.display(14)).tracking(1.2)
                    .foregroundColor(tc.textSecondary).monospacedDigit()
                // Only the tapped `›` spins while its fetch is in flight; the other arrow is untouched.
                pagerArrow("chevron.right", enabled: viewModel.canGoNext, loading: viewModel.isPageLoading) {
                    Task { await viewModel.nextPage() }
                }
            }
            .padding(.vertical, 14)
        }
    }

    private func pagerArrow(_ system: String, enabled: Bool, loading: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 11)
                    .fill(tc.segBackground)
                    .frame(width: 34, height: 34)
                    .overlay(RoundedRectangle(cornerRadius: 11).stroke(DesignSystem.Erewhon.line, lineWidth: 1))
                if loading {
                    ProgressView().controlSize(.small).tint(tc.textSecondary)
                } else {
                    Image(systemName: system).font(AppFont.bold(14)).foregroundColor(tc.textPrimary)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!enabled || loading)   // isPageLoading also gates re-entrant taps
        .opacity(enabled ? 1 : 0.32)
    }

    // MARK: rows

    /// NAV-1b: non-self rows carrying a real uid open the read-only profile sheet; my own inline row
    /// and any id-less row stay inert.
    @ViewBuilder
    private func standingRow(_ s: Standing, position: Int, isLast: Bool) -> some View {
        if !s.isMe, s.dto.id != nil {
            Button {
                profileStanding = s
            } label: {
                standingRowContent(s, position: position, isLast: isLast)
            }
            .buttonStyle(PlainButtonStyle())
        } else {
            standingRowContent(s, position: position, isLast: isLast)
        }
    }

    private func standingRowContent(_ s: Standing, position: Int, isLast: Bool) -> some View {
        // R7c §1: the shared standings pieces. Every displayed row now has a real position (the
        // no-position appended row is gone in LB-PAGE-1).
        let metal = StandingsPieces.podiumMetal(position: position, hasData: true)
        let row = HStack(alignment: .center, spacing: 13) {
            StandingsPieces.rankChip(position: position, hasData: true, metal: metal)
            StandingsPieces.avatar(initial: initial(for: s.dto), tint: DesignSystem.Erewhon.rankMetal(forRR: s.dto.rr))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Text(s.dto.displayName.isEmpty ? "@\(s.dto.username)" : s.dto.displayName)
                        .font(AppFont.bold(14)).foregroundColor(tc.textPrimary).lineLimit(1)
                    if s.isMe { youPill }
                }
                subline(s.dto)
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

    /// Row sub-line. RR board: the tier word is dropped (the plaque + "Tier · RR" caption carry it —
    /// the GLV/ChallengeSheet dedup precedent). `GlobalLeaderboardDTO` has no level field, so the
    /// mockup's "Lv N" slot is realized as the @handle line (shown only when a displayName exists —
    /// else the name row already IS the @handle). Wins/Streak keep the tier sub-line unchanged.
    @ViewBuilder
    private func subline(_ dto: GlobalLeaderboardDTO) -> some View {
        switch viewModel.metric {
        case .rr:
            if !dto.displayName.isEmpty && !dto.username.isEmpty {
                Text("@\(dto.username)")
                    .font(AppFont.regular(11)).foregroundColor(tc.textTertiary).lineLimit(1)
            }
        case .wins, .streak:
            Text(Rank.rankTier(from: dto.rr).displayName)
                .font(AppFont.regular(11)).foregroundColor(tc.textTertiary).lineLimit(1)
        }
    }

    /// Trailing value column. RR board (LB-PAGE-1 plaque swap, the ChallengeSheet precedent): the
    /// shipped `RankPlaque` + the RR number, with the tier folded into the caption. Wins/Streak
    /// stay numeric (unchanged).
    @ViewBuilder
    private func valueColumn(_ dto: GlobalLeaderboardDTO) -> some View {
        switch viewModel.metric {
        case .rr:
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 5) {
                    RankPlaque(rank: Rank.getRank(from: dto.rr), size: 18)
                    Text("\(dto.rr)")
                        .font(AppFont.display(18)).foregroundColor(tc.textPrimary).monospacedDigit()
                }
                Text("\(Rank.rankTier(from: dto.rr).displayName) · RR")
                    .font(AppFont.regular(10)).foregroundColor(tc.textTertiary)
            }
        case .wins, .streak:
            VStack(alignment: .trailing, spacing: 2) {
                Text(viewModel.valueText(dto))
                    .font(AppFont.display(20)).foregroundColor(tc.textPrimary).lineLimit(1)
                Text(viewModel.captionText(dto))
                    .font(AppFont.regular(10)).foregroundColor(tc.textTertiary)
            }
        }
    }

    // MARK: pinned "You" footer (below the box, always visible)

    /// You pill · name · `#N` position chip (aggregation-derived; hidden when nil) · metric-matched
    /// value column. Reuses `myEntry`; hidden entirely when I have never dueled (`myEntry == nil`).
    @ViewBuilder
    private var pinnedFooter: some View {
        if let entry = viewModel.myEntry {
            HStack(spacing: 13) {
                youPill
                Text(entry.displayName.isEmpty ? "@\(entry.username)" : entry.displayName)
                    .font(AppFont.bold(15)).foregroundColor(tc.textPrimary).lineLimit(1)
                if let pos = viewModel.myBoardPosition { positionChip(pos) }
                Spacer(minLength: DesignSystem.Spacing.sm)
                valueColumn(entry)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14).fill(tc.cardBackground.mix(with: tc.primary, by: 0.10)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(tc.primary.opacity(0.4), lineWidth: 1.5))
        }
    }

    /// Mockup `.pos`: the accent-tinted "#N" standing chip.
    private func positionChip(_ position: Int) -> some View {
        Text("#\(position)")
            .font(AppFont.display(13)).foregroundColor(tc.primary).monospacedDigit()
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 7).fill(tc.primary.opacity(0.13)))
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

    private func initial(for dto: GlobalLeaderboardDTO) -> String {
        let name = dto.displayName.isEmpty ? dto.username : dto.displayName
        return name.first.map { String($0).uppercased() } ?? "?"
    }

}
