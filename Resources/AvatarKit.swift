//
//  AvatarKit.swift
//  HealthBar
//
//  Created by Claude on 7/21/26.
//
//  D3a — Preset Avatars: Core. Three tightly-coupled types behind one wire
//  contract (an icon id + a color id, both `String`):
//    • AvatarCatalog     — a STATIC namespace: compile-time id tables + lookup.
//    • AvatarView         — the ONE avatar renderer everywhere; a PURE renderer.
//    • AvatarPickerSheet  — the picker (one component, two presenters).
//
//  Ids are the permanent contract (D-ART swaps custom emblems / D3c grows the
//  set behind the SAME ids); hex/gradient definitions NEVER enter Firestore.
//  An unknown id at render time (future set, tampered data) falls back to
//  initials silently — which is exactly why the rules validate type/size only,
//  never membership: the catalog can grow with no rules change.
//

import SwiftUI

// MARK: - Catalog

/// The single source of truth for avatar ids. A STATIC NAMESPACE ONLY — no
/// singleton, no ObservableObject, no protocol, no runtime mutation (never an
/// `AvatarManager.shared`). Lookups return nil for an unknown id.
///
/// The id tables + `symbol(for:)` are the pure contract locked by a standalone
/// TDD spec (`AvatarCatalogSpec`); the SwiftUI paint half is verified by
/// compilation + screenshots.
enum AvatarCatalog {

    /// D2 — Default is sword + verdant.
    static let defaultIcon = "sword"
    static let defaultColor = "verdant"

    /// D2 — the 10 locked icon ids, in picker display order. Ids are the permanent
    /// wire contract; the SF Symbol mapping below is a placeholder swap.
    static let iconIds = ["sword", "shield", "rook", "fleur", "spark", "moon", "sun", "gem", "bolt", "leaf"]

    /// D2 — the 9 locked color ids, in picker display order (6 solids + 3 gradients).
    static let colorIds = ["verdant", "sky", "violet", "ember", "rose", "gold", "aurora", "dusk", "sunfire"]

    /// id -> closest real SF Symbol. Placeholder emblems (D-ART swaps custom art
    /// behind the same ids). Unknown id -> nil ⇒ initials fallback at render.
    private static let iconSymbols: [String: String] = [
        "sword": "figure.fencing",       // weapon / combat
        "shield": "shield.fill",          // heraldry
        "rook": "building.columns.fill",  // castle / tower
        "fleur": "seal.fill",             // heraldic emblem
        "spark": "sparkles",              // arcane
        "moon": "moon.stars.fill",        // celestial
        "sun": "sun.max.fill",            // celestial
        "gem": "diamond.fill",            // treasure
        "bolt": "bolt.fill",              // power
        "leaf": "leaf.fill",              // nature
    ]

    /// id -> local paint (solid Color or LinearGradient). A gradient is just
    /// another id — nothing special on the wire. Unknown id -> nil ⇒ initials
    /// fallback at render.
    private static let paints: [String: AvatarPaint] = [
        "verdant": AvatarPaint(AvatarInk.verdant),
        "sky":     AvatarPaint(AvatarInk.sky),
        "violet":  AvatarPaint(AvatarInk.violet),
        "ember":   AvatarPaint(AvatarInk.ember),
        "rose":    AvatarPaint(AvatarInk.rose),
        "gold":    AvatarPaint(AvatarInk.gold),
        "aurora":  AvatarPaint(AvatarInk.aurora),
        "dusk":    AvatarPaint(AvatarInk.dusk),
        "sunfire": AvatarPaint(AvatarInk.sunfire),
    ]

    /// Resolves an icon id to its SF Symbol name, or nil for an unknown id.
    static func symbol(for iconId: String) -> String? { iconSymbols[iconId] }

    /// Resolves a color id to its paint, or nil for an unknown id.
    static func paint(for colorId: String) -> AvatarPaint? { paints[colorId] }
}

/// A resolved avatar fill — a solid Color or a LinearGradient, type-erased so
/// both live in one table and one `.fill(_:)`. Artwork, not theme taxonomy
/// (the RankPlaque `Ink` precedent): a curated identity palette that reads the
/// same in both UI families and is deliberately NOT a reskinnable DesignSystem
/// token — the app-wide reskin does not repaint chosen avatars.
struct AvatarPaint {
    let fill: AnyShapeStyle
    init<S: ShapeStyle>(_ fill: S) { self.fill = AnyShapeStyle(fill) }
}

/// Avatar palette artwork values (hex literals, like RankPlaque's `Ink`). Deep
/// enough that the white glyph reads on every fill. Private — the wire contract
/// is the id, never these colors.
private enum AvatarInk {
    static let verdant = Color(hex: "#2FA25B")
    static let sky     = Color(hex: "#3A8FDE")
    static let violet  = Color(hex: "#8560D6")
    static let ember   = Color(hex: "#E06438")
    static let rose    = Color(hex: "#E0537E")
    static let gold    = Color(hex: "#C0902F")

    static let aurora  = LinearGradient(colors: [Color(hex: "#2FA25B"), Color(hex: "#2BB8A8"), Color(hex: "#7357D8")],
                                        startPoint: .topLeading, endPoint: .bottomTrailing)
    static let dusk    = LinearGradient(colors: [Color(hex: "#3E52C4"), Color(hex: "#8560D6"), Color(hex: "#DE5A86")],
                                        startPoint: .topLeading, endPoint: .bottomTrailing)
    static let sunfire = LinearGradient(colors: [Color(hex: "#E7B23E"), Color(hex: "#E06438"), Color(hex: "#DA3A5C")],
                                        startPoint: .topLeading, endPoint: .bottomTrailing)
}

