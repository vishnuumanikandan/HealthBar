//
//  CleanLogQTESheet.swift
//  HealthBar
//
//  Created by Claude on 7/5/26.
//

import SwiftUI

/// Clean-log power moment (D1d): a tap-timing flourish when a low-toxin meal is logged mid-duel.
/// Marker position is a pure TRIANGLE WAVE of elapsed time; hit the center zone for a point.
struct CleanLogQTESheet: View {

    let coordinator: AppCoordinator
    let pending: PendingCleanLogQTE
    let dateKey: String
    var onFinished: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }

    @State private var startTime = Date()
    @State private var resultText: String?
    @State private var finished = false

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Text("Clean log!").font(AppFont.bold(22)).foregroundColor(tc.primary)
            Text(pending.mealName).font(AppFont.regular(14)).foregroundColor(tc.textSecondary)
            Text("Tap when the marker hits the center").font(AppFont.regular(12)).foregroundColor(tc.textTertiary)

            track

            if let resultText {
                Text(resultText).font(AppFont.bold(22)).foregroundColor(tc.primary)
            } else {
                AppButton(title: "TAP", style: .primary, action: { tap() })
            }
        }
        .padding(DesignSystem.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(tc.primaryBackground.ignoresSafeArea())
        .presentationDetents([.medium])
    }

    private var track: some View {
        TimelineView(.animation) { _ in
            let pos = position(Date().timeIntervalSince(startTime))
            GeometryReader { geo in
                let zoneWidth = geo.size.width * (DuelConstants.cleanLogHitZone.upperBound - DuelConstants.cleanLogHitZone.lowerBound)
                ZStack(alignment: .leading) {
                    Capsule().fill(tc.cardBackground).frame(height: 16)
                    Rectangle().fill(tc.primary.opacity(0.3))
                        .frame(width: zoneWidth, height: 16)
                        .offset(x: geo.size.width * DuelConstants.cleanLogHitZone.lowerBound)
                    Circle().fill(tc.primary).frame(width: 20, height: 20)
                        .offset(x: geo.size.width * pos - 10)
                }
            }
            .frame(height: 20)
        }
        .frame(height: 20)
        .padding(.vertical, DesignSystem.Spacing.md)
    }

    /// Triangle wave 0→1→0 across each `cleanLogSweepDuration` sweep.
    private func position(_ elapsed: Double) -> Double {
        let phase = (elapsed / DuelConstants.cleanLogSweepDuration).truncatingRemainder(dividingBy: 2)
        return 1 - abs(1 - phase)
    }

    private func tap() {
        guard !finished else { return }
        finished = true
        let pos = position(Date().timeIntervalSince(startTime))
        let hit = DuelConstants.cleanLogHitZone.contains(pos)
        Task {
            if hit {
                let total = await coordinator.awardCleanLogQTE(points: DuelConstants.cleanLogHitPoints, dateKey: dateKey)
                resultText = "NICE +\(DuelConstants.cleanLogHitPoints)  (\(total)/\(DuelConstants.cleanLogPointsCap))"
            } else {
                resultText = "MISSED"
            }
            try? await Task.sleep(for: .seconds(1.2))
            onFinished()
            dismiss()
        }
    }
}
