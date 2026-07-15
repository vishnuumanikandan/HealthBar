//
//  MoodCheckView.swift
//  HealthBar
//
//  Created by Claude on 2/2/26.
//

import SwiftUI

/// Modal view for daily mood check-in
///
/// Shows at 7pm if:
/// - Daily Mood Check is enabled in Accessibility settings
/// - User hasn't logged mood today
/// - App is active (not in background)
struct MoodCheckView: View {

    /// Binding to control visibility
    @Binding var isPresented: Bool

    /// Callback when mood is selected
    let onMoodSelected: (Mood) -> Void

    /// Animation state
    @State private var titleOpacity: Double = 0
    @State private var buttonsScale: CGFloat = 0.8
    @State private var buttonsOpacity: Double = 0
    @State private var settings = SettingsManager.shared

    private var tc: ThemeColors { settings.activeColors }

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.xl) {
            // Header
            VStack(spacing: DesignSystem.Spacing.sm) {
                Text("How did today feel?")
                    .font(AppFont.bold(28))
                    .foregroundColor(tc.textPrimary)

                Text("Take a moment to reflect on your day")
                    .font(AppFont.regular(16))
                    .foregroundColor(tc.textSecondary)
            }
            .opacity(titleOpacity)
            .multilineTextAlignment(.center)

            // Mood buttons
            HStack(spacing: DesignSystem.Spacing.lg) {
                ForEach(Mood.allCases, id: \.self) { mood in
                    MoodButton(mood: mood) {
                        selectMood(mood)
                    }
                }
            }
            .scaleEffect(buttonsScale)
            .opacity(buttonsOpacity)

            // Skip button
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    isPresented = false
                }
            } label: {
                Text("Skip for today")
                    .font(AppFont.regular(16))
                    .foregroundColor(tc.textSecondary)
            }
            .opacity(buttonsOpacity)
            .accessibilityLabel("Skip mood check for today")
        }
        .padding(DesignSystem.Spacing.xl)
        .padding(.vertical, DesignSystem.Spacing.lg)
        .frame(maxWidth: 360)
        .adaptiveCard(borderColor: tc.primary, fillColor: tc.cardBackground, isSelected: true)  // R6c: preserved implicit-selection (review intent later)
        .onAppear {
            // Animate in
            withAnimation(.easeOut(duration: 0.4)) {
                titleOpacity = 1.0
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.15)) {
                buttonsScale = 1.0
                buttonsOpacity = 1.0
            }
        }
    }

    private func selectMood(_ mood: Mood) {
        // Haptic feedback
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        #endif

        // Call callback and dismiss
        onMoodSelected(mood)

        withAnimation(.easeOut(duration: 0.2)) {
            isPresented = false
        }
    }
}

/// Individual mood selection button
struct MoodButton: View {

    let mood: Mood
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: DesignSystem.Spacing.sm) {
                // Mood icon — fixed square keeps all three tiles the same width the
                // emoji glyphs used to give them (SF Symbols vary in intrinsic width).
                Image(systemName: mood.symbolName)
                    .font(AppFont.regular(48))
                    .foregroundColor(mood.color)
                    .frame(width: 56, height: 56)

                // Label
                Text(mood.displayName)
                    .font(AppFont.regular(14))
                    .foregroundColor(mood.color)
            }
            .padding(DesignSystem.Spacing.md)
            .adaptiveCard(borderColor: mood.color.opacity(0.3), fillColor: mood.color.opacity(isPressed ? 0.2 : 0.1))
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .accessibilityLabel("Select mood: \(mood.displayName)")
        .accessibilityHint(mood.subtitle)
    }
}

/// Container view for displaying mood check with background overlay
struct MoodCheckContainer: View {

    @Binding var isPresented: Bool
    let onMoodSelected: (Mood) -> Void

    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    // Allow dismissing by tapping background
                    withAnimation {
                        isPresented = false
                    }
                }

            // Modal
            MoodCheckView(
                isPresented: $isPresented,
                onMoodSelected: onMoodSelected
            )
        }
        .transition(.opacity)
    }
}

// MARK: - Preview

#Preview("Mood Check") {
    ZStack {
        DesignSystem.Colors.primaryBackground
            .ignoresSafeArea()

        MoodCheckContainer(
            isPresented: .constant(true),
            onMoodSelected: { mood in
                print("Selected: \(mood)")
            }
        )
    }
}
