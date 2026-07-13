//
//  TopBar.swift
//  HealthBar
//
//  Created by Claude on 7/12/26.
//

import SwiftUI

/// R7b §1: the persistent top bar mounted as a `.safeAreaInset(edge: .top)` on the root
/// TabView — level + XP progress on the left, streak on the right — visible on every tab
/// and over pushed screens, both families.
///
/// A new chrome surface gets normal MVVM. The VM reads through the existing
/// `getTodaysSummary()` chokepoint (guest-safe internally: guests have local progress and
/// the bar renders for them identically), so this file adds no new data access.
@Observable
@MainActor
final class TopBarViewModel {

    /// Today's summary, or `nil` before the first successful load (placeholder chrome).
    private(set) var summary: TodaySummary?

    /// R7c §3: first letter of the display name, for the top-bar avatar. `nil` when the profile
    /// hasn't loaded, the fetch failed, or the name is empty — including guests, who have no
    /// display name. The bar then renders the glyph avatar; still no error UI in chrome.
    private(set) var initial: String?

    private let coordinator: AppCoordinator

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    /// Refresh via the existing chokepoint. Errors keep the last summary — chrome shows
    /// no error UI (a top bar must never flash an error over a working screen).
    func load() async {
        if let fresh = try? await coordinator.getTodaysSummary() {
            summary = fresh
        }
        let profile = try? await coordinator.getUserProfile()
        let name = profile?.displayName.trimmingCharacters(in: .whitespaces) ?? ""
        initial = name.first.map { String($0).uppercased() }
    }
}

/// The persistent top bar itself. One structure, both families (R4 ruling: new chrome with
/// no pixel bones renders token-driven, not per-family). Non-interactive in R7b — no tap
/// targets.
///
/// The view model is optional because ContentView cannot construct it at `init` (the
/// coordinator needs `@Environment(\.modelContext)`, unavailable there) and builds it lazily
/// on first appear. A nil VM is treated exactly like a nil summary: the fixed-height frame
/// still renders with "—" figures, so the chrome never collapses or jumps.
struct PersistentTopBar: View {

    let viewModel: TopBarViewModel?

    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }

    private var summary: TodaySummary? { viewModel?.summary }

    private var levelText: String { summary.map { "\($0.currentLevel)" } ?? "—" }
    private var streakText: String { summary.map { "\($0.currentStreak)" } ?? "—" }

    /// XP filled within the current level, clamped 0…1. Mirrors
    /// `HomeViewModel.levelProgressPercentage` exactly (`totalXP % 100 / 100`); the VM is
    /// untouched by R7b, so the math is duplicated here rather than shared.
    private var levelProgress: Double {
        guard let summary else { return 0 }
        return min(max(Double(summary.totalXP % 100) / 100.0, 0), 1)
    }

    var body: some View {
        HStack(spacing: 0) {
            leftCluster
            Spacer(minLength: 12)
            rightCluster
        }
        .frame(height: DesignSystem.Erewhon.topBarContentHeight)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .background(barBackground)
    }

    // MARK: Left — avatar + level eyebrow/number + slim XP capsule
    private var leftCluster: some View {
        HStack(spacing: 10) {
            avatar
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("LV.")
                    .font(AppFont.regular(10))
                    .foregroundColor(tc.textTertiary)
                Text(levelText)
                    .font(AppFont.display(17))
                    .foregroundColor(tc.textPrimary)
            }
            xpCapsule
        }
    }

    /// R7c §3: initials avatar. Circular on purpose — this is identity chrome, not a rank surface
    /// (the rounded square is the standings/rank shape). No display name — a guest, or a profile
    /// that hasn't loaded — falls back to a neutral glyph on the same circle, so the bar's
    /// geometry never shifts. Non-interactive, like the rest of the bar.
    private var avatar: some View {
        ZStack {
            Circle().fill(tc.primary.opacity(0.16))
            Circle().stroke(tc.primary.opacity(0.45), lineWidth: 1)

            if let initial = viewModel?.initial {
                Text(initial)
                    .font(AppFont.bold(13))
                    .foregroundColor(tc.primary)
            } else {
                Image(systemName: "person.fill")
                    .font(AppFont.regular(12))
                    .foregroundColor(tc.textTertiary)
            }
        }
        .frame(width: 28, height: 28)
    }

    /// Slim XP capsule: segBackground track + Erewhon hairline + accent fill at `levelProgress`.
    private var xpCapsule: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(tc.segBackground)
                .overlay(Capsule().stroke(DesignSystem.Erewhon.line, lineWidth: 1))
            Capsule()
                .fill(tc.primary)
                .frame(width: 110 * levelProgress)
        }
        .frame(width: 110, height: 6)
    }

    // MARK: Right — flame glyph + streak count
    private var rightCluster: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame")
                .font(AppFont.regular(15))
                .foregroundColor(tc.primary)
            Text(streakText)
                .font(AppFont.display(17))
                .foregroundColor(tc.textPrimary)
        }
    }

    /// The CleanTabBar treatment, mirrored to the top edge: blur + a background fade, with a
    /// hairline BOTTOM edge, extending up under the status bar. Token-driven, so the pixel
    /// family gets the same structure with its own colors.
    private var barBackground: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            LinearGradient(
                stops: [
                    .init(color: tc.primaryBackground, location: 0.0),          // solid at the top
                    .init(color: tc.primaryBackground.opacity(0.8), location: 0.7),
                    .init(color: tc.primaryBackground.opacity(0), location: 1.0) // transparent at the bottom
                ],
                startPoint: .top, endPoint: .bottom
            )
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DesignSystem.Erewhon.lineSoft)
                .frame(height: 1)
        }
        .ignoresSafeArea(edges: .top)
    }
}
