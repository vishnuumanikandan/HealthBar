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
    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }

    @State private var showForfeitConfirm = false
    @State private var endgamePulse = false

    init(coordinator: AppCoordinator, myUid: String, duel: DuelDTO) {
        self._viewModel = State(initialValue: ArenaViewModel(coordinator: coordinator, myUid: myUid, duel: duel))
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
    }

    // MARK: - Header + scores

    /// D5: adopts the D4 fighter layout — two fighter columns around a `.vs-mid`,
    /// replacing the plain name/name row.
    private var versusHeader: some View {
        HStack(alignment: .center, spacing: 0) {
            fighterColumn(initial: "Y", isMe: true, name: nil, subline: leagueSubline)
            vsMid
            fighterColumn(initial: initial(for: viewModel.theirLabel), isMe: false,
                          name: viewModel.theirLabel, subline: leagueSubline)
        }
    }

    // MARK: - Fighter pieces (D4/D5)

    /// The fighter sub-line = league label (D4). The standalone league badge is absorbed
    /// into the fighter sub-lines here, restyled to the hairline language (D5).
    private var leagueSubline: String { "\(viewModel.league)-DAY RANKED" }

    /// Mockup `.fighter`: initials avatar, name (mine = the `.you-tag` pill), league sub-line.
    private func fighterColumn(initial: String, isMe: Bool, name: String?, subline: String) -> some View {
        VStack(spacing: 10) {
            favAvatar(initial: initial)
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
    private func favAvatar(initial: String) -> some View {
        Text(initial)
            .font(AppFont.bold(23))
            .foregroundColor(tc.textPrimary)
            .frame(width: 60, height: 60)
            .background(RoundedRectangle(cornerRadius: 19).fill(tc.segBackground))
            .overlay(RoundedRectangle(cornerRadius: 19).stroke(DesignSystem.Erewhon.line, lineWidth: 1))
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
