//
//  GlobalLeaderboardView.swift
//  HealthBar
//
//  Created by Claude on 7/6/26.
//

import SwiftUI

/// RETIRED (R4c): the global ladder now lives inline on Battle as `BattleStandingsBlock`
/// (top 10 + my row). This standalone screen is no longer pushed or presented anywhere — it
/// survives only so any lingering reference or preview keeps compiling. All fetch/board logic
/// stays in `GlobalLeaderboardViewModel`.
///
/// The global leaderboard (D3): a single world-readable ladder with a metric toggle
/// (RR / Wins / Streak); Wins/Streak are per-league (1/3/5-Day sub-toggle), RR is global.
/// Fetch-on-view + pull-to-refresh; rows are NOT tappable (global strangers have no profile
/// surface). A pinned "You" footer shows my standing on the current board.
struct GlobalLeaderboardView: View {

    @State private var viewModel: GlobalLeaderboardViewModel
    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }

    init(coordinator: AppCoordinator, myUid: String) {
        self._viewModel = State(initialValue: GlobalLeaderboardViewModel(coordinator: coordinator, myUid: myUid))
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            tc.primaryBackground.ignoresSafeArea()

            VStack(spacing: DesignSystem.Spacing.md) {
                metricPicker
                if viewModel.showsLeaguePicker { leaguePicker }
                content
                youFooter
            }
            .padding(DesignSystem.Spacing.lg)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Leaderboard")
                    .font(AppFont.bold(20))
                    .foregroundColor(tc.textPrimary)
            }
        }
        .task { await viewModel.loadInitial() }
    }

    // MARK: - Pickers

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

    private var metricPicker: some View {
        Picker("Metric", selection: metricBinding) {
            ForEach(LeaderboardMetric.allCases) { metric in
                Text(metric.rawValue).tag(metric)
            }
        }
        .pickerStyle(.segmented)
    }

    private var leaguePicker: some View {
        Picker("League", selection: leagueBinding) {
            ForEach(DuelConstants.leagues, id: \.self) { days in
                Text("\(days)-Day").tag(days)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && !viewModel.hasLoaded {
            Spacer()
            ProgressView().tint(tc.primary)
            Spacer()
        } else {
            ScrollView {
                if let error = viewModel.loadError {
                    messageCard(error, tertiary: false)
                } else if viewModel.rows.isEmpty {
                    messageCard("No one on this board yet — finish a ranked duel.", tertiary: true)
                } else {
                    LazyVStack(spacing: DesignSystem.Spacing.md) {
                        ForEach(Array(viewModel.rows.enumerated()), id: \.element.id) { index, row in
                            leaderRow(row, position: index + 1)
                        }
                    }
                }
            }
            .refreshable { await viewModel.refresh() }
        }
    }

    private func messageCard(_ text: String, tertiary: Bool) -> some View {
        Text(text)
            .font(AppFont.regular(15))
            .foregroundColor(tertiary ? tc.textTertiary : tc.textSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DesignSystem.Spacing.xl)
    }

    // MARK: - Row

    private func leaderRow(_ row: GlobalLeaderboardDTO, position: Int) -> some View {
        let metal = metalColor(position)
        let mine = viewModel.isMe(row)
        return HStack(spacing: DesignSystem.Spacing.md) {
            rankNumeral(position, metal: metal)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Text(row.displayName.isEmpty ? "@\(row.username)" : row.displayName)
                        .font(AppFont.bold(16))
                        .foregroundColor(tc.textPrimary)
                        .lineLimit(1)
                    if mine { youCapsule }
                }
                if !row.displayName.isEmpty && !row.username.isEmpty {
                    Text("@\(row.username)")
                        .font(AppFont.regular(11))
                        .foregroundColor(tc.textSecondary)
                }
            }

            Spacer()

            valueColumn(value: viewModel.valueText(row), caption: viewModel.captionText(row), trailingBadge: nil)
        }
        .padding(DesignSystem.Spacing.md)
        .adaptiveCard(
            borderColor: metal?.opacity(0.85) ?? (mine ? tc.primary : tc.primary.opacity(0.3)),
            fillColor: metal.map { tc.cardBackground.mix(with: $0, by: 0.16) }
                ?? (mine ? tc.cardBackground.mix(with: tc.primary, by: 0.10) : tc.cardBackground),
            // R6c: preserve retired heuristic — accent border only on own row without a rank-metal
            isSelected: metal == nil && mine
        )
        .overlay {
            if let metal, settings.isCleanUI {
                RoundedRectangle(cornerRadius: 16).stroke(metal.opacity(0.55), lineWidth: 1.5)
            }
        }
    }

    /// Big position numeral; metal on the podium, crown over #1.
    private func rankNumeral(_ position: Int, metal: Color?) -> some View {
        VStack(spacing: 1) {
            if position == 1 {
                Image(systemName: "crown.fill")
                    .font(.system(size: 11))
                    .foregroundColor(metal ?? DesignSystem.Colors.goldMid)
            }
            Text("\(position)")
                .font(AppFont.bold(position <= 3 ? 26 : 17))
                .foregroundColor(metal ?? tc.textSecondary)
                .monospacedDigit()
        }
        .frame(width: 40)
    }

    private var youCapsule: some View {
        Text("You")
            .font(AppFont.bold(10))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(tc.primary))
    }

    /// Trailing value column. RR tier strings are words (smaller font); Wins/Streak are digits.
    private func valueColumn(value: String, caption: String, trailingBadge: String?) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value)
                .font(AppFont.bold(viewModel.metric == .rr ? 17 : 22))
                .foregroundColor(tc.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
            HStack(spacing: 4) {
                Text(caption)
                    .font(AppFont.regular(10))
                    .foregroundColor(tc.textSecondary)
                if let trailingBadge {
                    Text(trailingBadge)
                        .font(AppFont.bold(10))
                        .foregroundColor(tc.primary)
                        .monospacedDigit()
                }
            }
        }
    }

    // MARK: - Pinned "You" footer

    @ViewBuilder
    private var youFooter: some View {
        if let entry = viewModel.myEntry {
            // On the RR board, append my standing (#N) when the count aggregation succeeded.
            let position: String? = (viewModel.metric == .rr) ? viewModel.myBoardPosition.map { "#\($0)" } : nil
            HStack(spacing: DesignSystem.Spacing.md) {
                youCapsule
                Text(entry.displayName.isEmpty ? "@\(entry.username)" : entry.displayName)
                    .font(AppFont.bold(15))
                    .foregroundColor(tc.textPrimary)
                    .lineLimit(1)
                Spacer()
                valueColumn(value: viewModel.valueText(entry), caption: viewModel.captionText(entry), trailingBadge: position)
            }
            .padding(DesignSystem.Spacing.md)
            .adaptiveCard(
                borderColor: tc.primary,
                fillColor: tc.cardBackground.mix(with: tc.primary, by: 0.10),
                isSelected: true  // R6c: preserved implicit-selection (review intent later)
            )
        }
    }

    // MARK: - Podium metals (mirrors the guild leaderboard)

    private func metalColor(_ position: Int) -> Color? {
        switch position {
        case 1: return DesignSystem.Colors.goldMid
        case 2: return Color(hex: "#9CA3AF") // silver
        case 3: return Color(hex: "#CD7F32") // bronze
        default: return nil
        }
    }
}
