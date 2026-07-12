//
//  RankPlaque.swift
//  HealthBar
//
//  Created by Claude on 7/12/26.
//

import SwiftUI

/// The ONE shared rank emblem (R7a §2): a hex plaque bearing a per-rank emblem, with
/// glow/shine chrome that escalates by tier group and an AngularGradient sweep on the
/// prismatic top three (Sentinel / Prismatic / Zenith).
///
/// Every rank emblem in the app renders through this view — never draw one per-file.
///
/// Geometry is traced from `design/erewhon/rank-plaques.html` (a 40×44 viewBox): every
/// coordinate below is that file's, scaled by `s = size / 40`. The plaque hexagon is
/// pointy-top; the emblem sits in the HTML's `translate(8.6, 10) scale(0.71)` sub-space.
///
/// Artwork, not chrome: both families render it identically (no `isCleanUI` branch), and
/// it is entirely STATIC — no idle animation on any plaque, including Zenith. Motion
/// belongs to the rank-up celebration.
///
/// The glow rings intentionally bleed a few points outside the declared frame (that is
/// what a glow does) — do not `.clipped()` a plaque.
struct RankPlaque: View {

    let rank: Rank
    /// Plaque WIDTH in points. The view is `size × size * 1.1` (the 40 × 44 viewBox ratio).
    let size: CGFloat

    /// View points per viewBox unit.
    private var s: CGFloat { size / 40 }

    /// The live accent — plat/diamond bodies and rims track the theme (R6b ruling); the
    /// HTML's `#4882FF` is a stand-in for it. Read inside `body` so @Observable tracks it.
    private var accent: Color { SettingsManager.shared.activeColors.primary }

    var body: some View {
        let chrome = Self.chrome(for: rank, accent: accent)

        ZStack(alignment: .topLeading) {
            // 1 — glow rings, back to front (soft, blurred; the HTML's flat rings approximate these).
            ForEach(Array(chrome.rings.enumerated()), id: \.offset) { _, ring in
                PlaqueHex(dw: ring.expansion, dh: ring.expansion)
                    .stroke(ring.color.opacity(ring.opacity), lineWidth: ring.width * s)
                    .blur(radius: ring.blur * s)
            }

            // 2 — the plaque: fill + rim.
            PlaqueHex().fill(chrome.fill)
            PlaqueHex().stroke(chrome.rim, lineWidth: chrome.rimWidth * s)

            // 3 — inner bevel ring (flat-plate treatment: Stone / Copper only).
            if chrome.hasBevel {
                PlaqueHex(dw: -2.1, dh: -2.5)
                    .stroke(Ink.bevel, lineWidth: 1 * s)
            }

            // 4 — shine streak(s), clipped to the plaque.
            ZStack(alignment: .topLeading) {
                ForEach(Array(chrome.shines.enumerated()), id: \.offset) { _, shine in
                    Self.viewBoxPoly(shine.points, s).fill(shine.color.opacity(shine.opacity))
                }
            }
            .clipShape(PlaqueHex())

            // 5 — the emblem.
            emblem
        }
        .frame(width: size, height: size * 1.1, alignment: .topLeading)
        .accessibilityElement()
        .accessibilityLabel(rank.displayName)
    }

    /// One private builder per rank, dispatched from a single switch (R7a §2).
    @ViewBuilder
    private var emblem: some View {
        let em = Em(s: s)
        switch rank {
        case .stone:     stoneEmblem(em)
        case .copper:    copperEmblem(em)
        case .iron:      ironEmblem(em)
        case .gold:      goldEmblem(em)
        case .platinum:  platinumEmblem(em)
        case .diamond:   diamondEmblem(em)
        case .sentinel:  sentinelEmblem(em)
        case .prismatic: prismaticEmblem(em)
        case .zenith:    zenithEmblem(em)
        }
    }
}

// MARK: - Palette (emblem artwork literals)

/// Every hex from the HTML palette table. These are ARTWORK values, not theme taxonomy —
/// deliberately NOT DesignSystem tokens. The one exception is plat/diamond's body + rim,
/// which is the live accent (see `RankPlaque.accent`).
private enum Ink {
    // Chrome
    static let bevel = Color(hex: "#252B35")

