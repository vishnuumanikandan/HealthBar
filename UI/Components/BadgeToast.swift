//
//  BadgeToast.swift
//  HealthBar
//
//  Created by Claude on 4/8/26.
//

import SwiftUI

// MARK: - BadgeToastQueue

/// Global singleton queue that drives badge unlock toasts across all tabs.
///
/// Each tab has its own AppCoordinator, so per-coordinator state is invisible
/// cross-tab. This singleton ensures a toast triggered on the Food tab is still
/// visible when the user is on the Profile tab.
///
/// Usage:
///   BadgeToastQueue.shared.enqueue(newlyUnlockedBadges)
@Observable
@MainActor
final class BadgeToastQueue {

    static let shared = BadgeToastQueue()

    /// Badges waiting to be shown (FIFO).
    var queue: [BadgeDefinition] = []

    /// The badge currently being displayed. Nil when no toast is active.
    var currentToast: BadgeDefinition?

    private init() {}

    /// Adds badges to the queue and starts showing if nothing is active.
    func enqueue(_ badges: [BadgeDefinition]) {
        queue.append(contentsOf: badges)
        showNext()
    }

    /// Advances to the next toast after a brief dismiss pause.
    func dismiss() {
        currentToast = nil
        Task {
            try? await Task.sleep(for: .seconds(0.3))
            showNext()
        }
    }

    // MARK: - Private

    private func showNext() {
        guard currentToast == nil, !queue.isEmpty else { return }
        currentToast = queue.removeFirst()
    }
}

// MARK: - DuelPointsToast (DUEL-CLARITY-1)

/// One "+N duel points" toast: a signed headline and the reason for the biggest mover.
///
/// The copy is a FIXED table — one entry per category AND direction, never free-form. Built
/// only from `DayScoreBreakdown.delta`'s result, which is my OWN side; the opponent's
/// components do not exist here and are never inferred.
struct DuelPointsToast: Identifiable {
    let id = UUID()
    let points: Int
    let reason: DayScoreBreakdown.Component

    /// "+4 duel points" / "−4 duel points" (a real minus sign, matching the primer's stakes).
    var headline: String {
        points < 0 ? "−\(abs(points)) duel points" : "+\(points) duel points"
    }

    /// The fixed copy table: category × direction.
    var subline: String { Self.subline(reason, rose: points > 0) }

    /// The table itself — hoisted to a static (DUEL-FEED-1) so the Arena score-feed rows render
    /// from the SAME frozen copy. ONE source: no second table, no invented wording. The strings
    /// are unchanged from the instance property this was lifted out of.
    static func subline(_ reason: DayScoreBreakdown.Component, rose: Bool) -> String {
        switch reason {
        case .calories: return rose ? "Calories · on target"  : "Calories · over goal"
        case .protein:  return rose ? "Protein target hit"    : "Protein · under target"
        case .purity:   return rose ? "Purity improved"       : "Purity dropped"
        case .quests:   return rose ? "Quests completed"      : "Quest progress lost"
        case .qteBonus: return rose ? "QTE bonus earned"      : "QTE bonus reduced"
        }
    }

    /// nil when the net change rounds to no whole point — sub-point drift is not worth a toast.
    static func make(net: Double, reason: DayScoreBreakdown.Component) -> DuelPointsToast? {
        let points = Int(net.rounded())
        guard points != 0 else { return nil }
        return DuelPointsToast(points: points, reason: reason)
    }
}

// MARK: - DuelPointsToastQueue

/// Global singleton queue for duel-points toasts — a SIBLING of `BadgeToastQueue`, pattern-copied
/// (same singleton shape, same FIFO semantics, same 0.3s dismiss pause, same host overlay site).
/// `BadgeToastQueue` itself is untouched: not subclassed, not extended, not modified.
///
/// Separate queue because the two are separate moments: a badge unlock is a milestone, a points
/// toast is live feedback on today's score. ContentView gives badges precedence — a points toast
/// simply waits in `currentToast` until the badge banner clears, so it is deferred, never dropped.
@Observable
@MainActor
final class DuelPointsToastQueue {

    static let shared = DuelPointsToastQueue()

    /// Toasts waiting to be shown (FIFO).
    var queue: [DuelPointsToast] = []

    /// The toast currently being displayed. Nil when no toast is active.
    var currentToast: DuelPointsToast?

    private init() {}

    /// Adds a toast to the queue and starts showing if nothing is active.
    func enqueue(_ toast: DuelPointsToast) {
        queue.append(toast)
        showNext()
    }

    /// Advances to the next toast after a brief dismiss pause.
    func dismiss() {
        currentToast = nil
        Task {
            try? await Task.sleep(for: .seconds(0.3))
            showNext()
        }
    }

    // MARK: - Private

    private func showNext() {
        guard currentToast == nil, !queue.isEmpty else { return }
        currentToast = queue.removeFirst()
    }
}

// MARK: - BadgeToastView

/// A banner that slides in from the top to celebrate a newly earned badge.
///
/// Shown via `.overlay(alignment: .top)` on ContentView's mainTabView.
/// Auto-dismisses after 3 seconds; tapping it dismisses it immediately.
struct BadgeToastView: View {

    let badge: BadgeDefinition
    let onDismiss: () -> Void

    private var tc: ThemeColors { SettingsManager.shared.activeColors }

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            BadgeEmblem(badge, size: 32, isLocked: false)

            VStack(alignment: .leading, spacing: 2) {
                Text("Badge Unlocked!")
                    .font(AppFont.bold(12))
                    .foregroundColor(tc.textSecondary)
                Text(badge.title)
                    .font(AppFont.bold(17))
                    .foregroundColor(tc.textPrimary)
            }

            Spacer()

            Image(systemName: "xmark")
                .font(AppFont.bold(12))
                .foregroundColor(tc.textSecondary)
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .adaptiveCard(borderColor: tc.primary.opacity(0.4), fillColor: tc.cardBackground)
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.top, DesignSystem.Spacing.sm)
        .onTapGesture { onDismiss() }
        .task {
            try? await Task.sleep(for: .seconds(3))
            onDismiss()
        }
    }
}

// MARK: - DuelPointsToastView (DUEL-CLARITY-1)

/// The duel-points banner — `BadgeToastView`'s layout, timing and dismissal, with the points
/// figure in place of the emblem. Same host: `.overlay(alignment: .top)` on ContentView.
struct DuelPointsToastView: View {

    let toast: DuelPointsToast
    let onDismiss: () -> Void

    private var tc: ThemeColors { SettingsManager.shared.activeColors }

    /// A drop is the one place the retired `danger` token still applies (no themed replacement).
    private var accent: Color { toast.points < 0 ? DesignSystem.Colors.danger : tc.primary }

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: toast.points < 0 ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                .font(AppFont.regular(26))
                .foregroundColor(accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(toast.headline)
                    .font(AppFont.display(17))
                    .foregroundColor(accent)
                Text(toast.subline)
                    .font(AppFont.regular(12))
                    .foregroundColor(tc.textSecondary)
            }

            Spacer()

            Image(systemName: "xmark")
                .font(AppFont.bold(12))
                .foregroundColor(tc.textSecondary)
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .adaptiveCard(borderColor: accent.opacity(0.4), fillColor: tc.cardBackground)
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.top, DesignSystem.Spacing.sm)
        .onTapGesture { onDismiss() }
        .task {
            try? await Task.sleep(for: .seconds(3))
            onDismiss()
        }
    }
}
