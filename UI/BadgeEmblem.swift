//
//  BadgeEmblem.swift
//  HealthBar
//
//  Created by Claude on 7/14/26.
//

import SwiftUI

/// The ONE shared badge emblem (D1 §2): custom artwork for each of the six badges,
/// with a full-grayscale + lock-disc treatment for locked badges.
///
/// Every badge emblem in the app renders through this view — never draw one per-file.
/// (Feed rows are the exception: they keep SF Symbols per the D0 ruling.)
///
/// Geometry is traced from `design/erewhon/badge-emblems.html` (a 72×72 viewBox): every
/// coordinate below is that file's, scaled by `s = size / 72`. One private builder per
/// badge, dispatched from a single switch — RankPlaque's per-rank structure is the exemplar.
///
/// Artwork, not chrome: both families (Erewhon + pixel) render it identically (no
/// `isCleanUI` branch), and it is entirely STATIC — no idle animation, no motion of its
/// own. When shown inside an animated container (e.g. the unlock toast's slide/spring)
/// the emblem rides that animation unchanged.
///
/// Colour rules (D1 §2): the `#083ACE` accent slots ride the LIVE `tc.primary` (theme-
/// tracking, same rule as the plaques' accent); `#8F7BE8` → `Erewhon.rankPrismatic`;
/// `#C9A648` → `Erewhon.rankGold`. The navy base and the white/opacity ramps are private
/// `Art` artwork constants — never DesignSystem tokens (the RankPlaque rule).
struct BadgeEmblem: View {

    /// The badge to render. Badges are identified by their `String` id; every call site
    /// already holds the full `BadgeDefinition`, so the value itself is the parameter
    /// (no separate id enum exists).
    let badge: BadgeDefinition
    /// Emblem width & height in points (square).
    let size: CGFloat
    /// Locked badges render full-grayscale under a centered lock disc.
    var isLocked: Bool = false

    init(_ badge: BadgeDefinition, size: CGFloat, isLocked: Bool = false) {
        self.badge = badge
        self.size = size
        self.isLocked = isLocked
    }

    /// View points per viewBox unit (the HTML's 72-unit box).
    private var s: CGFloat { size / 72 }

    /// The live accent — the `#083ACE` slots track the theme. Read inside `body` so
    /// @Observable tracks it.
    private var accent: Color { SettingsManager.shared.activeColors.primary }

    var body: some View {
        emblem
            .frame(width: size, height: size)
            // Full grayscale when locked — drains ALL colour, NO opacity fade (the emblem
            // stays fully visible). `.saturation` runs BEFORE the overlay, so the lock
            // disc is never desaturated. One shared modifier path — no per-emblem variants.
            .saturation(isLocked ? 0 : 1)
            .overlay { if isLocked { lockOverlay } }
            .accessibilityElement()
            .accessibilityLabel(isLocked ? "\(badge.title), locked" : badge.title)
    }

    /// One private builder per badge, dispatched from a single switch (RankPlaque §2 pattern).
    @ViewBuilder
    private var emblem: some View {
        let a = Art(s: s, accent: accent)
        switch badge.id {
        case "first_flame":  firstFlame(a)
        case "week_warrior": weekWarrior(a)
        case "month_legend": monthLegend(a)
        case "century":      century(a)
        case "goal_getter":  goalGetter(a)
        case "level_up":     levelUp(a)
        case "tutorial_complete": tutorialComplete(a)
        default:             fallback(a)   // unknown id (never in practice) — neutral disc
        }
    }

    /// The locked overlay: a dark disc (~36% of the emblem) bearing a white `lock.fill`.
    /// The 36% ratio holds at every size so the disc stays legible in grid cells.
    private var lockOverlay: some View {
        ZStack {
            Circle()
                .fill(Art.lockDisc)
                .frame(width: size * 0.36, height: size * 0.36)
            Image(systemName: "lock.fill")
                .font(.system(size: size * 0.18, weight: .semibold))
                .foregroundStyle(Art.white)
        }
    }
}

// MARK: - Emblems (one builder per badge; coordinates traced from the HTML)

private extension BadgeEmblem {

    // First Flame — shield, accent inner shield, white flame.
    func firstFlame(_ a: Art) -> some View {
        ZStack(alignment: .topLeading) {
            Self.shieldOuter(a).fill(Art.navy)
            Self.shieldInner(a).fill(a.accentColor)
            Self.flame(a).fill(Art.white)
            Self.flameTongue(a).fill(a.accentColor.opacity(0.55))
        }
    }

