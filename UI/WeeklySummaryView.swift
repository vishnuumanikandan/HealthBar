//
//  WeeklySummaryView.swift
//  HealthBar
//
//  Created by Claude on 2/3/26.
//

import SwiftUI

/// Data model for a single day's summary in the weekly view
struct DaySummary: Identifiable {
    let id = UUID()

    /// Date of this day
    let date: Date

    /// Total calories consumed
    let calories: Int

    /// Total protein consumed
    let protein: Double

    /// Total purity score
    let purityScore: Int

    /// Number of meals logged
    let mealCount: Int

    /// Whether this is today
    var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    /// Short day name (e.g., "Mon", "Tue")
    var dayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    /// Day number (e.g., "12")
    var dayNumber: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }
}

/// Weekly summary statistics
struct WeeklySummary {
    /// Array of day summaries (Mon-Sun)
    let days: [DaySummary]

    /// Calorie goal for comparison
    let calorieGoal: Int

    /// Protein goal for comparison
    let proteinGoal: Double

    /// Purity goal for comparison
    let purityGoal: Int

    /// Average daily calories
    var avgCalories: Int {
        guard !days.isEmpty else { return 0 }
        return days.reduce(0) { $0 + $1.calories } / days.count
    }

    /// Average daily protein
    var avgProtein: Double {
        guard !days.isEmpty else { return 0 }
        return days.reduce(0.0) { $0 + $1.protein } / Double(days.count)
    }

    /// Average daily purity
    var avgPurity: Int {
        guard !days.isEmpty else { return 0 }
        return days.reduce(0) { $0 + $1.purityScore } / days.count
    }

    /// Days with meals logged
    var daysLogged: Int {
        days.filter { $0.mealCount > 0 }.count
    }

    /// Total meals this week
    var totalMeals: Int {
        days.reduce(0) { $0 + $1.mealCount }
    }
}

/// Weekly summary view showing Mon-Sun stats with bar chart
struct WeeklySummaryView: View {

    /// Weekly summary data
    let summary: WeeklySummary

    /// Selected metric to display in bar chart
    @State private var selectedMetric: WeeklyMetric = .calories

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            // Metric selector
            metricPicker

            // Bar chart
            WeeklyBarChart(
                days: summary.days,
                metric: selectedMetric,
                goal: goalForMetric(selectedMetric)
            )

            // Summary stats
            summaryStats
        }
    }

    // MARK: - Metric Picker

    private var metricPicker: some View {
        Picker("Metric", selection: $selectedMetric) {
            ForEach(WeeklyMetric.allCases) { metric in
                Text(metric.displayName).tag(metric)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Summary Stats

    private var summaryStats: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            Text("This Week")
                .font(.system(size: DesignSystem.FontSizes.headline, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: DesignSystem.Spacing.md) {
                WeeklyStatCard(
                    title: "Avg Calories",
                    value: "\(summary.avgCalories)",
                    subtitle: "goal: \(summary.calorieGoal)",
                    isOnTrack: summary.avgCalories <= summary.calorieGoal
                )

                WeeklyStatCard(
                    title: "Avg Protein",
                    value: String(format: "%.0fg", summary.avgProtein),
                    subtitle: "goal: \(Int(summary.proteinGoal))g",
                    isOnTrack: summary.avgProtein >= summary.proteinGoal
                )

                WeeklyStatCard(
                    title: "Days Logged",
                    value: "\(summary.daysLogged)/7",
                    subtitle: "\(summary.totalMeals) meals",
                    isOnTrack: summary.daysLogged >= 5
                )
            }
        }
        .padding(DesignSystem.Spacing.lg)
        .background(DesignSystem.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                .strokeBorder(DesignSystem.Colors.primary.opacity(0.25), lineWidth: 1.5)
        )
        .shadow(
            color: DesignSystem.Shadows.card.color,
            radius: DesignSystem.Shadows.card.radius,
            x: DesignSystem.Shadows.card.x,
            y: DesignSystem.Shadows.card.y
        )
    }

    // MARK: - Helpers

    private func goalForMetric(_ metric: WeeklyMetric) -> Double {
        switch metric {
        case .calories:
            return Double(summary.calorieGoal)
        case .protein:
            return summary.proteinGoal
        case .purity:
            return Double(summary.purityGoal)
        }
    }
}

// MARK: - Weekly Metric Enum

/// Metrics that can be displayed in the weekly bar chart
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

    /// Extract value from DaySummary for this metric
    func value(from day: DaySummary) -> Double {
        switch self {
        case .calories: return Double(day.calories)
        case .protein: return day.protein
        case .purity: return Double(day.purityScore)
        }
    }
}

// MARK: - Weekly Stat Card