    // Stone
    static let stoneBase = Color(hex: "#3A3F47")
    static let stoneBody = Color(hex: "#565D68")
    static let stoneHi = Color(hex: "#9AA1AC")

    // Copper
    static let copperBase = Color(hex: "#7A4526")
    static let copperBody = Color(hex: "#C9784A")
    static let copperHi = Color(hex: "#E8A876")

    // Iron
    static let ironBase = Color(hex: "#525A66")
    static let ironBody = Color(hex: "#A8B2C0")
    static let ironHi = Color(hex: "#DDE3EA")

    // Gold
    static let goldBase = Color(hex: "#9A7220")
    static let goldBody = Color(hex: "#E8B84B")
    static let goldHi = Color(hex: "#FFF0C4")

    // Platinum / Diamond (body + rim are the LIVE ACCENT; these are the fixed companions)
    static let platBase = Color(hex: "#2B57C4")
    static let platFacetLine = Color(hex: "#1E3F94")
    static let platHi = Color(hex: "#AFCBFF")
    static let platHiSoft = Color(hex: "#D6E4FF")

    // Prismatic group (Sentinel / Prismatic / Zenith)
    static let prismBase = Color(hex: "#3A2E7A")     // facet split lines + emblem base
    static let prismViolet = Color(hex: "#6D4DD8")
    static let prismBlue = Color(hex: "#4882FF")
    static let prismCyan = Color(hex: "#58E0E8")
    static let prismPink = Color(hex: "#E58BE0")
    static let prismIce = Color(hex: "#EDF6FF")
    static let prismIceWash = Color(hex: "#C9F4FF")
    static let prismPinkWash = Color(hex: "#F3D2F5")
    static let prismRim = Color(hex: "#8F7BE8")
    static let zenithRim = Color(hex: "#A9BFFF")

    // Plaque fills
    static let fillDark = Color(hex: "#1A1F28")      // stone / copper / iron
    static let fillWarm = Color(hex: "#1B2029")      // gold / platinum / diamond
    static let fillSentinel = Color(hex: "#201F33")
    static let fillPrismatic = Color(hex: "#221F35")
    static let fillZenith = Color(hex: "#242038")

    /// The prismatic sweep: violet → blue → cyan → pink → violet (seamless).
    static let prismSweep = Gradient(colors: [prismViolet, prismBlue, prismCyan, prismPink, prismViolet])
}

// MARK: - Chrome (ONE shared builder, parameterised by tier group)

private struct GlowRing {
    let expansion: CGFloat
    let color: Color
    let opacity: Double
    var width: CGFloat = 1
    var blur: CGFloat = 2
}

private struct Shine {
    let points: [(CGFloat, CGFloat)]   // viewBox coords
    let color: Color
    let opacity: Double
}

private struct PlaqueChrome {
    var rings: [GlowRing] = []
    var fill: Color
    var rim: Color
    var rimWidth: CGFloat
    var hasBevel: Bool = false
    var shines: [Shine] = []
}

private extension RankPlaque {

