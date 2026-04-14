//
//  SignUpView.swift
//  HealthBar
//
//  Created by Vishnu Nathan on 1/19/26.
//
//  Account creation screen.
//  Purely reactive — all logic lives in AuthViewModel.
//

import SwiftUI

// MARK: - SignUpView

/// Account creation screen.
///
/// Shares the same `AuthViewModel` instance as `LoginView` — the ViewModel
/// is injected from ContentView so state (e.g., the email a user typed on
/// the login screen) carries over naturally.
///
/// On successful sign-up the service starts a session, `isLoggedIn` flips true,
/// and ContentView transitions to the main TabView automatically.
///
/// `@FocusState` routes the keyboard: displayName → email → password → confirm password → submit.
struct SignUpView: View {

    // MARK: - Properties

    /// Shared ViewModel (same instance as LoginView).
    @Bindable var viewModel: AuthViewModel

    // MARK: - Focus Routing

    private enum Field: Hashable {
        case displayName
        case email
        case password
        case confirmPassword
    }

    @FocusState private var focusedField: Field?

    // MARK: - Body

    var body: some View {
        ZStack {
            // Full-bleed background
            DesignSystem.Colors.primaryBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: DesignSystem.Spacing.xl) {
                    Spacer().frame(height: DesignSystem.Spacing.xl)

                    headerSection
                    fieldsSection

                    // Auth-level error banner (e.g., email already registered)
                    if let authError = viewModel.authError {
                        authErrorBanner(authError)
                    }

                    actionsSection

                    Spacer().frame(height: DesignSystem.Spacing.xl)
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)
            }
        }
        // Dismiss keyboard when tapping outside any field
        .onTapGesture {
            focusedField = nil
        }
        .navigationTitle("Create Account")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            // App icon mark
            ZStack {
                Circle()
                    .fill(DesignSystem.Colors.primaryGradient)
                    .frame(width: 72, height: 72)

                Image(systemName: "heart.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(.white)
            }
            .shadow(
                color: DesignSystem.Shadows.successPulse.color,
                radius: DesignSystem.Shadows.successPulse.radius,
                x: DesignSystem.Shadows.successPulse.x,
                y: DesignSystem.Shadows.successPulse.y
            )
            .accessibilityHidden(true)

            Text("HealthBar")
                .font(.system(size: DesignSystem.FontSizes.title, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Text("Start your journey today.")
                .font(.system(size: DesignSystem.FontSizes.callout, weight: .regular))
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, DesignSystem.Spacing.sm)
    }

    // MARK: - Fields

    private var fieldsSection: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            // Display Name — first field, return key moves to email
            AuthTextField(
                label: "Display Name",
                placeholder: "How should we call you?",
                text: $viewModel.displayName,
                isSecure: false,
                errorMessage: viewModel.displayNameError,
                submitLabel: .next,
                onSubmit: { focusedField = .email }
            )
            .focused($focusedField, equals: .displayName)

            // Email
            AuthTextField(
                label: "Email",
                placeholder: "you@example.com",
                text: $viewModel.email,
                isSecure: false,
                errorMessage: viewModel.emailError,
                submitLabel: .next,
                onSubmit: { focusedField = .password }
            )
            .focused($focusedField, equals: .email)

            // Password — return key moves to confirm password
            AuthTextField(
                label: "Password",
                placeholder: "At least 8 characters, 1 number",
                text: $viewModel.password,
                isSecure: true,
                errorMessage: viewModel.passwordError,
                submitLabel: .next,
                onSubmit: { focusedField = .confirmPassword }
            )
            .focused($focusedField, equals: .password)

            // Confirm password — return key submits
            AuthTextField(
                label: "Confirm Password",
                placeholder: "Re-enter your password",
                text: $viewModel.confirmPassword,
                isSecure: true,
                errorMessage: viewModel.confirmPasswordError,
                submitLabel: .go,
                onSubmit: {
                    focusedField = nil
                    Task { await viewModel.signUp() }
                }
            )
            .focused($focusedField, equals: .confirmPassword)
        }
    }

    // MARK: - Auth Error Banner

    /// Shown for backend-level failures (e.g., email already registered).
    private func authErrorBanner(_ message: String) -> some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 18, weight: .regular))
                .foregroundColor(DesignSystem.Colors.danger)

            Text(message)
                .font(.system(size: DesignSystem.FontSizes.footnote, weight: .regular))
                .foregroundColor(DesignSystem.Colors.danger)
                .multilineTextAlignment(.leading)

            Spacer()
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.danger.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                .stroke(DesignSystem.Colors.danger.opacity(0.3), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message)")
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            // Create Account button
            AppButton(
                title: "Create Account",
                style: .primary,
                action: {
                    focusedField = nil
                    Task { await viewModel.signUp() }
                },
                isLoading: viewModel.isLoading,
                isDisabled: !viewModel.isSignUpSubmittable
            )
            .accessibilityLabel(viewModel.isLoading ? "Creating account" : "Create Account")
            .accessibilityHint("Double-tap to create your HealthBar account")

            // The NavigationStack back button (top-left) is the primary mechanism
            // to return to LoginView. We surface a visible text hint below.
            HStack(spacing: DesignSystem.Spacing.xs) {
                Text("Already have an account?")
                    .font(.system(size: DesignSystem.FontSizes.callout, weight: .regular))
                    .foregroundColor(DesignSystem.Colors.textSecondary)

                Text("Log In")
                    .font(.system(size: DesignSystem.FontSizes.callout, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.primary)
            }
            .frame(minHeight: 44)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Already have an account? Use the back button to return to Log In")
        }
    }
}

// MARK: - Preview

#Preview("Sign Up View") {
    NavigationStack {
        SignUpView(viewModel: AuthViewModel(authService: LocalAuthService.shared))
    }
}