/// Small stat card for weekly summary
struct WeeklyStatCard: View {
    let title: String
    let value: String
    let subtitle: String
    let isOnTrack: Bool

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.xs) {
            Text(title)
                .font(.system(size: DesignSystem.FontSizes.caption, weight: .medium))
                .foregroundColor(DesignSystem.Colors.textSecondary)

            Text(value)
                .font(.system(size: DesignSystem.FontSizes.title3, weight: .bold))
                .foregroundColor(isOnTrack ? DesignSystem.Colors.primary : DesignSystem.Colors.textPrimary)

            Text(subtitle)
                .font(.system(size: 10, weight: .regular))
                .foregroundColor(DesignSystem.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(DesignSystem.Spacing.sm)
        .background(isOnTrack ? DesignSystem.Colors.primary.opacity(0.1) : DesignSystem.Colors.border.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm))
    }
}

// MARK: - Weekly Bar Chart

/// Bar chart showing daily values for the week
struct WeeklyBarChart: View {
    let days: [DaySummary]
    let metric: WeeklyMetric
    let goal: Double

    /// Maximum value for scaling bars
    private var maxValue: Double {
        let values = days.map { metric.value(from: $0) }
        let maxData = values.max() ?? 0
        return max(maxData, goal) * 1.1 // Add 10% headroom
    }

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            // Goal line indicator
            HStack {
                Text("Goal: \(goalText)")
                    .font(.system(size: DesignSystem.FontSizes.caption, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textSecondary)

                Spacer()
            }

            // Chart area
            HStack(alignment: .bottom, spacing: DesignSystem.Spacing.sm) {
                ForEach(days) { day in
                    DayBarView(
                        day: day,
                        value: metric.value(from: day),
                        maxValue: maxValue,
                        goal: goal,
                        metric: metric
                    )
                }
            }
            .frame(height: 160)
            .padding(.horizontal, DesignSystem.Spacing.sm)
            .overlay(
                // Goal line
                GeometryReader { geometry in
                    let goalY = geometry.size.height * (1 - goal / maxValue)
                    Rectangle()
                        .fill(DesignSystem.Colors.warning)
                        .frame(height: 2)
                        .offset(y: goalY)
                }
            )
        }
        .padding(DesignSystem.Spacing.lg)
        .background(DesignSystem.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                .strokeBorder(DesignSystem.Colors.primary.opacity(0.25), lineWidth: 1.5)
        )
        .shadow(
            color: DesignSystem.Shadows.card.color,
            radius: DesignSystem.Shadows.card.radius,
            x: DesignSystem.Shadows.card.x,
            y: DesignSystem.Shadows.card.y
        )
    }

    private var goalText: String {
        switch metric {
        case .calories:
            return "\(Int(goal)) cal"
        case .protein:
            return "\(Int(goal))g"
        case .purity:
            return "\(Int(goal))"
        }
    }
}

// MARK: - Day Bar View

/// Single bar in the weekly chart
struct DayBarView: View {
    let day: DaySummary
    let value: Double
    let maxValue: Double
    let goal: Double
    let metric: WeeklyMetric

    /// Height percentage (0.0 to 1.0)
    private var heightPercentage: Double {
        guard maxValue > 0 else { return 0 }
        return min(value / maxValue, 1.0)
    }

    /// Whether this day met the goal
    private var metGoal: Bool {
        switch metric {
        case .calories:
            // For calories, lower is better (under goal)
            return value <= goal && value > 0
        case .protein:
            // For protein, higher is better (over goal)
            return value >= goal
        case .purity:
            // For purity (toxin score), lower is better
            return value <= goal && value > 0
        }
    }

    /// Color for the bar
    private var barColor: Color {
        if value == 0 {
            return DesignSystem.Colors.border
        } else if metGoal {
            return DesignSystem.Colors.primary
        } else {
            return DesignSystem.Colors.warning
        }
    }

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.xs) {
            // Value label (only show if non-zero)
            if value > 0 {
                Text(valueText)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            // Bar
            GeometryReader { geometry in
                VStack {
                    Spacer()

                    RoundedRectangle(cornerRadius: 4)
                        .fill(barColor)
                        .frame(height: max(geometry.size.height * heightPercentage, value > 0 ? 4 : 2))
                }
            }

            // Day label
            VStack(spacing: 2) {
                Text(day.dayName)
                    .font(.system(size: 10, weight: day.isToday ? .bold : .medium))
                    .foregroundColor(day.isToday ? DesignSystem.Colors.primary : DesignSystem.Colors.textSecondary)

                Text(day.dayNumber)
                    .font(.system(size: 9, weight: .regular))
                    .foregroundColor(DesignSystem.Colors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var valueText: String {
        switch metric {
        case .calories:
            return "\(Int(value))"
        case .protein:
            return "\(Int(value))g"
        case .purity:
            return "\(Int(value))"
        }
    }
}

// MARK: - Preview

#Preview("Weekly Summary View") {
    let calendar = Calendar.current
    let today = Date()

    // Generate sample week data
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
        WeeklySummaryView(summary: summary)
            .padding()
    }
    .background(DesignSystem.Colors.primaryBackground)
}