    // Week Warrior — circle, gold ring, white calendar + gold day-dot.
    func weekWarrior(_ a: Art) -> some View {
        ZStack(alignment: .topLeading) {
            a.circle(36, 36, 25).fill(Art.navy)
            a.circle(36, 36, 21.5).stroke(a.gold, lineWidth: a.w(2.5))
            a.roundedRect(25, 29, 22, 20, 3.2).fill(Art.white)
            a.roundedRect(30, 25, 2.6, 6, 1.3).fill(Art.white)
            a.roundedRect(39.4, 25, 2.6, 6, 1.3).fill(Art.white)
            a.line([(27, 34.5), (45, 34.5)]).stroke(Art.navy, lineWidth: a.w(1.6))
            a.circle(30, 42.5, 1.7).fill(Art.navy.opacity(0.35))
            a.circle(42, 42.5, 1.7).fill(Art.navy.opacity(0.35))
            a.circle(36, 42.5, 3.6).fill(a.gold)
        }
    }

    // Month Legend — hex, prismatic stroke, white bar + prism2-class plates.
    func monthLegend(_ a: Art) -> some View {
        ZStack(alignment: .topLeading) {
            Self.hex(a).fill(Art.navy)
            Self.hex(a).stroke(a.prismatic, lineWidth: a.w(3))
            a.roundedRect(25, 26.5, 22, 4.2, 2).fill(a.prismatic.opacity(0.85))
            a.roundedRect(21, 33, 30, 7, 2.6).fill(Art.white)
            a.roundedRect(25, 42.3, 22, 4.2, 2).fill(a.prismatic.opacity(0.7))
        }
    }

    // Century — circle, gold inner ring, "100" struck center, gold laurels + ribbon notch.
    func century(_ a: Art) -> some View {
        ZStack(alignment: .topLeading) {
            a.circle(36, 36, 25).fill(Art.navy)
            a.circle(36, 36, 21).stroke(a.gold, lineWidth: a.w(2.4))

            // Left laurel — stem + four leaves fanning up the ring.
            Self.laurelLeft(a).stroke(a.gold, lineWidth: a.w(1.4))
            a.ellipse(23.6, 49, 2.9, 1.5, rotate: -48).fill(a.gold)
            a.ellipse(21, 44.5, 2.9, 1.5, rotate: -62).fill(a.gold)
            a.ellipse(19.4, 39.6, 2.8, 1.4, rotate: -76).fill(a.gold)
            a.ellipse(19, 34.6, 2.6, 1.4, rotate: -88).fill(a.gold)
            // Right laurel — mirror.
            Self.laurelRight(a).stroke(a.gold, lineWidth: a.w(1.4))
            a.ellipse(48.4, 49, 2.9, 1.5, rotate: 48).fill(a.gold)
            a.ellipse(51, 44.5, 2.9, 1.5, rotate: 62).fill(a.gold)
            a.ellipse(52.6, 39.6, 2.8, 1.4, rotate: 76).fill(a.gold)
            a.ellipse(53, 34.6, 2.6, 1.4, rotate: 88).fill(a.gold)

            // Ribbon notch below.
            a.poly([(31, 49), (41, 49), (41, 58), (36, 54.5), (31, 58)]).fill(a.gold)

            // "100" — Bebas via AppFont.display (the app's display face), centered in the
            // ring (emblem center = frame center). Path-drawing the numeral was the
            // alternative; the display font keeps it crisp and consistent with rank UI.
            Text("100")
                .font(AppFont.display(19 * s))
                .foregroundStyle(a.gold)
                .frame(width: size, height: size)
        }
    }

    // Goal Getter — concentric target: navy / accent / navy / white.
    func goalGetter(_ a: Art) -> some View {
        ZStack(alignment: .topLeading) {
            a.circle(36, 36, 25).fill(Art.navy)
            a.circle(36, 36, 18.5).fill(a.accentColor)
            a.circle(36, 36, 12).fill(Art.navy)
            a.circle(36, 36, 5.5).fill(Art.white)
        }
    }

    // Level Up — shield, inset accent outline, three ascending chevrons, gold burst crest.
    func levelUp(_ a: Art) -> some View {
        let ray = StrokeStyle(lineWidth: a.w(1.5), lineCap: .round)
        return ZStack(alignment: .topLeading) {
            Self.shieldOuter(a).fill(Art.navy)
            Self.shieldInner(a).stroke(a.accentColor, lineWidth: a.w(2.5))
            a.poly([(28, 48), (36, 42), (44, 48), (44, 45), (36, 39), (28, 45)]).fill(Art.white.opacity(0.35))
            a.poly([(28, 43), (36, 37), (44, 43), (44, 40), (36, 34), (28, 40)]).fill(Art.white.opacity(0.65))
            a.poly([(28, 38), (36, 32), (44, 38), (44, 35), (36, 29), (28, 35)]).fill(Art.white)
            a.circle(36, 24.5, 2.6).fill(a.gold)
            a.line([(36, 18.5), (36, 20.5)]).stroke(a.gold, style: ray)
            a.line([(41.5, 20), (40.2, 21.6)]).stroke(a.gold, style: ray)
            a.line([(43, 24.5), (41, 24.5)]).stroke(a.gold, style: ray)
            a.line([(30.5, 20), (31.8, 21.6)]).stroke(a.gold, style: ray)
            a.line([(29, 24.5), (31, 24.5)]).stroke(a.gold, style: ray)
        }
    }

