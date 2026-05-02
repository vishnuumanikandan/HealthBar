//
//  TimeOfDayTheme.swift
//  HealthBar
//
//  Created by Claude on 4/30/26.
//

import SwiftUI

/// Represents the three time-of-day visual themes
enum TimeOfDayTheme: String, CaseIterable, Identifiable, Equatable {
    case morning
    case afternoon
    case night

    var id: String { rawValue }

    /// Display name for settings UI
    var displayName: String {
        switch self {
        case .morning: return "Morning"
        case .afternoon: return "Afternoon"
        case .night: return "Night"
        }
    }

    /// SF Symbol icon for settings picker
    var icon: String {
        switch self {
        case .morning: return "sun.max.fill"
        case .afternoon: return "sunset.fill"
        case .night: return "moon.stars.fill"
        }
    }

    /// Determine theme from current hour
    static func current() -> TimeOfDayTheme {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 6..<14: return .morning
        case 14..<19: return .afternoon
        default: return .night
        }
    }

    /// Resolved ThemeColors for this theme
    var colors: ThemeColors {
        switch self {
        case .morning: return Self.morningColors
        case .afternoon: return Self.afternoonColors
        case .night: return Self.nightColors
        }
    }
}

// MARK: - ThemeColors

struct ThemeColors {
    // Background
    let primaryBackground: Color
    let cardBackground: Color

    // Primary accent (borders, active elements)
    let primary: Color
    let primaryDark: Color
    let primaryDarker: Color

    // Text
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color

    // Ring
    let ringFilled: Color
    let ringEmpty: Color

    // XP bar
    let xpTrackBackground: Color
    let xpTrackBorder: Color
    let xpFillLight: Color
    let xpFillDark: Color

    // Macro bar fills
    let macroBarProtein: Color
    let macroBarCarbs: Color
    let macroBarFat: Color
    let macroBarTrack: Color

    // Buttons (Log Food / Scan)
    let buttonLight: Color
    let buttonMid: Color
    let buttonDark: Color
    let buttonBorder: Color

    // Quest board background type
    let questBoardStyle: QuestBoardStyle

    // Purity bar bands (bottom to top)
    let purityBand1: Color // bottom (good)
    let purityBand2: Color
    let purityBand3: Color
    let purityBand4: Color // top (bad)

    // Segmented control
    let segBackground: Color
    let segInactiveFill: Color
    let segInactiveText: Color
    let segActiveFill: Color
    let segActiveText: Color

    // Weekly chart bars
    let barLight: Color
    let barDark: Color
    let barBorder: Color
    let barTodayLight: Color
    let barTodayDark: Color
    let barTodayBorder: Color
    let chartAxisColor: Color
    let goalLineColor: Color

    // "This Week" stats card
    let statsContainerBorder: Color
    let statsContainerFill: Color
    let statsTitle: Color
    let statCellBorder: Color
    let statCellFill: Color
    let statLabel: Color
    let statValue: Color
    let statSubtitle: Color
    let statOnBorder: Color
    let statOnLight: Color
    let statOnMid: Color
    let statOnDark: Color

    // Tab bar
    let tabBarLight: Color
    let tabBarMid: Color
    let tabBarDark: Color
    let tabActive: Color
    let tabInactive: Color

    // Inventory slots
    let invBorderColor: Color
    let invTimeBg: Color

    // 3-band gradients for icon pills
    let iconGreen: (light: Color, mid: Color, dark: Color, border: Color)
    let iconAmber: (light: Color, mid: Color, dark: Color, border: Color)
    let iconOrange: (light: Color, mid: Color, dark: Color, border: Color)

    enum QuestBoardStyle {
        case wood    // morning + afternoon
        case crystal // night (dark indigo stone)
    }
}

// MARK: - Morning Palette

