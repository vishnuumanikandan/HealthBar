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

    @Environment(\.dismiss) private var dismiss

    @State private var showLogin = false

    @State private var settings = SettingsManager.shared
    private var tc: ThemeColors { settings.activeColors }

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
            tc.primaryBackground
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
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Create Account")
                    .font(AppFont.bold(20))
                    .foregroundColor(tc.textPrimary)
            }
        }
        .navigationDestination(isPresented: $showLogin) {
            // WELCOMEROOT-1: alternatives hidden here — inside the guest sheet the guest
            // button is circular and the Sign Up link points back at this screen. Preserves
            // today's behavior, which the retired `!showNavBar` gate produced implicitly.
            LoginView(viewModel: viewModel, showNavBar: true, showsAlternatives: false)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 0) {
            // Eyebrow
            Text("START YOUR QUEST")
                .font(AppFont.display(14))
                .tracking(3)
                .foregroundColor(tc.primary)

            // Wordmark — the display face carries its own leading, so the gap above is tight.
            Text("OVERHEAL")
                .font(AppFont.display(32))
                .foregroundColor(tc.textPrimary)
                .padding(.top, DesignSystem.Spacing.xs)
                .accessibilityAddTraits(.isHeader)

            Text("Start your journey today.")
                .font(AppFont.regular(16))
                .foregroundColor(tc.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, DesignSystem.Spacing.sm)
        }
        // Absorbs the vertical space the retired icon mark occupied.
        .padding(.top, DesignSystem.Spacing.md)
        .padding(.bottom, DesignSystem.Spacing.md)
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
                isEmailField: true,
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
                .font(AppFont.regular(14))
                .foregroundColor(DesignSystem.Colors.danger)
                .multilineTextAlignment(.leading)

            Spacer()
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.danger.opacity(0.1))
        .clipShape(AdaptiveCardShapeStyle())
        .overlay(
            AdaptiveCardShapeStyle()
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
            .accessibilityHint("Double-tap to create your Overheal account")

            Button {
                showLogin = true
            } label: {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Text("Already have an account?")
                        .font(AppFont.regular(16))
                        .foregroundColor(tc.textSecondary)

                    Text("Log In")
                        .font(AppFont.bold(16))
                        .foregroundColor(tc.primary)
                }
            }
            .frame(minHeight: 44)
            .accessibilityLabel("Already have an account? Log In")
            .accessibilityHint("Double-tap to return to the login screen")
        }
    }
}

// MARK: - Preview

#Preview("Sign Up View") {
    NavigationStack {
        SignUpView(viewModel: AuthViewModel(authService: LocalAuthService.shared))
    }
}