    // Tutorial Complete — the tutorial spark: navy disc, accent spark-ring, white bolt.
    // Traced to the welcome popup greeting page's Circle-stroke spark ring (TutorialKit),
    // remapped into the 72-box: a concentric accent ring with a lightning bolt struck
    // through center. Reuses `a.circle` for the rings; `bolt` is the only new geometry.
    func tutorialComplete(_ a: Art) -> some View {
        ZStack(alignment: .topLeading) {
            a.circle(36, 36, 25).fill(Art.navy)
            a.circle(36, 36, 21).stroke(a.accentColor, lineWidth: a.w(2.5))
            Self.bolt(a).fill(Art.white)
        }
    }

    // Defensive neutral emblem for an unrecognized id (never hit — the seven ids are exhaustive).
    func fallback(_ a: Art) -> some View {
        ZStack(alignment: .topLeading) {
            a.circle(36, 36, 25).fill(Art.navy)
            a.circle(36, 36, 8).fill(Art.white)
        }
    }

    // MARK: Shared path builders

    /// The heraldic shield outer, shared by First Flame and Level Up (identical geometry).
    static func shieldOuter(_ a: Art) -> Path {
        var p = Path()
        p.move(to: a.p(15, 14))
        p.addLine(to: a.p(57, 14))
        p.addLine(to: a.p(57, 34))
        a.curve(&p, to: (36, 61), c1: (57, 48), c2: (47, 57))
        a.curve(&p, to: (15, 34), c1: (25, 57), c2: (15, 48))
        p.closeSubpath()
        return p
    }

    /// The shield inner face — filled (First Flame) or stroked (Level Up).
    static func shieldInner(_ a: Art) -> Path {
        var p = Path()
        p.move(to: a.p(20, 18.5))
        p.addLine(to: a.p(52, 18.5))
        p.addLine(to: a.p(52, 34))
        a.curve(&p, to: (36, 56), c1: (52, 45.5), c2: (44, 52.5))
        a.curve(&p, to: (20, 34), c1: (28, 52.5), c2: (20, 45.5))
        p.closeSubpath()
        return p
    }

    static func flame(_ a: Art) -> Path {
        var p = Path()
        p.move(to: a.p(36, 26))
        a.curve(&p, to: (42, 44), c1: (42, 34), c2: (44, 39))
        a.curve(&p, to: (36, 52), c1: (40.5, 48), c2: (38.5, 50.5))
        a.curve(&p, to: (30, 44), c1: (33.5, 50.5), c2: (31.5, 48))
        a.curve(&p, to: (36, 26), c1: (28, 39), c2: (30, 34))
        p.closeSubpath()
        return p
    }

    static func flameTongue(_ a: Art) -> Path {
        var p = Path()
        p.move(to: a.p(36, 37))
        a.curve(&p, to: (37.2, 45), c1: (38, 40), c2: (38.4, 42.6))
        a.curve(&p, to: (36, 46.8), c1: (36.7, 46), c2: (36, 46.8))
        a.curve(&p, to: (34.4, 43.4), c1: (35, 46), c2: (34.4, 45))
        a.curve(&p, to: (36, 37), c1: (34.4, 41.4), c2: (35.2, 39.6))
        p.closeSubpath()
        return p
    }

    /// The pointy-top hexagon medallion (Month Legend).
    static func hex(_ a: Art) -> Path {
        a.poly([(36, 10), (58, 23), (58, 49), (36, 62), (14, 49), (14, 23)])
    }

    static func laurelLeft(_ a: Art) -> Path {
        var p = Path()
        p.move(to: a.p(25, 51))
        a.curve(&p, to: (19, 33), c1: (20, 46), c2: (18, 40))
        return p
    }

    static func laurelRight(_ a: Art) -> Path {
        var p = Path()
        p.move(to: a.p(47, 51))
        a.curve(&p, to: (53, 33), c1: (52, 46), c2: (54, 40))
        return p
    }