    /// The escalation table, in one place. Stone/Copper are flat plates; Iron/Gold gain a
    /// shine + one faint ring; Platinum/Diamond two accent rings; the top three alternate
    /// hues across two/three/four rings. Opacities calibrate the glow strengths.
    static func chrome(for rank: Rank, accent: Color) -> PlaqueChrome {
        // The four shine geometries, widening as the treatment escalates.
        let shineSmall: [(CGFloat, CGFloat)] = [(2, 14), (14, 2), (20, 2), (4, 20)]
        let shineMid: [(CGFloat, CGFloat)] = [(0, 16), (16, 0), (23, 0), (3, 22)]
        let shineWide: [(CGFloat, CGFloat)] = [(0, 17), (17, 0), (24, 0), (3, 23)]
        let shineWidest: [(CGFloat, CGFloat)] = [(0, 18), (18, 0), (25, 0), (3, 24)]

        switch rank {
        case .stone:
            return PlaqueChrome(fill: Ink.fillDark, rim: Ink.stoneBase, rimWidth: 1.4, hasBevel: true)

        case .copper:
            return PlaqueChrome(fill: Ink.fillDark, rim: Ink.copperBase, rimWidth: 1.4, hasBevel: true)

        case .iron:
            return PlaqueChrome(
                rings: [GlowRing(expansion: 2, color: Ink.ironBody, opacity: 0.22, blur: 1.5)],
                fill: Ink.fillDark, rim: Ink.ironBody, rimWidth: 1.4,
                shines: [Shine(points: shineSmall, color: Ink.ironHi, opacity: 0.08)]
            )

        case .gold:
            return PlaqueChrome(
                rings: [GlowRing(expansion: 2, color: Ink.goldBody, opacity: 0.30, blur: 1.5)],
                fill: Ink.fillWarm, rim: Ink.goldBody, rimWidth: 1.4,
                shines: [Shine(points: shineMid, color: Ink.goldHi, opacity: 0.12)]
            )

        case .platinum:
            return PlaqueChrome(
                rings: [
                    GlowRing(expansion: 4, color: accent, opacity: 0.16, blur: 2.5),
                    GlowRing(expansion: 2, color: accent, opacity: 0.34, blur: 1.5),
                ],
                fill: Ink.fillWarm, rim: accent, rimWidth: 1.4,
                shines: [Shine(points: shineMid, color: Ink.platHiSoft, opacity: 0.13)]
            )

        case .diamond:
            return PlaqueChrome(
                rings: [
                    GlowRing(expansion: 4, color: accent, opacity: 0.18, blur: 2.5),
                    GlowRing(expansion: 2, color: accent, opacity: 0.40, width: 1.1, blur: 1.5),
                ],
                fill: Ink.fillWarm, rim: accent, rimWidth: 1.5,
                shines: [
                    Shine(points: shineWide, color: Ink.platHiSoft, opacity: 0.16),
                    // Lower-right counter-shine.
                    Shine(points: [(26, 44), (40, 29), (40, 23), (24, 42)], color: Ink.platHiSoft, opacity: 0.07),
                ]
            )

        case .sentinel:
            return PlaqueChrome(
                rings: [
                    GlowRing(expansion: 4, color: Ink.prismViolet, opacity: 0.28, blur: 2.5),
                    GlowRing(expansion: 2, color: Ink.prismCyan, opacity: 0.40, width: 1.1, blur: 1.5),
                ],
                fill: Ink.fillSentinel, rim: Ink.prismRim, rimWidth: 1.5,
                shines: [Shine(points: shineWide, color: Ink.prismIceWash, opacity: 0.15)]
            )

        case .prismatic:
            return PlaqueChrome(
                rings: [
                    GlowRing(expansion: 5, color: Ink.prismPink, opacity: 0.20, blur: 3),
                    GlowRing(expansion: 4, color: Ink.prismViolet, opacity: 0.32, blur: 2.5),
                    GlowRing(expansion: 2, color: Ink.prismCyan, opacity: 0.45, width: 1.1, blur: 1.5),
                ],
                fill: Ink.fillPrismatic, rim: Ink.prismRim, rimWidth: 1.5,
                shines: [
                    Shine(points: shineWide, color: Ink.prismIceWash, opacity: 0.17),
                    Shine(points: [(26, 44), (40, 29), (40, 24), (24, 42)], color: Ink.prismPinkWash, opacity: 0.08),
                ]
            )

        case .zenith:
            return PlaqueChrome(
                rings: [
                    GlowRing(expansion: 6, color: Ink.prismPink, opacity: 0.18, blur: 3.5),
                    GlowRing(expansion: 5, color: Ink.prismViolet, opacity: 0.28, blur: 3),
                    GlowRing(expansion: 4, color: Ink.prismCyan, opacity: 0.40, blur: 2.5),
                    GlowRing(expansion: 2, color: Ink.prismIce, opacity: 0.55, blur: 1.5),
                ],
                fill: Ink.fillZenith, rim: Ink.zenithRim, rimWidth: 1.6,
                shines: [
                    Shine(points: shineWidest, color: Ink.prismIce, opacity: 0.20),
                    Shine(points: [(25, 44), (40, 28), (40, 23), (23, 42)], color: Ink.prismPinkWash, opacity: 0.10),
                ]
            )
        }
    }

