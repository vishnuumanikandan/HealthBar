//
//  XPToast.swift
//  HealthBar
//
//  Created by Claude on 1/26/26.
//

import SwiftUI

/// Toast component for displaying XP earned from quest completion
///
/// Features:
/// - Gold/amber badge with XP amount
/// - Slides in with spring animation
/// - Auto-dismisses after 1.5-2 seconds
/// - CRITICAL: .allowsHitTesting(false) so it doesn't block user taps
/// - Position: Upper half of screen (never overlaps undo toast at bottom)
/// - Supports aggregated XP display for multiple quests
struct XPToast: View {

    // MARK: - Properties

    /// Amount of XP earned
    let xp: Int

    /// Number of quests that contributed (for aggregation)
    let questCount: Int

    /// Callback when toast should be dismissed
    let onDismiss: () -> Void

    /// Animation state
    @State private var isShowing = false

    // MARK: - Initialization

    init(xp: Int, questCount: Int = 1, onDismiss: @escaping () -> Void = {}) {
        self.xp = xp
        self.questCount = questCount
        self.onDismiss = onDismiss
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "star.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.yellow)

            Text(displayText)
                .font(.system(size: DesignSystem.FontSizes.headline, weight: .bold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.vertical, DesignSystem.Spacing.md)
        .background(
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color.orange, Color(hex: "#F59E0B")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .shadow(color: Color.orange.opacity(0.4), radius: 8, y: 4)
        .scaleEffect(isShowing ? 1.0 : 0.5)
        .opacity(isShowing ? 1.0 : 0.0)
        .allowsHitTesting(false) // CRITICAL: Don't block user taps
        .onAppear {
            // Animate in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isShowing = true
            }

            // Auto-dismiss after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeOut(duration: 0.3)) {
                    isShowing = false
                }

                // Call onDismiss after animation completes
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    onDismiss()
                }
            }
        }
    }

    // MARK: - Computed Properties

    /// Display text for the toast
    private var displayText: String {
        if questCount > 1 {
            return "+\(xp) XP from \(questCount) quests!"
        } else {
            return "+\(xp) XP"
        }
    }
}

// MARK: - Confetti Particles (Optional Enhancement)

/// Simple particle view for celebratory effect
struct ConfettiParticle: View {

    let color: Color
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .scaleEffect(isAnimating ? 0 : 1)
            .opacity(isAnimating ? 0 : 1)
            .offset(
                x: CGFloat.random(in: -50...50),
                y: isAnimating ? CGFloat.random(in: -100...(-50)) : 0
            )
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeOut(duration: 0.8)) {
                    isAnimating = true
                }
            }
    }
}

/// Container for confetti particle burst effect
struct ConfettiBurst: View {

    let particleCount: Int

    var body: some View {
        ZStack {
            ForEach(0..<particleCount, id: \.self) { index in
                ConfettiParticle(
                    color: [
                        DesignSystem.Colors.primary,
                        DesignSystem.Colors.energy,
                        Color.yellow,
                        Color.orange
                    ].randomElement()!
                )
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - XP Toast Container (for managing multiple quests)

/// Container view that handles XP toast display with aggregation
struct XPToastContainer: View {

    /// Total XP to display
    let totalXP: Int

    /// Number of quests that completed
    let questCount: Int

    /// Whether to show the toast
    @Binding var isShowing: Bool

    /// Show confetti effect
    var showConfetti: Bool = true

    var body: some View {
        VStack {
            if isShowing {
                ZStack {
                    // Confetti effect (optional)
                    if showConfetti && questCount > 0 {
                        ConfettiBurst(particleCount: 8)
                    }

                    XPToast(
                        xp: totalXP,
                        questCount: questCount,
                        onDismiss: {
                            isShowing = false
                        }
                    )
                }
                .transition(.scale.combined(with: .opacity))
            }

            Spacer()
        }
        .padding(.top, 60) // Position in upper half
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isShowing)
    }
}

// MARK: - Quest Rollback Toast

/// Toast for when a quest becomes incomplete after meal deletion
struct QuestRollbackToast: View {

    let questTitle: String
    @State private var isShowing = false

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)

            Text("\(questTitle) no longer met")
                .font(.system(size: DesignSystem.FontSizes.footnote, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .background(
            Capsule()
                .fill(DesignSystem.Colors.textSecondary)
        )
        .opacity(isShowing ? 1 : 0)
        .offset(y: isShowing ? 0 : -20)
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.spring(response: 0.3)) {
                isShowing = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeOut(duration: 0.3)) {
                    isShowing = false
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("XP Toast - Single Quest") {
    ZStack {
        DesignSystem.Colors.primaryBackground
            .ignoresSafeArea()

        VStack {
            XPToast(xp: 40, questCount: 1)
                .padding(.top, 60)

            Spacer()
        }
    }
}

#Preview("XP Toast - Multiple Quests") {
    ZStack {
        DesignSystem.Colors.primaryBackground
            .ignoresSafeArea()

        VStack {
            XPToast(xp: 70, questCount: 2)
                .padding(.top, 60)

            Spacer()
        }
    }
}

#Preview("XP Toast Container") {
    @Previewable @State var isShowing = true

    return ZStack {
        DesignSystem.Colors.primaryBackground
            .ignoresSafeArea()

        XPToastContainer(totalXP: 130, questCount: 3, isShowing: $isShowing)

        Button("Toggle") {
            isShowing.toggle()
        }
    }
}
