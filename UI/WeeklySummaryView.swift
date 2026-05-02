//
//  WeeklySummaryView.swift
//  HealthBar
//
//  Created by Claude on 2/3/26.
//  Updated on 4/29/26 - Pixel-art RPG redesign
//  Updated on 4/30/26 - Day/night theme integration
//

import SwiftUI

/// Data model for a single day's summary in the weekly view
struct DaySummary: Identifiable {
    let id = UUID()
    let date: Date
    let calories: Int
    let protein: Double
    let purityScore: Int
    let mealCount: Int

    var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    var dayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    var dayNumber: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }
}

/// Weekly summary statistics
struct WeeklySummary {
    let days: [DaySummary]
    let calorieGoal: Int
    let proteinGoal: Double
    let purityGoal: Int

    var avgCalories: Int {
        guard !days.isEmpty else { return 0 }
        return days.reduce(0) { $0 + $1.calories } / days.count
    }

    var avgProtein: Double {
        guard !days.isEmpty else { return 0 }
        return days.reduce(0.0) { $0 + $1.protein } / Double(days.count)
    }

    var avgPurity: Int {
        guard !days.isEmpty else { return 0 }
        return days.reduce(0) { $0 + $1.purityScore } / days.count
    }

    var daysLogged: Int {
        days.filter { $0.mealCount > 0 }.count
    }

    var totalMeals: Int {
        days.reduce(0) { $0 + $1.mealCount }
    }
}

/// Weekly summary view showing Mon-Sun stats with pixel-art bar chart
struct WeeklySummaryView: View {

    let summary: WeeklySummary
    var theme: TimeOfDayTheme = .morning
    @State private var selectedMetric: WeeklyMetric = .calories

    private var tc: ThemeColors { theme.colors }

    var body: some View {
        VStack(spacing: 14) {
            // Segmented control
            pixelSegmentedControl

            // Bar chart
            pixelBarChart

            // This Week stats
            thisWeekStats
        }
    }

    // MARK: - Pixel Segmented Control