    /// A closed polygon in viewBox (0…40 × 0…44) coordinates.
    static func viewBoxPoly(_ pts: [(CGFloat, CGFloat)], _ s: CGFloat) -> Path {
        var path = Path()
        guard let first = pts.first else { return path }
        path.move(to: CGPoint(x: first.0 * s, y: first.1 * s))
        for pt in pts.dropFirst() { path.addLine(to: CGPoint(x: pt.0 * s, y: pt.1 * s)) }
        path.closeSubpath()
        return path
    }
}

// MARK: - Shapes

/// The plaque hexagon (pointy-top). Centre (20, 21.75), half-width 15.5, half-height 18.25
/// in viewBox units at expansion 0 — the HTML's every ring is this hexagon grown uniformly,
/// so the rings and the plate share one definition.
private struct PlaqueHex: Shape {
    var dw: CGFloat = 0
    var dh: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let s = rect.width / 40
        let cx: CGFloat = 20, cy: CGFloat = 21.75
        let w = 15.5 + dw, h = 18.25 + dh
        var p = Path()
        p.move(to: CGPoint(x: cx * s, y: (cy - h) * s))
        p.addLine(to: CGPoint(x: (cx + w) * s, y: (cy - h / 2) * s))
        p.addLine(to: CGPoint(x: (cx + w) * s, y: (cy + h / 2) * s))
        p.addLine(to: CGPoint(x: cx * s, y: (cy + h) * s))
        p.addLine(to: CGPoint(x: (cx - w) * s, y: (cy + h / 2) * s))
        p.addLine(to: CGPoint(x: (cx - w) * s, y: (cy - h / 2) * s))
        p.closeSubpath()
        return p
    }
}

/// The emblem's local coordinate space — the HTML's `<g transform="translate(8.6,10) scale(0.71)">`.
/// Every emblem path below is written in the HTML's own numbers and mapped through here, so a
/// coordinate can be diffed against the ground truth by eye.
private struct Em {
    let s: CGFloat

    /// Emblem-space point → view point.
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: (8.6 + 0.71 * x) * s, y: (10 + 0.71 * y) * s)
    }

    /// Emblem-space stroke width → view points.
    func w(_ width: CGFloat) -> CGFloat { width * 0.71 * s }

    func poly(_ pts: [(CGFloat, CGFloat)]) -> Path {
        var path = Path()
        guard let first = pts.first else { return path }
        path.move(to: p(first.0, first.1))
        for pt in pts.dropFirst() { path.addLine(to: p(pt.0, pt.1)) }
        path.closeSubpath()
        return path
    }

    func line(_ pts: [(CGFloat, CGFloat)]) -> Path {
        var path = Path()
        guard let first = pts.first else { return path }
        path.move(to: p(first.0, first.1))
        for pt in pts.dropFirst() { path.addLine(to: p(pt.0, pt.1)) }
        return path
    }

    func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> Path {
        let c = p(cx, cy)
        let rr = r * 0.71 * s
        return Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2))
    }

    /// Cubic bezier segment appended in emblem space.
    func curve(_ path: inout Path, to end: (CGFloat, CGFloat),
               c1: (CGFloat, CGFloat), c2: (CGFloat, CGFloat)) {
        path.addCurve(to: p(end.0, end.1), control1: p(c1.0, c1.1), control2: p(c2.0, c2.1))
    }
}

// MARK: - Emblems (one builder per rank; coordinates traced from the HTML)

private extension RankPlaque {

