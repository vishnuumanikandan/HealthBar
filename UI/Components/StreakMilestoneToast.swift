//
//  StreakMilestoneToast.swift
//  HealthBar
//
//  Created by Claude on 2/2/26.
//

import SwiftUI

/// Special celebration toast for streak milestones (7/30/100 days)
///
/// Features:
/// - Gold/amber gradient background
/// - Large animated flame icon
/// - Title and message
/// - Bonus XP badge
/// - Auto-dismisses after 4 seconds
struct StreakMilestoneToast: View {

    /// The milestone being celebrated
    let milestone: StreakMilestone

    /// Binding to control visibility
    @Binding var isShowing: Bool

    /// Animation state for flame icon
    @State private var flameScale: CGFloat = 0.5
    @State private var flameOpacity: Double = 0

    /// Animation state for content
    @State private var contentOffset: CGFloat = 20
    @State private var contentOpacity: Double = 0

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            // Animated flame icon
            Image(systemName: "flame.fill")
                .font(.system(size: 64, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(hex: "#F59E0B"), Color(hex: "#FBBF24")],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .scaleEffect(flameScale)
                .opacity(flameOpacity)

            // Title
            Text(milestone.title)
                .font(.system(size: DesignSystem.FontSizes.title, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .offset(y: contentOffset)
                .opacity(contentOpacity)

            // Message
            Text(milestone.message)
                .font(.system(size: DesignSystem.FontSizes.callout, weight: .regular))
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .offset(y: contentOffset)
                .opacity(contentOpacity)

            // XP Badge
            HStack(spacing: DesignSystem.Spacing.xs) {
                Image(systemName: "star.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)

                Text("+\(milestone.bonusXP) XP")
                    .font(.system(size: DesignSystem.FontSizes.headline, weight: .bold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.vertical, DesignSystem.Spacing.md)
            .background(
                LinearGradient(
                    colors: [Color(hex: "#F59E0B"), Color(hex: "#D97706")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(Capsule())
            .shadow(color: Color(hex: "#F59E0B").opacity(0.4), radius: 8, y: 4)
            .offset(y: contentOffset)
            .opacity(contentOpacity)
        }
        .padding(DesignSystem.Spacing.xl)
        .frame(maxWidth: 320)
        .background(DesignSystem.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xl)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color(hex: "#F59E0B").opacity(0.5), Color(hex: "#FBBF24").opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
        )
        .shadow(color: Color(hex: "#F59E0B").opacity(0.3), radius: 20)
        .allowsHitTesting(false)
        .onAppear {
            // Flame animation
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                flameScale = 1.0
                flameOpacity = 1.0
            }

            // Content animation (staggered)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.15)) {
                contentOffset = 0
                contentOpacity = 1.0
            }

            // Haptic feedback
            #if os(iOS)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            #endif

            // Auto-dismiss after 4 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                withAnimation(.easeOut(duration: 0.3)) {
                    isShowing = false
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(milestone.title). \(milestone.message). Bonus \(milestone.bonusXP) XP earned.")
    }
}

/// Container view for displaying the milestone toast with proper positioning
struct StreakMilestoneToastContainer: View {

    let milestone: StreakMilestone
    @Binding var isShowing: Bool

    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    // Allow dismissing by tapping background
                    withAnimation {
                        isShowing = false
                    }
                }

            // Toast centered on screen
            StreakMilestoneToast(milestone: milestone, isShowing: $isShowing)
        }
        .transition(.opacity)
    }
}

// MARK: - Preview

#Preview("Streak Milestones") {
    VStack(spacing: DesignSystem.Spacing.xl) {
        ForEach(StreakMilestone.allCases, id: \.rawValue) { milestone in
            StreakMilestoneToast(milestone: milestone, isShowing: .constant(true))
                .scaleEffect(0.6)
        }
    }
    .padding()
    .background(DesignSystem.Colors.primaryBackground)
}

#Preview("Week Milestone") {
    ZStack {
        DesignSystem.Colors.primaryBackground
            .ignoresSafeArea()

        StreakMilestoneToastContainer(
            milestone: .week,
            isShowing: .constant(true)
        )
    }
}