    /// The tutorial spark's lightning bolt (Tutorial Complete), a simple 6-vertex zigzag
    /// centered in the ring — top at (41,22), bottom tip at (31,50).
    static func bolt(_ a: Art) -> Path {
        a.poly([(41, 22), (29, 40), (35.5, 40), (31, 50), (43, 32), (36.5, 32)])
    }
}

// MARK: - Art (the emblem drawing space + artwork literals)

/// The emblem drawing space — the HTML's 72×72 viewBox mapped straight to view points
/// (no sub-transform; emblems fill the box). Every path is written in the HTML's own
/// numbers and mapped through here, so a coordinate can be diffed against the ground
/// truth by eye. Mirrors RankPlaque's `Em`.
private struct Art {
    let s: CGFloat
    /// The live accent (`tc.primary`) — the `#083ACE` slots.
    let accent: Color

    // MARK: Artwork literals (NOT DesignSystem tokens — the RankPlaque rule)
    static let navy = Color(hex: "#0E1B4D")
    static let white = Color.white
    static let lockDisc = Color.black.opacity(0.82)

    // MARK: Mapped-token slots
    var accentColor: Color { accent }
    var prismatic: Color { DesignSystem.Erewhon.rankPrismatic }
    var gold: Color { DesignSystem.Erewhon.rankGold }

    // MARK: Coordinate + width mapping
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
    func w(_ width: CGFloat) -> CGFloat { width * s }

    func poly(_ pts: [(CGFloat, CGFloat)]) -> Path {
        var path = Path()
        guard let f = pts.first else { return path }
        path.move(to: p(f.0, f.1))
        for pt in pts.dropFirst() { path.addLine(to: p(pt.0, pt.1)) }
        path.closeSubpath()
        return path
    }

    func line(_ pts: [(CGFloat, CGFloat)]) -> Path {
        var path = Path()
        guard let f = pts.first else { return path }
        path.move(to: p(f.0, f.1))
        for pt in pts.dropFirst() { path.addLine(to: p(pt.0, pt.1)) }
        return path
    }

    func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> Path {
        let c = p(cx, cy)
        let rr = r * s
        return Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2))
    }

    func roundedRect(_ x: CGFloat, _ y: CGFloat, _ ww: CGFloat, _ hh: CGFloat, _ r: CGFloat) -> Path {
        Path(roundedRect: CGRect(x: x * s, y: y * s, width: ww * s, height: hh * s), cornerRadius: r * s)
    }

    /// An ellipse of half-axes (rx, ry) at (cx, cy), rotated `deg` degrees about its own
    /// center — the laurel leaves.
    func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat, rotate deg: CGFloat) -> Path {
        let c = p(cx, cy)
        let base = Path(ellipseIn: CGRect(x: c.x - rx * s, y: c.y - ry * s, width: rx * 2 * s, height: ry * 2 * s))
        let t = CGAffineTransform(translationX: c.x, y: c.y)
            .rotated(by: deg * .pi / 180)
            .translatedBy(x: -c.x, y: -c.y)
        return base.applying(t)
    }

    /// Cubic bezier segment appended in emblem space.
    func curve(_ path: inout Path, to end: (CGFloat, CGFloat),
               c1: (CGFloat, CGFloat), c2: (CGFloat, CGFloat)) {
        path.addCurve(to: p(end.0, end.1), control1: p(c1.0, c1.1), control2: p(c2.0, c2.1))
    }
}

// MARK: - Preview (all seven × unlocked + locked — the component's regression surface; keep it)

#Preview("Badge emblems") {
    ScrollView {
        VStack(spacing: 22) {
            ForEach(BadgeDefinition.all) { badge in
                HStack(spacing: 20) {
                    VStack(spacing: 5) {
                        BadgeEmblem(badge, size: 72)
                        Text("unlocked").font(AppFont.regular(10))
                            .foregroundColor(SettingsManager.shared.activeColors.textTertiary)
                    }
                    VStack(spacing: 5) {
                        BadgeEmblem(badge, size: 72, isLocked: true)
                        Text("locked").font(AppFont.regular(10))
                            .foregroundColor(SettingsManager.shared.activeColors.textTertiary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(badge.title)
                            .font(AppFont.bold(16))
                            .foregroundColor(SettingsManager.shared.activeColors.textPrimary)
                        Text(badge.description)
                            .font(AppFont.regular(11))
                            .foregroundColor(SettingsManager.shared.activeColors.textSecondary)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Grid-size sanity strip — verifies nothing renders sub-hairline at cell scale.
            HStack(spacing: 14) {
                ForEach(BadgeDefinition.all) { badge in
                    BadgeEmblem(badge, size: 34)
                }
            }
            .padding(.top, 6)
        }
        .padding(24)
    }
    .background(SettingsManager.shared.activeColors.primaryBackground)
}