    // Stone — a cut block.
    func stoneEmblem(_ em: Em) -> some View {
        ZStack(alignment: .topLeading) {
            em.poly([(16, 3), (27, 9), (27, 23), (16, 29), (5, 23), (5, 9)]).fill(Ink.stoneBase)
            em.poly([(16, 6), (24, 10.5), (24, 21.5), (16, 26), (8, 21.5), (8, 10.5)]).fill(Ink.stoneBody)
            em.line([(16, 6), (16, 26)]).stroke(Ink.stoneBase, lineWidth: em.w(1.4))
            em.line([(8, 10.5), (16, 15), (24, 10.5)]).stroke(Ink.stoneBase, lineWidth: em.w(1.4))
            em.line([(16, 15), (16, 26)]).stroke(Ink.stoneBase, lineWidth: em.w(1.4))
            em.line([(12, 9.5), (16, 7.7), (20, 11.3)])
                .stroke(Ink.stoneHi, style: StrokeStyle(lineWidth: em.w(1.3), lineCap: .round))
        }
    }

    // Copper — a shield with a chevron.
    func copperEmblem(_ em: Em) -> some View {
        ZStack(alignment: .topLeading) {
            Self.shieldOuter(em).fill(Ink.copperBase)
            Self.shieldInner(em).fill(Ink.copperBody)
            em.poly([(16, 9), (21, 18), (11, 18)]).fill(Ink.copperBase)
            em.poly([(16, 12.2), (18.6, 17), (13.4, 17)]).fill(Ink.copperHi)
            em.circle(9.5, 11, 1.1).fill(Ink.copperHi)
            em.circle(22.5, 11, 1.1).fill(Ink.copperHi)
        }
    }

    // Iron — the same shield, crossed.
    func ironEmblem(_ em: Em) -> some View {
        ZStack(alignment: .topLeading) {
            Self.shieldOuter(em).fill(Ink.ironBase)
            Self.shieldInner(em).fill(Ink.ironBody)
            em.line([(16, 4.5), (16, 27.5)]).stroke(Ink.ironBase, lineWidth: em.w(2.2))
            em.line([(6.5, 13.5), (25.5, 13.5)]).stroke(Ink.ironBase, lineWidth: em.w(2.2))
            em.circle(16, 13.5, 3.4).fill(Ink.ironBase)
            em.circle(16, 13.5, 1.7).fill(Ink.ironHi)
            em.circle(10, 9.5, 1).fill(Ink.ironHi)
            em.circle(22, 9.5, 1).fill(Ink.ironHi)
            em.circle(10, 19, 1).fill(Ink.ironHi)
            em.circle(22, 19, 1).fill(Ink.ironHi)
        }
    }

    // Gold — a star on a plinth.
    func goldEmblem(_ em: Em) -> some View {
        ZStack(alignment: .topLeading) {
            em.poly([(16, 1.5), (19.6, 9), (27.8, 10), (21.8, 15.6), (23.4, 23.8),
                     (16, 19.9), (8.6, 23.8), (10.2, 15.6), (4.2, 10), (12.4, 9)])
                .fill(Ink.goldBase)
            em.poly([(16, 4.6), (18.6, 10), (24.6, 10.8), (20.2, 14.9), (21.3, 20.9),
                     (16, 18), (10.7, 20.9), (11.8, 14.9), (7.4, 10.8), (13.4, 10)])
                .fill(Ink.goldBody)
            em.line([(16, 4.6), (16, 18)]).stroke(Ink.goldBase, lineWidth: em.w(1.2))
            em.line([(13.4, 10), (7.4, 10.8)]).stroke(Ink.goldBase, lineWidth: em.w(1.2))
            em.line([(18.6, 10), (24.6, 10.8)]).stroke(Ink.goldBase, lineWidth: em.w(1.2))
            em.circle(16, 13, 2).fill(Ink.goldHi)
            em.line([(4, 27), (28, 27)])
                .stroke(Ink.goldBase, style: StrokeStyle(lineWidth: em.w(1.6), lineCap: .round))
            em.line([(8, 27), (10, 24)])
                .stroke(Ink.goldBase, style: StrokeStyle(lineWidth: em.w(1.4), lineCap: .round))
            em.line([(24, 27), (22, 24)])
                .stroke(Ink.goldBase, style: StrokeStyle(lineWidth: em.w(1.4), lineCap: .round))
        }
    }

