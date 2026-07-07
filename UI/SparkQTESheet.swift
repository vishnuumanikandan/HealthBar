//
//  SparkQTESheet.swift
//  HealthBar
//
//  Created by Claude on 7/5/26.
//

import SwiftUI

/// Daily Spark QTE (D1d): hold to charge, release in the zone. Charge is a pure TRIANGLE WAVE
/// of hold time — no charge/drain state machine. One attempt/day (set even on a miss).
struct SparkQTESheet: View {

    let coordinator: AppCoordinator
    /// Captured when the sheet opened — a midnight rollover mid-game still credits that day.
    let dateKey: String
    var onFinished: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }

    @State private var pressStart: Date?
    @State private var resultText: String?
    @State private var finished = false

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Text("Daily Spark").font(AppFont.bold(22)).foregroundColor(tc.textPrimary)
            Text("Hold to charge — release in the bright zone")
                .font(AppFont.regular(13)).foregroundColor(tc.textSecondary)
                .multilineTextAlignment(.center)

            ring

            if let resultText {
                Text(resultText).font(AppFont.bold(26)).foregroundColor(tc.primary)
            } else {
                holdButton
            }
        }
        .padding(DesignSystem.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(tc.primaryBackground.ignoresSafeArea())
        .presentationDetents([.medium])
        .interactiveDismissDisabled(pressStart != nil)
    }

    private var ring: some View {
        TimelineView(.animation) { _ in
            let charge = pressStart.map { chargeValue(Date().timeIntervalSince($0)) } ?? 0
            ZStack {
                Circle().stroke(tc.cardBackground, lineWidth: 18)
                Circle()
                    .trim(from: DuelConstants.sparkGoodZone.lowerBound / 100, to: DuelConstants.sparkGoodZone.upperBound / 100)
                    .stroke(tc.primary.opacity(0.4), lineWidth: 18).rotationEffect(.degrees(-90))
                Circle()
                    .trim(from: DuelConstants.sparkPerfectZone.lowerBound / 100, to: DuelConstants.sparkPerfectZone.upperBound / 100)
                    .stroke(tc.primary, lineWidth: 18).rotationEffect(.degrees(-90))
                Circle()
                    .trim(from: 0, to: charge / 100)
                    .stroke(tc.textPrimary, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(charge))").font(AppFont.bold(30)).foregroundColor(tc.textPrimary)
            }
            .frame(width: 200, height: 200)
            .padding(DesignSystem.Spacing.md)
        }
        .frame(height: 224)
    }

    private var holdButton: some View {
        Text(pressStart == nil ? "HOLD" : "RELEASE")
            .font(AppFont.bold(17)).foregroundColor(.white)
            .frame(maxWidth: .infinity).frame(height: 52)
            .background(tc.primary).clipShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if pressStart == nil && !finished { pressStart = Date() } }
                    .onEnded { _ in release() }
            )
    }

    /// Triangle wave 0→100→0 across each `sparkSweepDuration` sweep.
    private func chargeValue(_ elapsed: Double) -> Double {
        let phase = (elapsed / DuelConstants.sparkSweepDuration).truncatingRemainder(dividingBy: 2)
        return (1 - abs(1 - phase)) * 100
    }

    private func release() {
        guard let start = pressStart, !finished else { return }
        finished = true
        let charge = chargeValue(Date().timeIntervalSince(start))
        pressStart = nil

        let points: Int
        let label: String
        if DuelConstants.sparkPerfectZone.contains(charge) {
            points = DuelConstants.sparkPerfectPoints; label = "PERFECT"
        } else if DuelConstants.sparkGoodZone.contains(charge) {
            points = DuelConstants.sparkGoodPoints; label = "GOOD"
        } else {
            points = 0; label = "MISSED"
        }

        Task {
            let total = await coordinator.awardSparkQTE(points: points, dateKey: dateKey)
            resultText = points > 0 ? "\(label) +\(total)" : "MISSED"
            try? await Task.sleep(for: .seconds(1.2))
            onFinished()
            dismiss()
        }
    }
}
