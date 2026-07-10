//
//  UndoToast.swift
//  HealthBar
//
//  Created by Claude on 1/26/26.
//

import SwiftUI

/// Toast component for delete undo functionality
///
/// Features:
/// - Themed card surface + hairline with primary text (D8 retint — tokenized so it
///   tracks the active scheme; pixel unchanged as an adaptiveCard consumer)
/// - Food name on left, "Undo" button on right
/// - Slides up from bottom
/// - Positioned above tab bar
/// - Never overlaps XP toasts (those are in upper half)
struct UndoToast: View {

    // MARK: - Properties

    /// Message to display (e.g., "Chicken Salad deleted")
    let message: String

    /// Action when Undo is tapped
    let onUndo: () -> Void

    /// Animation state
    @State private var isShowing = false

    private var tc: ThemeColors { SettingsManager.shared.activeColors }

    // MARK: - Body

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            // Message text
            Text(message)
                .font(AppFont.regular(16))
                .foregroundColor(tc.textPrimary)
                .lineLimit(1)

            Spacer()

            // Undo button
            Button(action: onUndo) {
                Text("Undo")
                    .font(AppFont.bold(16))
                    .foregroundColor(tc.primary)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.vertical, DesignSystem.Spacing.md)
        // D8: token surface — Erewhon ignores borderColor and uses its hairline; pixel
        // uses this primary-tint border. Fill/text follow the active scheme.
        .adaptiveCard(borderColor: tc.primary.opacity(0.3), fillColor: tc.cardBackground)
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .offset(y: isShowing ? 0 : 100)
        .opacity(isShowing ? 1 : 0)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isShowing)
        .onAppear {
            withAnimation {
                isShowing = true
            }
        }
    }
}

// MARK: - Preview

#Preview("Undo Toast") {
    ZStack {
        DesignSystem.Colors.primaryBackground
            .ignoresSafeArea()

        VStack {
            Spacer()

            UndoToast(
                message: "Grilled Chicken Salad deleted",
                onUndo: {
                    print("Undo tapped")
                }
            )
            .padding(.bottom, 100) // Simulate tab bar spacing
        }
    }
}