    // Platinum — stacked chevrons. Body + rim ride the live accent.
    func platinumEmblem(_ em: Em) -> some View {
        ZStack(alignment: .topLeading) {
            em.poly([(16, 3), (8, 11), (11, 13.6), (16, 9), (21, 13.6), (24, 11)]).fill(Ink.platBase)
            em.poly([(16, 9.5), (9.5, 16), (12.5, 18.6), (16, 15.2), (19.5, 18.6), (22.5, 16)]).fill(accent)
            em.poly([(16, 16.5), (11, 21.5), (16, 27.5), (21, 21.5)]).fill(accent)
            em.poly([(16, 20), (13.6, 22.3), (16, 25), (18.4, 22.3)]).fill(Ink.platHi)
            em.line([(3.5, 14.5), (7, 17)])
                .stroke(Ink.platHi, style: StrokeStyle(lineWidth: em.w(1.5), lineCap: .round))
            em.line([(28.5, 14.5), (25, 17)])
                .stroke(Ink.platHi, style: StrokeStyle(lineWidth: em.w(1.5), lineCap: .round))
        }
    }

    // Diamond — a cut gem. Body rides the live accent; facet lines stay fixed.
    func diamondEmblem(_ em: Em) -> some View {
        // The four lit facets, merged into one path so they fill as a single body.
        var facets = Path()
        facets.addPath(em.poly([(9, 4), (16, 12), (9, 12), (6, 12)]))
        facets.addPath(em.poly([(23, 4), (16, 12), (23, 12), (26, 12)]))
        facets.addPath(em.poly([(16, 12), (9, 12), (16, 27)]))
        facets.addPath(em.poly([(16, 12), (23, 12), (16, 27)]))

        return ZStack(alignment: .topLeading) {
            em.poly([(9, 4), (23, 4), (29, 12), (16, 29), (3, 12)]).fill(Ink.platBase)
            facets.fill(accent)
            em.line([(9, 4), (23, 4)]).stroke(Ink.platFacetLine, lineWidth: em.w(1.1))
            em.line([(16, 12), (3, 12)]).stroke(Ink.platFacetLine, lineWidth: em.w(1.1))
            em.line([(16, 12), (29, 12)]).stroke(Ink.platFacetLine, lineWidth: em.w(1.1))
            em.line([(9, 4), (16, 12), (23, 4)]).stroke(Ink.platFacetLine, lineWidth: em.w(1.1))
            em.line([(16, 12), (16, 29)]).stroke(Ink.platFacetLine, lineWidth: em.w(1.1))
            em.line([(12, 7.5), (14.5, 4.8)])
                .stroke(Ink.platHiSoft, style: StrokeStyle(lineWidth: em.w(1.5), lineCap: .round))
            em.circle(26, 3.5, 1).fill(Ink.platHiSoft)
            em.circle(5, 6, 0.8).fill(Ink.platHiSoft)
        }
    }

