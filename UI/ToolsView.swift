//
//  ToolsView.swift
//  HealthBar
//
//  Created by Claude on 3/30/26.
//

import SwiftUI
import Observation

// MARK: - ToolsViewModel

/// Lightweight state shared across calculator views.
/// Primarily used so MacroCalculatorView can auto-fill TDEE from TDEEView.
@Observable
final class ToolsViewModel {
    /// Set by TDEEView when a result is calculated; read by MacroCalculatorView.
    var lastTDEE: Double? = nil
}

// MARK: - ToolsView

/// PARTIALLY RETIRED (R7b §2): the Tools row was removed from ProfileView's settings. R7b's
/// plan treated Profile as ToolsView's last entry point — but it is NOT. FoodLogView's
/// date-navigator still presents this view (its "wrench" button → `showingTools`), an R5a/D2
/// entry point the plan overlooked. So ToolsView remains REACHABLE from the Food tab and is
/// kept as-is (GlobalLeaderboardView-style retirement note); the calculators
/// (`CalculatorViews.swift`) are likewise still reachable through it. Fully retiring this view
/// is blocked on that FoodLogView entry point, which is out of R7b's scope — do not delete.
///
/// `ToolsViewModel` above is unaffected: it is still constructed by both FoodLogView and this view.
struct ToolsView: View {

    let toolsViewModel: ToolsViewModel

    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }

    // Grid columns
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.md) {
                    waterTrackerRow

                    LazyVGrid(columns: columns, spacing: DesignSystem.Spacing.md) {
                        ForEach(CalculatorCard.allCards) { card in
                            NavigationLink(destination: destinationView(for: card)) {
                                CalculatorCardView(card: card, tc: tc)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                .padding(DesignSystem.Spacing.md)
            }
            .background(tc.primaryBackground.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Tools")
                        .font(AppFont.bold(20))
                        .foregroundColor(tc.textPrimary)
                }
            }
        }
    }

    // MARK: - Water Tracker Toggle (WATER-1 D4)

    /// A single visible row above the calculator grid — §7 reading A ("a small extra toggle
    /// tucked in Tools"), NOT the SECRET-1 hidden pattern. Turning it off hides every water
    /// surface and keeps all data (the `trackAdvancedNutrition` precedent).
    private var waterTrackerRow: some View {
        Toggle(isOn: $settings.waterTrackerEnabled) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("Water Tracker")
                    .font(AppFont.bold(16))
                    .foregroundColor(tc.textPrimary)

                Text("Adds a water column to the Food Log")
                    .font(AppFont.regular(12))
                    .foregroundColor(tc.textSecondary)
            }
        }
        .tint(tc.primary)
        .padding(DesignSystem.Spacing.md)
        .adaptiveCard(borderColor: tc.primary.opacity(0.25), fillColor: tc.cardBackground)
        .accessibilityLabel("Water tracker")
        .accessibilityHint("When enabled, adds a water column to the Food Log")
    }

    @ViewBuilder
    private func destinationView(for card: CalculatorCard) -> some View {
        switch card.id {
        case "tdee":       TDEEView(toolsViewModel: toolsViewModel)
        case "protein":    ProteinView()
        case "1rm":        OneRepMaxView()
        case "muscle":     MuscleGainView()
        case "creatine":   CreatineView()
        case "strength":   StrengthStandardsView()
        case "sleep":      SleepToolkitView()
        case "macro":      MacroView(toolsViewModel: toolsViewModel)
        default:           EmptyView()
        }
    }
}

// MARK: - Calculator Card Model

struct CalculatorCard: Identifiable {
    let id: String
    let icon: String
    let title: String
    let description: String
    let iconColor: Color

    static let allCards: [CalculatorCard] = [
        CalculatorCard(id: "tdee",     icon: "flame.fill",               title: "TDEE",             description: "Daily calorie needs & goals",    iconColor: .orange),
        CalculatorCard(id: "protein",  icon: "figure.strengthtraining.traditional", title: "Protein",   description: "Daily protein target",           iconColor: .blue),
        CalculatorCard(id: "1rm",      icon: "dumbbell.fill",             title: "One Rep Max",      description: "Estimate your 1RM",              iconColor: .red),
        CalculatorCard(id: "muscle",   icon: "figure.arms.open",          title: "Muscle Potential", description: "Max natural muscle mass",        iconColor: .purple),
        CalculatorCard(id: "creatine", icon: "pill.fill",                 title: "Creatine",         description: "Loading & maintenance dose",     iconColor: .teal),
        CalculatorCard(id: "strength", icon: "chart.bar.fill",            title: "Strength Levels",  description: "Bench, squat, deadlift, OHP",    iconColor: .indigo),
        CalculatorCard(id: "sleep",    icon: "moon.zzz.fill",             title: "Sleep Toolkit",    description: "Bedtime & sleep tips",           iconColor: .purple),
        CalculatorCard(id: "macro",    icon: "chart.pie.fill",            title: "Macros",           description: "Protein, carbs & fat targets",   iconColor: .green),
    ]
}

// MARK: - Calculator Card View

private struct CalculatorCardView: View {

    let card: CalculatorCard
    let tc: ThemeColors

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack {
                Image(systemName: card.icon)
                    .font(AppFont.regular(18))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .adaptivePill(
                        borderColor: SettingsManager.shared.isCleanUI ? .clear : card.iconColor.adjustedBrightness(-0.2),
                        fillColor: .clear,
                        fillGradient: DesignSystem.Colors.adaptiveGradientFrom(card.iconColor)
                    )
                Spacer()
                Image(systemName: "chevron.right")
                    .font(AppFont.bold(12))
                    .foregroundColor(tc.textTertiary)
            }

            Text(card.title)
                .font(AppFont.bold(16))
                .foregroundColor(tc.textPrimary)
                .lineLimit(1)

            Text(card.description)
                .font(AppFont.regular(12))
                .foregroundColor(tc.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DesignSystem.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .adaptiveCard(borderColor: tc.primary.opacity(0.25), fillColor: tc.cardBackground)
    }
}