extension TimeOfDayTheme {
    static let morningColors = ThemeColors(
        primaryBackground: Color(hex: "#DCFCE7"),
        cardBackground: Color(hex: "#F3FDF7"),
        primary: Color(hex: "#059669"),
        primaryDark: Color(hex: "#047857"),
        primaryDarker: Color(hex: "#064E3B"),
        textPrimary: Color(hex: "#111827"),
        textSecondary: Color(hex: "#6B7280"),
        textTertiary: Color(hex: "#9CA3AF"),
        ringFilled: Color(hex: "#059669"),
        ringEmpty: Color(hex: "#E5E7EB"),
        xpTrackBackground: Color(hex: "#E5E7EB"),
        xpTrackBorder: Color(hex: "#059669"),
        xpFillLight: Color(hex: "#34D399"),
        xpFillDark: Color(hex: "#10B981"),
        macroBarProtein: Color(hex: "#EA580C"),
        macroBarCarbs: Color(hex: "#EA580C"),
        macroBarFat: Color(hex: "#10B981"),
        macroBarTrack: Color(hex: "#E5E7EB"),
        buttonLight: Color(hex: "#34D399"),
        buttonMid: Color(hex: "#10B981"),
        buttonDark: Color(hex: "#047857"),
        buttonBorder: Color(hex: "#047857"),
        questBoardStyle: .wood,
        purityBand1: Color(hex: "#059669"),
        purityBand2: Color(hex: "#84CC16"),
        purityBand3: Color(hex: "#EA580C"),
        purityBand4: Color(hex: "#DC2626"),
        segBackground: Color(hex: "#DCFCE7"),
        segInactiveFill: Color(hex: "#374151"),
        segInactiveText: Color(hex: "#D1D5DB"),
        segActiveFill: Color.white,
        segActiveText: Color(hex: "#111827"),
        barLight: Color(hex: "#6EE7B7"),
        barDark: Color(hex: "#10B981"),
        barBorder: Color(hex: "#047857"),
        barTodayLight: Color(hex: "#34D399"),
        barTodayDark: Color(hex: "#059669"),
        barTodayBorder: Color(hex: "#064E3B"),
        chartAxisColor: Color(hex: "#059669"),
        goalLineColor: Color(hex: "#EA580C"),
        statsContainerBorder: Color(hex: "#4338CA"),
        statsContainerFill: Color(hex: "#EEF2FF"),
        statsTitle: Color(hex: "#312E81"),
        statCellBorder: Color(hex: "#6366F1"),
        statCellFill: Color(hex: "#E0E7FF"),
        statLabel: Color(hex: "#4338CA"),
        statValue: Color(hex: "#312E81"),
        statSubtitle: Color(hex: "#6366F1"),
        statOnBorder: Color(hex: "#4338CA"),
        statOnLight: Color(hex: "#818CF8"),
        statOnMid: Color(hex: "#6366F1"),
        statOnDark: Color(hex: "#4338CA"),
        tabBarLight: Color(hex: "#A0723D"),
        tabBarMid: Color(hex: "#8B5A2B"),
        tabBarDark: Color(hex: "#5D3A1A"),
        tabActive: Color(hex: "#FCD34D"),
        tabInactive: Color(hex: "#D2B48C"),
        invBorderColor: Color(hex: "#059669"),
        invTimeBg: Color(hex: "#DCFCE7").opacity(0.85),
        iconGreen: (Color(hex: "#34D399"), Color(hex: "#10B981"), Color(hex: "#059669"), Color(hex: "#047857")),
        iconAmber: (Color(hex: "#FBBF24"), Color(hex: "#D97706"), Color(hex: "#92400E"), Color(hex: "#92400E")),
        iconOrange: (Color(hex: "#FB923C"), Color(hex: "#EA580C"), Color(hex: "#C2410C"), Color(hex: "#C2410C"))
    )
}

// MARK: - Afternoon Palette

