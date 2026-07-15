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

    /// SF Symbol name for button display, tinted with `color`.
    var symbolName: String {
        switch self {
        case .great: return "face.smiling"
        case .okay: return "face.dashed"
        case .rough: return "cloud.rain.fill"
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