    // Sentinel — a winged shield; its two facets take the prismatic sweep.
    func sentinelEmblem(_ em: Em) -> some View {
        // Base shield: M16 5 26 9.5 v7 c(…) → mirrored back up the left side.
        var base = Path()
        base.move(to: em.p(16, 5))
        base.addLine(to: em.p(26, 9.5))
        base.addLine(to: em.p(26, 16.5))
        em.curve(&base, to: (16, 27.5), c1: (26, 21.5), c2: (22, 25.2))
        em.curve(&base, to: (6, 16.5), c1: (10, 25.2), c2: (6, 21.5))
        base.addLine(to: em.p(6, 9.5))
        base.closeSubpath()

        var right = Path()
        right.move(to: em.p(16, 7.3))
        right.addLine(to: em.p(23.8, 10.8))
        right.addLine(to: em.p(23.8, 16.3))
        em.curve(&right, to: (16, 25), c1: (23.8, 20.2), c2: (20.6, 23.1))
        right.addLine(to: em.p(16, 10))
        right.closeSubpath()

        var left = Path()
        left.move(to: em.p(16, 7.3))
        left.addLine(to: em.p(8.2, 10.8))
        left.addLine(to: em.p(8.2, 16.3))
        em.curve(&left, to: (16, 25), c1: (8.2, 20.2), c2: (11.4, 23.1))
        left.addLine(to: em.p(16, 10))
        left.closeSubpath()

        // Wings: left cyan, right pink.
        var wingL1 = Path(); wingL1.move(to: em.p(2, 10))
        em.curve(&wingL1, to: (8, 12.2), c1: (4.5, 9.5), c2: (6.5, 10.3))
        var wingL2 = Path(); wingL2.move(to: em.p(2, 14))
        em.curve(&wingL2, to: (7, 15.8), c1: (4, 13.7), c2: (5.6, 14.4))
        var wingR1 = Path(); wingR1.move(to: em.p(30, 10))
        em.curve(&wingR1, to: (24, 12.2), c1: (27.5, 9.5), c2: (25.5, 10.3))
        var wingR2 = Path(); wingR2.move(to: em.p(30, 14))
        em.curve(&wingR2, to: (25, 15.8), c1: (28, 13.7), c2: (26.4, 14.4))

        let wing = StrokeStyle(lineWidth: em.w(1.4), lineCap: .round)

        return ZStack(alignment: .topLeading) {
            base.fill(Ink.prismBase)
            Self.prismSweep(masking: [right, left])
            em.poly([(16, 10.5), (18, 15), (14, 15)]).fill(Ink.prismIce)
            em.line([(16, 15), (16, 21)])
                .stroke(Ink.prismIceWash, style: StrokeStyle(lineWidth: em.w(1.6), lineCap: .round))
            wingL1.stroke(Ink.prismCyan, style: wing)
            wingL2.stroke(Ink.prismCyan, style: wing)
            wingR1.stroke(Ink.prismPink, style: wing)
            wingR2.stroke(Ink.prismPink, style: wing)
        }
    }

    // Prismatic — a crown on a double bar; its two facets take the prismatic sweep.
    func prismaticEmblem(_ em: Em) -> some View {
        let left = em.poly([(6.5, 20.5), (5.2, 10.8), (9.8, 14), (16, 6.8), (16, 20.5)])
        let right = em.poly([(25.5, 20.5), (26.8, 10.8), (22.2, 14), (16, 6.8), (16, 20.5)])
        let bar = StrokeStyle(lineWidth: em.w(1.8), lineCap: .round)

        return ZStack(alignment: .topLeading) {
            em.poly([(5, 22), (3, 8), (9.5, 12.5), (16, 4), (22.5, 12.5), (29, 8), (27, 22)])
                .fill(Ink.prismBase)
            Self.prismSweep(masking: [left, right])
            em.circle(16, 15.5, 2).fill(Ink.prismIce)
            em.circle(9.5, 17, 1.2).fill(Ink.prismCyan)
            em.circle(22.5, 17, 1.2).fill(Ink.prismPink)
            em.line([(5, 24.5), (27, 24.5)]).stroke(Ink.prismBase, style: bar)
            em.line([(5, 27), (27, 27)]).stroke(Ink.prismBase, style: bar)
            em.line([(5, 24.5), (14, 24.5)]).stroke(Ink.prismCyan.opacity(0.8), style: bar)
            em.line([(18, 27), (27, 27)]).stroke(Ink.prismPink.opacity(0.8), style: bar)
        }
    }