extension TimeOfDayTheme {
    static let afternoonColors = ThemeColors(
        primaryBackground: Color(hex: "#FEF3C7"),
        cardBackground: Color(hex: "#FFFBEB"),
        primary: Color(hex: "#B45309"),
        primaryDark: Color(hex: "#92400E"),
        primaryDarker: Color(hex: "#78350F"),
        textPrimary: Color(hex: "#78350F"),
        textSecondary: Color(hex: "#92400E"),
        textTertiary: Color(hex: "#B45309"),
        ringFilled: Color(hex: "#D97706"),
        ringEmpty: Color(hex: "#FDE68A"),
        xpTrackBackground: Color(hex: "#FDE68A"),
        xpTrackBorder: Color(hex: "#B45309"),
        xpFillLight: Color(hex: "#FBBF24"),
        xpFillDark: Color(hex: "#D97706"),
        macroBarProtein: Color(hex: "#EA580C"),
        macroBarCarbs: Color(hex: "#EA580C"),
        macroBarFat: Color(hex: "#D97706"),
        macroBarTrack: Color(hex: "#FDE68A"),
        buttonLight: Color(hex: "#FBBF24"),
        buttonMid: Color(hex: "#D97706"),
        buttonDark: Color(hex: "#92400E"),
        buttonBorder: Color(hex: "#92400E"),
        questBoardStyle: .wood,
        purityBand1: Color(hex: "#65A30D"),
        purityBand2: Color(hex: "#D97706"),
        purityBand3: Color(hex: "#EA580C"),
        purityBand4: Color(hex: "#DC2626"),
        segBackground: Color(hex: "#FDE68A"),
        segInactiveFill: Color(hex: "#78350F"),
        segInactiveText: Color(hex: "#FDE68A"),
        segActiveFill: Color(hex: "#FFFBEB"),
        segActiveText: Color(hex: "#78350F"),
        barLight: Color(hex: "#FDE68A"),
        barDark: Color(hex: "#D97706"),
        barBorder: Color(hex: "#92400E"),
        barTodayLight: Color(hex: "#FBBF24"),
        barTodayDark: Color(hex: "#B45309"),
        barTodayBorder: Color(hex: "#78350F"),
        chartAxisColor: Color(hex: "#B45309"),
        goalLineColor: Color(hex: "#DC2626"),
        statsContainerBorder: Color(hex: "#92400E"),
        statsContainerFill: Color(hex: "#FEF3C7"),
        statsTitle: Color(hex: "#78350F"),
        statCellBorder: Color(hex: "#B45309"),
        statCellFill: Color(hex: "#FDE68A"),
        statLabel: Color(hex: "#92400E"),
        statValue: Color(hex: "#78350F"),
        statSubtitle: Color(hex: "#B45309"),
        statOnBorder: Color(hex: "#78350F"),
        statOnLight: Color(hex: "#FBBF24"),
        statOnMid: Color(hex: "#D97706"),
        statOnDark: Color(hex: "#92400E"),
        tabBarLight: Color(hex: "#A0723D"),
        tabBarMid: Color(hex: "#8B5A2B"),
        tabBarDark: Color(hex: "#5D3A1A"),
        tabActive: Color(hex: "#FCD34D"),
        tabInactive: Color(hex: "#D2B48C"),
        invBorderColor: Color(hex: "#B45309"),
        invTimeBg: Color(hex: "#FEF3C7").opacity(0.85),
        iconGreen: (Color(hex: "#A3E635"), Color(hex: "#65A30D"), Color(hex: "#3F6212"), Color(hex: "#3F6212")),
        iconAmber: (Color(hex: "#FBBF24"), Color(hex: "#D97706"), Color(hex: "#92400E"), Color(hex: "#92400E")),
        iconOrange: (Color(hex: "#FB923C"), Color(hex: "#EA580C"), Color(hex: "#C2410C"), Color(hex: "#9A3412"))
    )
}

// MARK: - Night Palette