    private var pixelSegmentedControl: some View {
        PixelCard(borderColor: tc.segBackground, fillColor: tc.segBackground) {
            HStack(spacing: 0) {
                ForEach(WeeklyMetric.allCases) { metric in
                    Button {
                        selectedMetric = metric
                    } label: {
                        PixelPill(
                            borderColor: tc.segBackground,
                            fillColor: metric == selectedMetric ? tc.segActiveFill : tc.segInactiveFill
                        ) {
                            Text(metric.displayName)
                                .font(DesignSystem.Typography.pixel(13, weight: metric == selectedMetric ? .bold : .regular))
                                .foregroundColor(metric == selectedMetric ? tc.segActiveText : tc.segInactiveText)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(4)
        }
        .frame(height: 44)
    }

    // MARK: - Pixel Bar Chart

    private var pixelBarChart: some View {
        PixelCard(borderColor: tc.primary, fillColor: tc.cardBackground) {
            VStack(spacing: 10) {
                // Goal line text
                Text(goalText)
                    .font(DesignSystem.Typography.pixel(13))
                    .foregroundColor(tc.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Chart area
                ZStack(alignment: .bottom) {
                    // Goal line
                    GeometryReader { geometry in
                        let goalY = geometry.size.height * (1 - goalForMetric(selectedMetric) / maxValue)
                        Rectangle()
                            .fill(tc.goalLineColor)
                            .frame(height: 2)
                            .offset(y: goalY)
                    }

                    HStack(alignment: .bottom, spacing: 6) {
                        ForEach(summary.days) { day in
                            pixelDayBar(day)
                        }
                    }

                    // Bottom border
                    VStack {
                        Spacer()
                        Rectangle()
                            .fill(tc.chartAxisColor)
                            .frame(height: 2)
                    }
                }
                .frame(height: 200)
                .padding(.horizontal, 8)

                // Day labels
                HStack(spacing: 6) {
                    ForEach(summary.days) { day in
                        VStack(spacing: 4) {
                            Text(day.dayName)
                                .font(DesignSystem.Typography.pixel(12))
                                .foregroundColor(day.isToday ? tc.primary : tc.textTertiary)
                                .fontWeight(day.isToday ? .bold : .regular)
                            Text(day.dayNumber)
                                .font(DesignSystem.Typography.pixel(11))
                                .foregroundColor(day.isToday ? tc.primary : tc.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(16)
        }
    }

    private func pixelDayBar(_ day: DaySummary) -> some View {
        let value = selectedMetric.value(from: day)
        let heightPercent = maxValue > 0 ? min(value / maxValue, 1.0) : 0

        return VStack {
            Spacer()
            if value > 0 {
                // 2-tone bar
                ZStack(alignment: .top) {
                    // Bar body
                    LinearGradient(
                        stops: [
                            .init(color: day.isToday ? tc.barTodayLight : tc.barLight, location: 0),
                            .init(color: day.isToday ? tc.barTodayLight : tc.barLight, location: 0.35),
                            .init(color: day.isToday ? tc.barTodayDark : tc.barDark, location: 0.35),
                            .init(color: day.isToday ? tc.barTodayDark : tc.barDark, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 200 * heightPercent)

                    // Top border
                    Rectangle()
                        .fill(day.isToday ? tc.barTodayBorder : tc.barBorder)
                        .frame(height: 2)
                }
                .frame(height: 200 * heightPercent)
            } else {
                // Empty bar placeholder
                Rectangle()
                    .fill(tc.primary.opacity(0.3))
                    .frame(height: 2)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - This Week Stats

    private var thisWeekStats: some View {
        PixelCard(borderColor: tc.statsContainerBorder, fillColor: tc.statsContainerFill) {
            VStack(spacing: 14) {
                Text("This Week")
                    .font(DesignSystem.Typography.pixel(18, weight: .bold))
                    .foregroundColor(tc.statsTitle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    let calOnTrack = summary.avgCalories <= summary.calorieGoal
                    statCard(
                        title: "Avg Cal",
                        value: "\(summary.avgCalories)",
                        subtitle: calOnTrack ? "on track" : "off",
                        isOnTrack: calOnTrack
                    )

                    let protOnTrack = summary.avgProtein >= summary.proteinGoal
                    statCard(
                        title: "Avg Protein",
                        value: String(format: "%.0fg", summary.avgProtein),
                        subtitle: protOnTrack ? "on track" : "off",
                        isOnTrack: protOnTrack
                    )

                    statCard(
                        title: "Days",
                        value: "\(summary.daysLogged)/7",
                        subtitle: "\(summary.totalMeals) meals",
                        isOnTrack: summary.daysLogged >= 5
                    )
                }
            }
            .padding(18)
        }
    }

    private func statCard(title: String, value: String, subtitle: String, isOnTrack: Bool) -> some View {
        PixelCard(
            borderColor: isOnTrack ? tc.statOnBorder : tc.statCellBorder,
            fillColor: isOnTrack ? .clear : tc.statCellFill,
            fillGradient: isOnTrack ? DesignSystem.Colors.threeBand(light: tc.statOnLight, mid: tc.statOnMid, dark: tc.statOnDark) : nil
        ) {
            VStack(spacing: 8) {
                Text(title)
                    .font(DesignSystem.Typography.pixel(11))
                    .foregroundColor(isOnTrack ? .white.opacity(0.85) : tc.statLabel)
                    .multilineTextAlignment(.center)

                Text(value)
                    .font(DesignSystem.Typography.pixel(20, weight: .bold))
                    .foregroundColor(isOnTrack ? .white : tc.statValue)

                Text(subtitle)
                    .font(DesignSystem.Typography.pixel(11))
                    .foregroundColor(isOnTrack ? .white.opacity(0.85) : tc.statSubtitle)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Helpers

    private var maxValue: Double {
        let values = summary.days.map { selectedMetric.value(from: $0) }
        let maxData = values.max() ?? 0
        return max(maxData, goalForMetric(selectedMetric)) * 1.1
    }

    private func goalForMetric(_ metric: WeeklyMetric) -> Double {
        switch metric {
        case .calories: return Double(summary.calorieGoal)
        case .protein: return summary.proteinGoal
        case .purity: return Double(summary.purityGoal)
        }
    }

    private var goalText: String {
        switch selectedMetric {
        case .calories: return "Goal: \(summary.calorieGoal) cal/day"
        case .protein: return "Goal: \(Int(summary.proteinGoal)) g/day"
        case .purity: return "Goal: \(summary.purityGoal)+ purity"
        }
    }
}

// MARK: - Weekly Metric Enum

enum WeeklyMetric: String, CaseIterable, Identifiable {
    case calories
    case protein
    case purity

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .calories: return "Calories"
        case .protein: return "Protein"
        case .purity: return "Purity"
        }
    }

    func value(from day: DaySummary) -> Double {
        switch self {
        case .calories: return Double(day.calories)
        case .protein: return day.protein
        case .purity: return Double(day.purityScore)
        }
    }
}

// MARK: - Preview

#Preview("Weekly Summary View") {
    let calendar = Calendar.current
    let today = Date()

    let sampleDays = (0..<7).map { dayOffset -> DaySummary in
        let date = calendar.date(byAdding: .day, value: -6 + dayOffset, to: today)!
        return DaySummary(
            date: date,
            calories: dayOffset == 6 ? 1800 : Int.random(in: 1500...2200),
            protein: dayOffset == 6 ? 130 : Double.random(in: 80...160),
            purityScore: dayOffset == 6 ? 25 : Int.random(in: 15...45),
            mealCount: dayOffset == 6 ? 3 : Int.random(in: 2...5)
        )
    }

    let summary = WeeklySummary(
        days: sampleDays,
        calorieGoal: 2000,
        proteinGoal: 150.0,
        purityGoal: 30
    )

    return ScrollView {
        WeeklySummaryView(summary: summary, theme: .night)
            .padding()
    }
    .background(Color(hex: "#0F172A"))
}
