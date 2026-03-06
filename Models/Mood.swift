//
//  Mood.swift
//  HealthBar
//
//  Created by Claude on 2/2/26.
//

import Foundation
import SwiftUI

/// Represents how the user is feeling for daily mood tracking
///
/// Simple 3-option scale for quick daily check-ins.
enum Mood: String, Codable, CaseIterable {
    case great = "great"
    case okay = "okay"
    case rough = "rough"

    /// Display name for the mood
    var displayName: String {
        rawValue.capitalized
    }

    /// Large emoji representation for button display
    var emoji: String {
        switch self {
        case .great: return "😊"
        case .okay: return "😐"
        case .rough: return "😔"
        }
    }

    /// Color associated with the mood
    var color: Color {
        switch self {
        case .great: return DesignSystem.Colors.primary  // Green
        case .okay: return Color(hex: "#F59E0B")  // Amber
        case .rough: return Color(hex: "#6B7280")  // Gray
        }
    }

    /// Subtitle description for the mood
    var subtitle: String {
        switch self {
        case .great: return "Feeling good!"
        case .okay: return "Could be better"
        case .rough: return "Not my best day"
        }
    }
}