// MARK: - Renderer

/// The ONE avatar renderer, everywhere. A PURE renderer: no storage,
/// networking, loading, caching, or lookups beyond `AvatarCatalog`; it never
/// inspects UserProfile, DataManager, or any coordinator. It takes ids, a size,
/// and a `@ViewBuilder fallback`.
///
/// • Valid ids: a rounded-square (`AdaptiveCardShapeStyle`, correct in both UI
///   families) with the color's tinted fill + hairline border + the glyph,
///   everything scaled from `size`.
/// • nil / unknown ids: renders the passed `fallback` verbatim — so each call
///   site's own current initials view is byte-preserved on the nil path.
struct AvatarView<Fallback: View>: View {
    let iconId: String?
    let colorId: String?
    let size: CGFloat
    @ViewBuilder let fallback: () -> Fallback

    init(iconId: String?, colorId: String?, size: CGFloat, @ViewBuilder fallback: @escaping () -> Fallback) {
        self.iconId = iconId
        self.colorId = colorId
        self.size = size
        self.fallback = fallback
    }

    var body: some View {
        if let iconId, let colorId,
           let symbol = AvatarCatalog.symbol(for: iconId),
           let paint = AvatarCatalog.paint(for: colorId) {
            swatch(symbol: symbol, paint: paint)
        } else {
            fallback()
        }
    }

    private func swatch(symbol: String, paint: AvatarPaint) -> some View {
        // Glyph + chrome scale with the container — RankPlaque's `s = size / <viewBox>`
        // convention, on a 72pt reference box.
        let s = size / 72
        let shape = AdaptiveCardShapeStyle(cornerRadius: size * 0.26)
        return ZStack {
            shape.fill(paint.fill)
            shape.stroke(Color.white.opacity(0.22), lineWidth: max(1, 2 * s))
            Image(systemName: symbol)
                .font(.system(size: 34 * s, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Picker

/// The avatar picker: live preview, color grid, icon grid, Save. ONE component,
/// TWO presenters (onboarding + Profile). Holds no persistence of its own — it
/// takes the current selection and an `onSave` the caller routes wherever it
/// needs. `onSave` returning true dismisses; false surfaces an inline retry
/// message and stays open (removeFriend's shape).
struct AvatarPickerSheet: View {

    let onSave: (_ iconId: String, _ colorId: String) async -> Bool

    @State private var selIcon: String
    @State private var selColor: String
    @State private var isSaving = false
    @State private var saveFailed = false
    @Environment(\.dismiss) private var dismiss

    private var tc: ThemeColors { SettingsManager.shared.activeColors }

    init(iconId: String, colorId: String, onSave: @escaping (_ iconId: String, _ colorId: String) async -> Bool) {
        self.onSave = onSave
        self._selIcon = State(initialValue: iconId)
        self._selColor = State(initialValue: colorId)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.lg) {
                    // Live preview (sel ids are always valid catalog ids → the fallback never shows).
                    AvatarView(iconId: selIcon, colorId: selColor, size: 96) { EmptyView() }
                        .padding(.top, DesignSystem.Spacing.md)

                    gridSection("Color", ids: AvatarCatalog.colorIds, isSelected: { $0 == selColor }) { id in
                        selColor = id
                    } cell: { id in
                        colorSwatch(id)
                    }

                    gridSection("Icon", ids: AvatarCatalog.iconIds, isSelected: { $0 == selIcon }) { id in
                        selIcon = id
                    } cell: { id in
                        AvatarView(iconId: id, colorId: selColor, size: 54) { EmptyView() }
                    }

                    if saveFailed {
                        Text("Couldn't save. Try again.")
                            .font(AppFont.regular(13))
                            .foregroundColor(DesignSystem.Colors.danger)
                    }

                    AppButton(title: "Save", style: .primary,
                              action: { Task { await save() } },
                              isLoading: isSaving)
                }
                .padding(DesignSystem.Spacing.lg)
            }
            .background(tc.primaryBackground.ignoresSafeArea())
            .navigationTitle("Your Avatar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(tc.textSecondary)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        saveFailed = false
        let ok = await onSave(selIcon, selColor)
        isSaving = false
        if ok { dismiss() } else { saveFailed = true }
    }

    // MARK: Grid building blocks

    /// A labeled 5-column grid of tappable swatches; the selected id gets a ring.
    @ViewBuilder
    private func gridSection<Cell: View>(
        _ title: String,
        ids: [String],
        isSelected: @escaping (String) -> Bool,
        onTap: @escaping (String) -> Void,
        @ViewBuilder cell: @escaping (String) -> Cell
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text(title)
                .font(AppFont.bold(13))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundColor(tc.textSecondary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
                ForEach(ids, id: \.self) { id in
                    Button { onTap(id) } label: {
                        cell(id)
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(
                                AdaptiveCardShapeStyle(cornerRadius: 13)
                                    .stroke(tc.primary, lineWidth: isSelected(id) ? 3 : 0)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func colorSwatch(_ id: String) -> some View {
        AdaptiveCardShapeStyle(cornerRadius: 13)
            .fill(AvatarCatalog.paint(for: id)?.fill ?? AnyShapeStyle(tc.segBackground))
    }
}
