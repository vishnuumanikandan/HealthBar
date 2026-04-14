//
//  LoginView.swift
//  HealthBar
//
//  Created by Vishnu Nathan on 1/19/26.
//
//  Authentication entry screen.
//  Purely reactive — all logic lives in AuthViewModel.
//

import SwiftUI

// MARK: - AuthDestination

/// Navigation destinations used in the auth flow NavigationStack.
/// Defined here since LoginView is the root of the auth navigation stack.
enum AuthDestination: Hashable {
    case signUp
}

// MARK: - LoginView

/// The authentication entry screen.
///
/// Displays the HealthBar logo, email/password fields, and a "Log In" button.
/// On success, `authService.isLoggedIn` flips true and ContentView transitions
/// to the main TabView automatically — no imperative navigation needed here.
///
/// Uses `@Bindable` to create two-way bindings to `AuthViewModel`'s properties.
/// `@FocusState` routes keyboard focus: email → password → submit.
struct LoginView: View {

    // MARK: - Properties

    /// Shared ViewModel driving this screen and SignUpView.
    @Bindable var viewModel: AuthViewModel

    // MARK: - Focus Routing

    private enum Field: Hashable {
        case email
        case password
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
                    Spacer().frame(height: DesignSystem.Spacing.xxl)

                    headerSection
                    fieldsSection

                    // Auth-level error banner (wrong password, account not found, etc.)
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
        .navigationBarHidden(true)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            // App icon mark
            ZStack {
                Circle()
                    .fill(DesignSystem.Colors.primaryGradient)
                    .frame(width: 84, height: 84)

                Image(systemName: "heart.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundColor(.white)
            }
            .shadow(
                color: DesignSystem.Shadows.successPulse.color,
                radius: DesignSystem.Shadows.successPulse.radius,
                x: DesignSystem.Shadows.successPulse.x,
                y: DesignSystem.Shadows.successPulse.y
            )
            .accessibilityHidden(true)

            // App name
            Text("HealthBar")
                .font(.system(size: DesignSystem.FontSizes.largeTitle, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)

            // Tagline
            Text("Your health quest begins here.")
                .font(.system(size: DesignSystem.FontSizes.callout, weight: .regular))
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, DesignSystem.Spacing.sm)
    }

    // MARK: - Fields

    private var fieldsSection: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
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

            // Password — return key submits the form
            AuthTextField(
                label: "Password",
                placeholder: "Enter your password",
                text: $viewModel.password,
                isSecure: true,
                errorMessage: viewModel.passwordError,
                submitLabel: .go,
                onSubmit: {
                    focusedField = nil
                    Task { await viewModel.login() }
                }
            )
            .focused($focusedField, equals: .password)
        }
    }

    // MARK: - Auth Error Banner

    /// Shown for backend-level failures (wrong password, account not found).
    /// Separate from field-level inline errors.
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
            // Log In button
            AppButton(
                title: "Log In",
                style: .primary,
                action: {
                    focusedField = nil
                    Task { await viewModel.login() }
                },
                isLoading: viewModel.isLoading,
                isDisabled: !viewModel.isLoginSubmittable
            )
            .accessibilityLabel(viewModel.isLoading ? "Logging in" : "Log In")
            .accessibilityHint("Double-tap to log into your HealthBar account")

            // Navigate to SignUpView
            NavigationLink(value: AuthDestination.signUp) {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Text("Don't have an account?")
                        .font(.system(size: DesignSystem.FontSizes.callout, weight: .regular))
                        .foregroundColor(DesignSystem.Colors.textSecondary)

                    Text("Sign Up")
                        .font(.system(size: DesignSystem.FontSizes.callout, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.primary)
                }
            }
            .frame(minHeight: 44) // Minimum tap target
            .accessibilityLabel("Don't have an account? Sign Up")
            .accessibilityHint("Double-tap to create a new HealthBar account")

            // Divider
            HStack(spacing: DesignSystem.Spacing.sm) {
                Rectangle()
                    .frame(height: 1)
                    .foregroundStyle(DesignSystem.Colors.textSecondary.opacity(0.25))
                Text("or")
                    .font(.system(size: DesignSystem.FontSizes.caption, weight: .regular))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                Rectangle()
                    .frame(height: 1)
                    .foregroundStyle(DesignSystem.Colors.textSecondary.opacity(0.25))
            }
            .padding(.horizontal, DesignSystem.Spacing.md)

            // Continue as Guest — full access, local data only, no account required
            Button {
                focusedField = nil
                Task { await viewModel.continueAsGuest() }
            } label: {
                Text("Continue as Guest")
                    .font(.system(size: DesignSystem.FontSizes.callout, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .frame(minHeight: 44)
            }
            .disabled(viewModel.isLoading)
            .accessibilityLabel("Continue as Guest")
            .accessibilityHint("Double-tap to use HealthBar without an account. Data is stored locally only.")
        }
    }
}

// MARK: - Preview

#Preview("Login View") {
    NavigationStack {
        LoginView(viewModel: AuthViewModel(authService: LocalAuthService.shared))
    }
}
