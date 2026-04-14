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

// MARK: - BadgeToastView

/// A banner that slides in from the top to celebrate a newly earned badge.
///
/// Shown via `.overlay(alignment: .top)` on ContentView's mainTabView.
/// Auto-dismisses after 3 seconds; tapping it dismisses it immediately.
struct BadgeToastView: View {

    let badge: BadgeDefinition
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Text(badge.emoji)
                .font(.system(size: 32))

            VStack(alignment: .leading, spacing: 2) {
                Text("Badge Unlocked!")
                    .font(.system(size: DesignSystem.FontSizes.caption, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                Text(badge.title)
                    .font(.system(size: DesignSystem.FontSizes.body, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
            }

            Spacer()

            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                .fill(DesignSystem.Colors.cardBackground)
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                        .stroke(DesignSystem.Colors.primary.opacity(0.4), lineWidth: 1)
                )
        )
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.top, DesignSystem.Spacing.sm)
        .onTapGesture { onDismiss() }
        .task {
            try? await Task.sleep(for: .seconds(3))
            onDismiss()
        }
    }
}
