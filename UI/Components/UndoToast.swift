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
/// - Dark background with white text
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

    // MARK: - Body

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            // Message text
            Text(message)
                .font(.system(size: DesignSystem.FontSizes.callout, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)

            Spacer()

            // Undo button
            Button(action: onUndo) {
                Text("Undo")
                    .font(.system(size: DesignSystem.FontSizes.callout, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.primary)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.vertical, DesignSystem.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                .fill(Color(hex: "#1F2937")) // Dark charcoal
                .shadow(color: Color.black.opacity(0.3), radius: 8, y: 4)
        )
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