    // Zenith — a rayed star in an arc cradle; its two facets take the prismatic sweep.
    func zenithEmblem(_ em: Em) -> some View {
        let right = em.poly([(16, 11), (18, 15.2), (22.4, 15.8), (19.2, 18.8), (20, 23.2), (16, 21.1)])
        let left = em.poly([(16, 11), (14, 15.2), (9.6, 15.8), (12.8, 18.8), (12, 23.2), (16, 21.1)])

        var arcL = Path(); arcL.move(to: em.p(2.5, 16))
        em.curve(&arcL, to: (10, 27.5), c1: (3.1, 21.4), c2: (5.7, 25.2))
        var arcR = Path(); arcR.move(to: em.p(29.5, 16))
        em.curve(&arcR, to: (22, 27.5), c1: (28.9, 21.4), c2: (26.3, 25.2))

        let ray = StrokeStyle(lineWidth: em.w(1.4), lineCap: .round)
        let arc = StrokeStyle(lineWidth: em.w(1.5), lineCap: .round)

        return ZStack(alignment: .topLeading) {
            // Rays, hue-paired outward from the star.
            em.line([(16, 8), (14, 2)]).stroke(Ink.prismCyan, style: ray)
            em.line([(16, 8), (18, 2)]).stroke(Ink.prismCyan, style: ray)
            em.line([(16, 8), (11, 3.5)]).stroke(Ink.prismPink, style: ray)
            em.line([(16, 8), (21, 3.5)]).stroke(Ink.prismPink, style: ray)
            em.line([(16, 8), (8.5, 6)]).stroke(Ink.prismViolet, style: ray)
            em.line([(16, 8), (23.5, 6)]).stroke(Ink.prismViolet, style: ray)

            em.poly([(16, 8.5), (18.8, 14), (24.8, 14.9), (20.4, 19.1), (21.5, 25.1),
                     (16, 22.2), (10.5, 25.1), (11.6, 19.1), (7.2, 14.9), (13.2, 14)])
                .fill(Ink.prismBase)
            Self.prismSweep(masking: [right, left])
            em.circle(16, 17.5, 1.8).fill(Ink.prismIce)

            arcL.stroke(Ink.prismCyan, style: arc)
            arcR.stroke(Ink.prismPink, style: arc)
        }
    }

    // MARK: Shared emblem pieces

    /// The shield outer, shared by Copper and Iron (identical geometry, different metal).
    static func shieldOuter(_ em: Em) -> Path {
        var p = Path()
        p.move(to: em.p(16, 2))
        p.addLine(to: em.p(28, 8))
        p.addLine(to: em.p(28, 17))
        em.curve(&p, to: (16, 30), c1: (28, 23), c2: (23, 27.5))
        em.curve(&p, to: (4, 17), c1: (9, 27.5), c2: (4, 23))
        p.addLine(to: em.p(4, 8))
        p.closeSubpath()
        return p
    }

    /// The shield inner face, shared by Copper and Iron.
    static func shieldInner(_ em: Em) -> Path {
        var p = Path()
        p.move(to: em.p(16, 4.5))
        p.addLine(to: em.p(25.5, 9.3))
        p.addLine(to: em.p(25.5, 16.8))
        em.curve(&p, to: (16, 27.5), c1: (25.5, 21.6), c2: (21.5, 25.3))
        em.curve(&p, to: (6.5, 16.8), c1: (10.5, 25.3), c2: (6.5, 21.6))
        p.addLine(to: em.p(6.5, 9.3))
        p.closeSubpath()
        return p
    }

    /// The prismatic AngularGradient swept across the given facet shapes (Sentinel /
    /// Prismatic / Zenith). Facet split lines stay `prismBase` — they are drawn beneath.
    static func prismSweep(masking facets: [Path]) -> some View {
        AngularGradient(gradient: Ink.prismSweep, center: .center)
            .mask {
                ZStack(alignment: .topLeading) {
                    ForEach(Array(facets.enumerated()), id: \.offset) { _, facet in
                        facet.fill(.white)
                    }
                }
            }
    }
}

// MARK: - Preview (the ladder's regression surface — keep it)

#Preview("Rank ladder") {
    ScrollView {
        VStack(spacing: 26) {
            ForEach(Rank.allCases, id: \.self) { rank in
                HStack(spacing: 18) {
                    RankPlaque(rank: rank, size: 44)
                    RankPlaque(rank: rank, size: 64)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rank.displayName.uppercased())
                            .font(AppFont.display(20))
                            .foregroundColor(SettingsManager.shared.activeColors.textPrimary)
                        Text("RR \(rank.rrThreshold)+  ·  raw \"\(rank.rawValue)\"")
                            .font(AppFont.regular(11))
                            .foregroundColor(SettingsManager.shared.activeColors.textSecondary)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(28)
    }
    .background(SettingsManager.shared.activeColors.primaryBackground)
}
