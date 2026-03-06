//
//  MealType.swift
//  HealthBar
//
//  Created by Claude on 2/2/26.
//

import Foundation
import SwiftUI

/// Represents the type of meal based on time of day
///
/// Auto-assigned when logging food based on the current time.
/// Non-editable by user - purely for organization and display.
enum MealType: String, Codable, CaseIterable {
    case breakfast = "breakfast"
    case lunch = "lunch"
    case dinner = "dinner"
    case snack = "snack"
    case uncategorized = "uncategorized"

    /// Display name (capitalized)
    var displayName: String {
        rawValue.capitalized
    }

    /// SF Symbol icon for the meal type
    var icon: String {
        switch self {
        case .breakfast:
            return "sun.horizon.fill"
        case .lunch:
            return "sun.max.fill"
        case .dinner:
            return "moon.fill"
        case .snack:
            return "carrot.fill"
        case .uncategorized:
            return "fork.knife"
        }
    }

    /// Color associated with the meal type
    var color: Color {
        switch self {
        case .breakfast:
            return Color(hex: "#F59E0B") // Warm amber/orange
        case .lunch:
            return Color(hex: "#10B981") // Green (matches secondary)
        case .dinner:
            return Color(hex: "#6366F1") // Indigo/purple
        case .snack:
            return Color(hex: "#EC4899") // Pink
        case .uncategorized:
            return Color(hex: "#6B7280") // Gray
        }
    }

    /// Auto-assigns meal type based on time of day
    ///
    /// Time ranges:
    /// - 5am-11am: Breakfast
    /// - 11am-4pm: Lunch
    /// - 4pm-9pm: Dinner
    /// - 9pm-5am: Snack
    ///
    /// - Parameter date: The date/time to evaluate
    /// - Returns: Appropriate MealType for the time
    static func fromTime(_ date: Date) -> MealType {
        let hour = Calendar.current.component(.hour, from: date)

        switch hour {
        case 5..<11:
            return .breakfast
        case 11..<16:
            return .lunch
        case 16..<21:
            return .dinner
        default:
            return .snack
        }
    }
}
