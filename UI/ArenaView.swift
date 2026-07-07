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

    private var versusHeader: some View {
        HStack {
            Text(viewModel.myLabel).font(AppFont.bold(18)).foregroundColor(tc.textPrimary)
            Spacer()
            leagueBadge
            Spacer()
            Text(viewModel.theirLabel).font(AppFont.bold(18)).foregroundColor(tc.textPrimary)
        }
    }

    private var leagueBadge: some View {
        Text(viewModel.leagueLabel())
            .font(AppFont.bold(10))
            .foregroundColor(tc.primary)
            .padding(.horizontal, DesignSystem.Spacing.sm)
            .padding(.vertical, 3)
            .background(tc.primary.opacity(0.15))
            .clipShape(Capsule())
    }

    private var scoreRow: some View {
        HStack {
            Text(viewModel.myScoreText)
                .font(AppFont.bold(40))
                .foregroundColor(viewModel.iAmLeading ? tc.primary : tc.textPrimary)
            Spacer()
            Text("—").font(AppFont.bold(40)).foregroundColor(tc.textTertiary)
            Spacer()
            Text(viewModel.theirScoreText).font(AppFont.bold(40)).foregroundColor(tc.textPrimary)
        }
    }

    // MARK: - Tug-of-war bar

    private var tugOfWarBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(tc.cardBackground)
                    .overlay(Capsule().stroke(tc.primary.opacity(0.25), lineWidth: 1))
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
                    .font(AppFont.bold(20))
                    .foregroundColor(tc.textPrimary)
                if let delta = viewModel.rrDeltaText {
                    Text(delta).font(AppFont.bold(14)).foregroundColor(tc.textSecondary)
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
            fillColor: tc.cardBackground
        )
        .opacity(row.state == .upcoming ? 0.5 : 1.0)
    }

    private func dayScoreLabel(_ score: Double?, winner: Bool) -> some View {
        HStack(spacing: 3) {
            if winner {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 11)).foregroundColor(tc.primary)
            }
            Text(score.map { "\(Int($0.rounded()))" } ?? "—")
                .font(AppFont.bold(14))
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
