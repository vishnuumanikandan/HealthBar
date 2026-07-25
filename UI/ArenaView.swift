//
//  ArenaView.swift
//  HealthBar
//
//  Created by Claude on 7/4/26.
//

import SwiftUI

/// The Arena — the signature duel view (D1c). Renders entirely from a `DuelDTO`: versus
/// header, tug-of-war bar, countdown, day-by-day timeline, projected RR, and actions.
/// No SwiftData, no Firestore types, no listeners.
struct ArenaView: View {

    @State private var viewModel: ArenaViewModel
    /// Retained to build the FriendProfileView sheet (NAV-1b).
    private let coordinator: AppCoordinator
    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }

    @State private var showForfeitConfirm = false
    @State private var endgamePulse = false
    /// NAV-1b: opponent's read-only profile sheet presentation flag.
    @State private var showOpponentProfile = false
    /// DUEL-CLARITY-1: "How duels work" primer presentation flag.
    @State private var showPrimer = false
    /// DUEL-FEED-1: score-feed disclosure state (collapsed by default).
    @State private var showScoreFeed = false

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    init(coordinator: AppCoordinator, myUid: String, duel: DuelDTO) {
        self._viewModel = State(initialValue: ArenaViewModel(coordinator: coordinator, myUid: myUid, duel: duel))
        self.coordinator = coordinator
    }

    var body: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.lg) {
                versusHeader
                scoreRow
                tugOfWarBar
                countdownOrOutcome
                if let projected = viewModel.projectedRRText {
                    Text(projected)
                        .font(AppFont.regular(12))
                        .foregroundColor(tc.textSecondary)
                }
                breakdownCard
                scoreFeedCard
                dayTimeline
                actions
                if viewModel.isStale {
                    Text("Couldn't refresh — showing the last known state.")
                        .font(AppFont.regular(11))
                        .foregroundColor(tc.textTertiary)
                }
            }
            .padding(DesignSystem.Spacing.lg)
        }
        .background(tc.primaryBackground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) {
            if let message = viewModel.toastMessage { toast(message) }
        }
        .task { await viewModel.refresh() }
        .refreshable { await viewModel.refresh() }
        .confirmationDialog("Forfeit this duel?", isPresented: $showForfeitConfirm, titleVisibility: .visible) {
            Button("Forfeit", role: .destructive) { Task { await viewModel.forfeit() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Forfeiting counts as a loss and costs RR.")
        }
        .onChange(of: viewModel.toastMessage) { _, message in
            guard message != nil else { return }
            Task { try? await Task.sleep(for: .seconds(3)); viewModel.toastMessage = nil }
        }
        // NAV-1b: opponent head → read-only profile. Active duels are never touched by a
        // block (onRemoved is a no-op); on return the head re-evaluates and goes inert if
        // the opponent was just blocked.
        .sheet(isPresented: $showOpponentProfile) {
            FriendProfileView(
                coordinator: coordinator,
                friendUid: viewModel.theirUid,
                username: viewModel.theirUsername,
                displayName: viewModel.theirDisplayName,
                onRemoved: {}
            )
        }
        // DUEL-CLARITY-1: the scoring primer. Static content — nothing to pass, nothing to load.
        .sheet(isPresented: $showPrimer) {
            DuelPrimerSheet()
        }
    }

    // MARK: - Header + scores

    /// D5: adopts the D4 fighter layout — two fighter columns around a `.vs-mid`,
    /// replacing the plain name/name row.
    private var versusHeader: some View {
        VStack(spacing: 6) {
            HStack(alignment: .center, spacing: 0) {
                // D3b/D4: MY head from the live local profile (VM); THEIR head is the opponent column.
                fighterColumn(initial: "Y", isMe: true, name: nil, subline: leagueSubline,
                              avatarIcon: viewModel.myAvatarIcon, avatarColor: viewModel.myAvatarColor)
                vsMid
                opponentColumn
            }
            primerAffordance
        }
    }

    /// DUEL-CLARITY-1: the primer entry point, sitting directly under the league sub-lines.
    /// The other entry point is the Battle ongoing-list foot button; both open the same sheet.
    private var primerAffordance: some View {
        Button {
            showPrimer = true
        } label: {
            Image(systemName: "info.circle")
                .font(AppFont.regular(13))
                .foregroundColor(tc.textTertiary)
                .frame(width: 44, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("How duels work")
    }

    /// The opponent fighter column. NAV-1b: tappable to their read-only profile unless
    /// they're blocked — in which case it renders exactly as today, just inert (no disabled
    /// styling, no hint; visually indistinguishable). My own column is never tappable.
    @ViewBuilder
    private var opponentColumn: some View {
        // D3b/D4: THEIR head from the duel's counterparty-side snapshot (VM ownership logic).
        let column = fighterColumn(initial: initial(for: viewModel.theirLabel), isMe: false,
                                   name: viewModel.theirLabel, subline: leagueSubline,
                                   avatarIcon: viewModel.theirAvatarIcon, avatarColor: viewModel.theirAvatarColor)
        if viewModel.canOpenOpponentProfile {
            Button {
                showOpponentProfile = true
            } label: {
                column
            }
            .buttonStyle(PlainButtonStyle())
        } else {
            column
        }
    }

    // MARK: - Fighter pieces (D4/D5)

    /// The fighter sub-line = league label (D4). The standalone league badge is absorbed
    /// into the fighter sub-lines here, restyled to the hairline language (D5).
    private var leagueSubline: String { "\(viewModel.league)-DAY RANKED" }

    /// Mockup `.fighter`: initials avatar, name (mine = the `.you-tag` pill), league sub-line.
    /// D3b: `avatarIcon`/`avatarColor` are the preset-avatar ids for this head (nil ⇒ initials).
    private func fighterColumn(initial: String, isMe: Bool, name: String?, subline: String,
                               avatarIcon: String? = nil, avatarColor: String? = nil) -> some View {
        VStack(spacing: 10) {
            favAvatar(initial: initial, avatarIcon: avatarIcon, avatarColor: avatarColor)
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
    /// D3b: the preset avatar over the existing 60pt/radius-19 initials fallback (byte-preserved).
    private func favAvatar(initial: String, avatarIcon: String? = nil, avatarColor: String? = nil) -> some View {
        AvatarView(iconId: avatarIcon, colorId: avatarColor, size: 60) {
            Text(initial)
                .font(AppFont.bold(23))
                .foregroundColor(tc.textPrimary)
                .frame(width: 60, height: 60)
                .background(RoundedRectangle(cornerRadius: 19).fill(tc.segBackground))
                .overlay(RoundedRectangle(cornerRadius: 19).stroke(DesignSystem.Erewhon.line, lineWidth: 1))
        }
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

    /// First letter for an initials avatar, stripping a leading "@" from `@handle` labels.
    private func initial(for label: String) -> String {
        let trimmed = label.hasPrefix("@") ? String(label.dropFirst()) : label
        return trimmed.first.map { String($0).uppercased() } ?? "?"
    }

    private var scoreRow: some View {
        // D5: score-row numerals → display at the existing 40pt scale (color logic unchanged).
        HStack {
            Text(viewModel.myScoreText)
                .font(AppFont.display(40))
                .foregroundColor(viewModel.iAmLeading ? tc.primary : tc.textPrimary)
            Spacer()
            Text("—").font(AppFont.display(40)).foregroundColor(tc.textTertiary)
            Spacer()
            Text(viewModel.theirScoreText).font(AppFont.display(40)).foregroundColor(tc.textPrimary)
        }
    }

    // MARK: - Tug-of-war bar

    private var tugOfWarBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // D5: track → segBackground + hairline (fraction / endgame / notch logic kept).
                Capsule()
                    .fill(tc.segBackground)
                    .overlay(Capsule().stroke(DesignSystem.Erewhon.line, lineWidth: 1))
                Capsule()
                    .fill(viewModel.isEndgame ? DesignSystem.Colors.danger : tc.primary)
                    .frame(width: max(0, geo.size.width * viewModel.barFraction))
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: viewModel.barFraction)
                Rectangle()
                    .fill(tc.textTertiary)
                    .frame(width: 1)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
        }
        .frame(height: 14)
    }

    // MARK: - Countdown / outcome

    @ViewBuilder
    private var countdownOrOutcome: some View {
        if viewModel.isFinished {
            VStack(spacing: DesignSystem.Spacing.xs) {
                Text(viewModel.outcomeHeadline.uppercased())
                    .font(AppFont.display(20))
                    .foregroundColor(tc.textPrimary)
                if let delta = viewModel.rrDeltaText {
                    Text(delta).font(AppFont.display(14)).foregroundColor(tc.textSecondary)
                }
                if let resolvedAt = viewModel.resolvedAt {
                    Text(resolvedAt.formatted(.dateTime.month().day().year()))
                        .font(AppFont.regular(11))
                        .foregroundColor(tc.textTertiary)
                }
            }
        } else if let endAt = viewModel.endAt {
            HStack(spacing: 4) {
                Text("Ends").font(AppFont.bold(16))
                Text(endAt, style: .relative).font(AppFont.bold(16))
            }
            .foregroundColor(viewModel.isEndgame ? DesignSystem.Colors.danger : tc.textSecondary)
            .opacity(viewModel.isEndgame && endgamePulse ? 0.6 : 1.0)
            .onAppear {
                guard viewModel.isEndgame else { return }
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { endgamePulse = true }
            }
        }
    }

    // MARK: - My-side breakdown (DUEL-CLARITY-1)

    /// "YOUR POINTS TODAY" — why my score is what it is. ACTIVE duels only. My side only: the
    /// opponent has no component data here, is never fetched for one, and renders as the bare
    /// total in the score row above (their food data is private).
    ///
    /// These are my GLOBAL day components, so the card is identical in every active Arena —
    /// correct, and what the primer states: one day's points count in every duel.
    @ViewBuilder
    private var breakdownCard: some View {
        if viewModel.showBreakdown {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    Text("YOUR POINTS TODAY")
                        .font(AppFont.display(11))
                        .tracking(1.1)
                        .foregroundColor(tc.primary)
                    Spacer()
                    Text(viewModel.pointsText(viewModel.breakdown.total))
                        .font(AppFont.display(20))
                        .foregroundColor(tc.textPrimary)
                }

                // Primer order — the same five rows, in the same order, as the primer sheet.
                VStack(spacing: DesignSystem.Spacing.sm) {
                    ForEach(DayScoreBreakdown.Component.allCases, id: \.self) { component in
                        breakdownRow(component)
                    }
                }

                Text(viewModel.breakdownHint)
                    .font(AppFont.regular(11))
                    .foregroundColor(tc.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let callout = viewModel.comebackCallout {
                    Text(callout)
                        .font(AppFont.regular(11))
                        .foregroundColor(tc.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(DesignSystem.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .adaptiveCard(borderColor: tc.primary.opacity(0.25), fillColor: tc.cardBackground)
        }
    }

    /// One component row: name, `value / max`, and a thin progress bar. The LABEL shows the raw
    /// value; only the BAR is clamped (`fill`), so an over-max component can never overflow.
    private func breakdownRow(_ component: DayScoreBreakdown.Component) -> some View {
        let value = viewModel.breakdown.value(component)
        let ceiling = DayScoreBreakdown.maxValue(component)
        return VStack(spacing: 5) {
            HStack {
                Text(breakdownLabel(component))
                    .font(AppFont.regular(12))
                    .foregroundColor(tc.textSecondary)
                Spacer()
                Text("\(viewModel.pointsText(value)) / \(viewModel.pointsText(ceiling))")
                    .font(AppFont.display(13))
                    .foregroundColor(tc.textPrimary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(tc.segBackground)
                        .overlay(Capsule().stroke(DesignSystem.Erewhon.line, lineWidth: 1))
                    Capsule()
                        .fill(tc.primary)
                        .frame(width: max(0, geo.size.width * viewModel.breakdown.fill(component)))
                }
            }
            .frame(height: 5)
        }
    }

    private func breakdownLabel(_ component: DayScoreBreakdown.Component) -> String {
        switch component {
        case .calories: return "Calories"
        case .protein:  return "Protein"
        case .purity:   return "Purity"
        case .quests:   return "Quests"
        case .qteBonus: return "QTE bonus"
        }
    }

    // MARK: - Score feed (DUEL-FEED-1)

    /// One merged feed row. The per-side arrays are what carry authorship — an event stores no
    /// uid — so `isMine` is stamped here, at the merge.
    private struct ScoreFeedRow: Identifiable {
        let event: DuelFeedEventDTO
        let component: DayScoreBreakdown.Component
        let isMine: Bool
        /// Event ids are deterministic, so the two sides CAN legitimately collide (same category,
        /// same transition, same day). Side-qualify the identity or ForEach drops a real row.
        var id: String { "\(isMine ? "me" : "them")_\(event.id)" }
    }

    /// Both sides' events merged newest-first. Events whose category this build doesn't know are
    /// SKIPPED at render (never deleted — they stay in the document).
    private var scoreFeedRows: [ScoreFeedRow] {
        let mine = viewModel.myFeedEvents.map { (event: $0, isMine: true) }
        let theirs = viewModel.theirFeedEvents.map { (event: $0, isMine: false) }
        return (mine + theirs)
            .compactMap { pair -> ScoreFeedRow? in
                guard let component = pair.event.componentEnum else { return nil }
                return ScoreFeedRow(event: pair.event, component: component, isMine: pair.isMine)
            }
            .sorted { $0.event.at > $1.event.at }
    }

    /// "SCORE FEED" — the shared, category-level record of how both scores moved. Shown on every
    /// duel page (a finished duel still renders whatever events it accumulated).
    ///
    /// PRIVACY: category-level ONLY. A row names one of the five scoring components and a signed
    /// point delta — never a food, a quantity, or a meal — and the rule is symmetric: my rows
    /// expose exactly as little as theirs.
    private var scoreFeedCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Button {
                withAnimation { showScoreFeed.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    Text("SCORE FEED")
                        .font(AppFont.display(11))
                        .tracking(1.1)
                        .foregroundColor(tc.primary)
                    Spacer()
                    Image(systemName: showScoreFeed ? "chevron.up" : "chevron.down")
                        .font(AppFont.regular(12))
                        .foregroundColor(tc.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showScoreFeed {
                if scoreFeedRows.isEmpty {
                    Text("No score events yet — points appear as both sides log.")
                        .font(AppFont.regular(12))
                        .foregroundColor(tc.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DesignSystem.Spacing.lg)
                } else {
                    // DUEL-FEED-1: deliberate nested-scroll exception (LB-PAGE-1 precedent; boxed feed). Revisit if it fights the outer scroll. DO NOT replace with outer scrolling.
                    ScrollView {
                        LazyVStack(spacing: DesignSystem.Spacing.sm) {
                            ForEach(scoreFeedRows) { row in scoreFeedRowView(row) }
                        }
                    }
                    .frame(height: 260)
                }
            }
        }
        .padding(DesignSystem.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .adaptiveCard(borderColor: tc.primary.opacity(0.25), fillColor: tc.cardBackground)
    }

    private func scoreFeedRowView(_ row: ScoreFeedRow) -> some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            // Own-vs-opponent distinction. Their rows keep the same 3pt gutter, unpainted, so
            // both sides stay aligned.
            Capsule()
                .fill(row.isMine ? tc.primary : Color.clear)
                .frame(width: 3)

            feedAvatar(row)

            VStack(alignment: .leading, spacing: 2) {
                // The copy comes from the frozen points-toast table — one source, no new wording.
                Text("\(feedPointsText(row.event.delta)) · \(DuelPointsToast.subline(row.component, rose: row.event.delta > 0))")
                    .font(AppFont.regular(12))
                    .foregroundColor(tc.textPrimary)
                Text(Self.relativeFormatter.localizedString(for: row.event.at, relativeTo: Date()))
                    .font(AppFont.regular(10))
                    .foregroundColor(tc.textTertiary)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The row's 26pt head: MY rows use the LIVE local profile, THEIR rows the duel snapshot —
    /// the same ownership convention as the fighter columns. Initials reuse `favAvatar`'s
    /// treatment, scaled down.
    private func feedAvatar(_ row: ScoreFeedRow) -> some View {
        let size: CGFloat = 26
        return AvatarView(iconId: row.isMine ? viewModel.myAvatarIcon : viewModel.theirAvatarIcon,
                          colorId: row.isMine ? viewModel.myAvatarColor : viewModel.theirAvatarColor,
                          size: size) {
            Text(row.isMine ? "Y" : initial(for: viewModel.theirLabel))
                .font(AppFont.bold(11))
                .foregroundColor(tc.textPrimary)
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: 8).fill(tc.segBackground))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(DesignSystem.Erewhon.line, lineWidth: 1))
        }
    }

    /// "+4" / "−4" — `DuelPointsToast.headline`'s sign convention (a real minus sign) without the
    /// "duel points" words. A delta that rounds to no whole point keeps its tenths rather than
    /// rendering "+0": it was significant enough to store, so it is significant enough to show.
    private func feedPointsText(_ delta: Double) -> String {
        let whole = Int(delta.rounded())
        let magnitude = whole != 0 ? "\(abs(whole))" : viewModel.pointsText(abs(delta))
        return delta < 0 ? "−\(magnitude)" : "+\(magnitude)"
    }

    // MARK: - Day timeline

    private var dayTimeline: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            ForEach(viewModel.dayRows) { row in dayRowView(row) }
        }
    }

    private func dayRowView(_ row: ArenaViewModel.DayRow) -> some View {
        HStack {
            Text("Day \(row.dayNumber)").font(AppFont.bold(13)).foregroundColor(tc.textSecondary)
            Spacer()
            HStack(spacing: DesignSystem.Spacing.sm) {
                dayScoreLabel(row.myScore, winner: row.myWins == true)
                Text("vs").font(AppFont.regular(11)).foregroundColor(tc.textTertiary)
                dayScoreLabel(row.theirScore, winner: row.myWins == false)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .frame(maxWidth: .infinity)
        .adaptiveCard(
            borderColor: row.state == .current ? tc.primary : tc.primary.opacity(0.15),
            fillColor: tc.cardBackground,
            isSelected: row.state == .current
        )
        .opacity(row.state == .upcoming ? 0.5 : 1.0)
    }

    private func dayScoreLabel(_ score: Double?, winner: Bool) -> some View {
        HStack(spacing: 3) {
            if winner {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 11)).foregroundColor(tc.primary)
            }
            Text(score.map { "\(Int($0.rounded()))" } ?? "—")
                .font(AppFont.display(14))
                .foregroundColor(tc.textPrimary)
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private var actions: some View {
        if viewModel.isActive {
            AppButton(title: "Forfeit", style: .secondary,
                      action: { showForfeitConfirm = true }, isDisabled: viewModel.inFlight)
        } else if viewModel.canRematch {
            AppButton(title: "Rematch", style: .secondary,
                      action: { Task { await viewModel.rematch() } }, isDisabled: viewModel.inFlight)
        }
    }

    private func toast(_ message: String) -> some View {
        Text(message)
            .font(AppFont.regular(14))
            .foregroundColor(.white)
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .background(Color.black.opacity(0.8))
            .clipShape(Capsule())
            .padding(.bottom, DesignSystem.Spacing.xl)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