extension TimeOfDayTheme {
    static let nightColors = ThemeColors(
        primaryBackground: Color(hex: "#0F172A"),
        cardBackground: Color(hex: "#1E1B4B"),
        primary: Color(hex: "#6366F1"),
        primaryDark: Color(hex: "#4338CA"),
        primaryDarker: Color(hex: "#3730A3"),
        textPrimary: Color(hex: "#E0E7FF"),
        textSecondary: Color(hex: "#A5B4FC"),
        textTertiary: Color(hex: "#818CF8"),
        ringFilled: Color(hex: "#818CF8"),
        ringEmpty: Color(hex: "#312E81"),
        xpTrackBackground: Color(hex: "#312E81"),
        xpTrackBorder: Color(hex: "#6366F1"),
        xpFillLight: Color(hex: "#818CF8"),
        xpFillDark: Color(hex: "#6366F1"),
        macroBarProtein: Color(hex: "#818CF8"),
        macroBarCarbs: Color(hex: "#A855F7"),
        macroBarFat: Color(hex: "#6366F1"),
        macroBarTrack: Color(hex: "#312E81"),
        buttonLight: Color(hex: "#818CF8"),
        buttonMid: Color(hex: "#6366F1"),
        buttonDark: Color(hex: "#4338CA"),
        buttonBorder: Color(hex: "#3730A3"),
        questBoardStyle: .crystal,
        purityBand1: Color(hex: "#6366F1"),
        purityBand2: Color(hex: "#818CF8"),
        purityBand3: Color(hex: "#A855F7"),
        purityBand4: Color(hex: "#EC4899"),
        segBackground: Color(hex: "#312E81"),
        segInactiveFill: Color(hex: "#0F0E2A"),
        segInactiveText: Color(hex: "#818CF8"),
        segActiveFill: Color(hex: "#E0E7FF"),
        segActiveText: Color(hex: "#1E1B4B"),
        barLight: Color(hex: "#A5B4FC"),
        barDark: Color(hex: "#6366F1"),
        barBorder: Color(hex: "#818CF8"),
        barTodayLight: Color(hex: "#C084FC"),
        barTodayDark: Color(hex: "#7C3AED"),
        barTodayBorder: Color(hex: "#A855F7"),
        chartAxisColor: Color(hex: "#6366F1"),
        goalLineColor: Color(hex: "#EC4899"),
        statsContainerBorder: Color(hex: "#7C3AED"),
        statsContainerFill: Color(hex: "#2E1065"),
        statsTitle: Color(hex: "#E9D5FF"),
        statCellBorder: Color(hex: "#A855F7"),
        statCellFill: Color(hex: "#3B0764"),
        statLabel: Color(hex: "#C084FC"),
        statValue: Color(hex: "#E9D5FF"),
        statSubtitle: Color(hex: "#A855F7"),
        statOnBorder: Color(hex: "#7C3AED"),
        statOnLight: Color(hex: "#C084FC"),
        statOnMid: Color(hex: "#A855F7"),
        statOnDark: Color(hex: "#7C3AED"),
        tabBarLight: Color(hex: "#312E81"),
        tabBarMid: Color(hex: "#1E1B4B"),
        tabBarDark: Color(hex: "#0F0E2A"),
        tabActive: Color(hex: "#C084FC"),
        tabInactive: Color(hex: "#6366F1"),
        invBorderColor: Color(hex: "#6366F1"),
        invTimeBg: Color(hex: "#1E1B4B").opacity(0.85),
        iconGreen: (Color(hex: "#67E8F9"), Color(hex: "#22D3EE"), Color(hex: "#06B6D4"), Color(hex: "#155E75")),
        iconAmber: (Color(hex: "#FBBF24"), Color(hex: "#D97706"), Color(hex: "#92400E"), Color(hex: "#92400E")),
        iconOrange: (Color(hex: "#C084FC"), Color(hex: "#A855F7"), Color(hex: "#7C3AED"), Color(hex: "#581C87"))
    )
}
