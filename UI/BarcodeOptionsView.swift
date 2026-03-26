//
//  BarcodeOptionsView.swift
//  HealthBar
//
//  Created by Claude on 3/27/26.
//

import SwiftUI

/// Sub-screen shown after tapping "Scan Barcode" in AddFoodChoiceSheet.
/// Pushed via NavigationLink inside AddFoodChoiceSheet's NavigationStack.
///
/// Offers two barcode entry paths:
/// - Scan with Camera → BarcodeScannerView
/// - Enter Manually → text alert input
///
/// On success: dismisses the entire sheet chain and opens AddFoodFormView
/// with barcode-filled fields and the pre-selected meal type.
struct BarcodeOptionsView: View {

    @Bindable var viewModel: FoodLogViewModel

    /// Closure that dismisses the entire AddFoodChoiceSheet (and this navigation stack)
    let onDismissAll: () -> Void

    @State private var showingCamera = false
    @State private var showingManualAlert = false
    @State private var manualInput = ""

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            // Scan with Camera
            optionRow(
                sfSymbol: "camera.viewfinder",
                title: "Scan with Camera",
                subtitle: "Point camera at product barcode"
            ) {
                showingCamera = true
            }

            // Enter Manually
            optionRow(
                sfSymbol: "keyboard",
                title: "Enter Manually",
                subtitle: "Type in the barcode number"
            ) {
                showingManualAlert = true
            }

            Spacer()
        }
        .padding(DesignSystem.Spacing.lg)
        .background(DesignSystem.Colors.primaryBackground.ignoresSafeArea())
        .navigationTitle("Scan Barcode")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingCamera) {
            BarcodeScannerView { barcode in
                Task {
                    await viewModel.handleBarcodeScanned(barcode)
                    onDismissAll()
                    viewModel.openAddFoodFormAfterDelay()
                }
            }
        }
        .alert("Enter Barcode", isPresented: $showingManualAlert) {
            TextField("Barcode number", text: $manualInput)
                .keyboardType(.numberPad)
            Button("Search") {
                Task {
                    let barcode = manualInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !barcode.isEmpty else { return }
                    await viewModel.handleBarcodeScanned(barcode)
                    onDismissAll()
                    viewModel.openAddFoodFormAfterDelay()
                    manualInput = ""
                }
            }
            Button("Cancel", role: .cancel) {
                manualInput = ""
            }
        } message: {
            Text("Enter the UPC or EAN barcode number from the product label.")
        }
    }

    private func optionRow(
        sfSymbol: String,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: DesignSystem.Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                        .fill(DesignSystem.Colors.primary.opacity(0.12))
                        .frame(width: 52, height: 52)
                    Image(systemName: sfSymbol)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.primary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: DesignSystem.FontSizes.headline, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    Text(subtitle)
                        .font(.system(size: DesignSystem.FontSizes.footnote, weight: .regular))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textTertiary)
            }
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
            .shadow(
                color: DesignSystem.Shadows.card.color,
                radius: DesignSystem.Shadows.card.radius / 2,
                x: DesignSystem.Shadows.card.x,
                y: DesignSystem.Shadows.card.y
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
