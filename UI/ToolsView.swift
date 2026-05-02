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

struct ToolsView: View {

    let toolsViewModel: ToolsViewModel

    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeTheme.colors }

    // Grid columns
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: DesignSystem.Spacing.md) {
                    ForEach(CalculatorCard.allCards) { card in
                        NavigationLink(destination: destinationView(for: card)) {
                            CalculatorCardView(card: card, tc: tc)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(DesignSystem.Spacing.md)
            }
            .background(tc.primaryBackground.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Tools")
                        .font(PixelFont.bold(20))
                        .foregroundColor(tc.textPrimary)
                }
            }
        }
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
                    .font(PixelFont.regular(18))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .pixelPill(
                        borderColor: card.iconColor.adjustedBrightness(-0.2),
                        fillColor: .clear,
                        fillGradient: DesignSystem.Colors.threeBandFrom(card.iconColor)
                    )
                Spacer()
                Image(systemName: "chevron.right")
                    .font(PixelFont.bold(12))
                    .foregroundColor(tc.textTertiary)
            }

            Text(card.title)
                .font(PixelFont.bold(16))
                .foregroundColor(tc.textPrimary)
                .lineLimit(1)

            Text(card.description)
                .font(PixelFont.regular(12))
                .foregroundColor(tc.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DesignSystem.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pixelCard(borderColor: tc.primary.opacity(0.25), fillColor: tc.cardBackground)
    }
}
