//
//  HomeView.swift
//  HealthBar
//
//  Created by Claude on 1/19/26.
//  Updated on 4/29/26 - Pixel-art RPG redesign
//

import SwiftUI
import SwiftData

// MARK: - Pixel Art Background

struct PixelLandscapeBackground: View {
    let theme: TimeOfDayTheme

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let px = w / 60

            switch theme {
            case .morning:
                drawMorning(context, w: w, h: h, px: px)
            case .afternoon:
                drawAfternoon(context, w: w, h: h, px: px)
            case .night:
                drawNight(context, w: w, h: h, px: px)
            }
        }
        .drawingGroup()
    }

    // MARK: - Morning Scene

    private func drawMorning(_ context: GraphicsContext, w: CGFloat, h: CGFloat, px: CGFloat) {
        // Sky
        context.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(Color(hex: "#DCFCE7")))

        // Sun (upper right)
        let sunX = 47 * px
        // Halo
        fillRect(context, x: sunX, y: 3*px, w: 4*px, h: px, color: "#FDE68A")
        fillRect(context, x: sunX - 2*px, y: 6*px, w: px, h: 3*px, color: "#FDE68A")
        fillRect(context, x: sunX + 5*px, y: 6*px, w: px, h: 3*px, color: "#FDE68A")
        fillRect(context, x: sunX, y: 11*px, w: 4*px, h: px, color: "#FDE68A")
        // Core
        fillRect(context, x: sunX + px, y: 4*px, w: 2*px, h: px, color: "#FBBF24")
        fillRect(context, x: sunX, y: 5*px, w: 4*px, h: px, color: "#FBBF24")
        fillRect(context, x: sunX - px, y: 6*px, w: 6*px, h: 3*px, color: "#FBBF24")
        fillRect(context, x: sunX, y: 9*px, w: 4*px, h: px, color: "#FBBF24")
        fillRect(context, x: sunX + px, y: 10*px, w: 2*px, h: px, color: "#FBBF24")

        // Clouds
        fillRect(context, x: 6*px, y: 14*px, w: 6*px, h: px, color: "#FFFFFF", opacity: 0.75)
        fillRect(context, x: 4*px, y: 15*px, w: 10*px, h: 2*px, color: "#FFFFFF", opacity: 0.75)
        fillRect(context, x: 6*px, y: 17*px, w: 6*px, h: px, color: "#FFFFFF", opacity: 0.75)
        fillRect(context, x: 22*px, y: 22*px, w: 5*px, h: px, color: "#FFFFFF", opacity: 0.75)
        fillRect(context, x: 20*px, y: 23*px, w: 9*px, h: 2*px, color: "#FFFFFF", opacity: 0.75)
        fillRect(context, x: 22*px, y: 25*px, w: 5*px, h: px, color: "#FFFFFF", opacity: 0.75)

        // Sparkles
        for star in [(14,3),(38,8),(32,16),(3,9),(55,18),(42,20)] as [(Int,Int)] {
            fillRect(context, x: CGFloat(star.0)*px, y: CGFloat(star.1)*px, w: px, h: px, color: "#FBBF24", opacity: 0.7)
        }

        // Mountains
        let mOff = h * 0.35
        drawMorningTerrain(context, w: w, px: px, mOff: mOff)
    }

    private func drawMorningTerrain(_ context: GraphicsContext, w: CGFloat, px: CGFloat, mOff: CGFloat) {
        // Range 1 (lightest)
        fillRect(context, x: 0, y: mOff + 44*px, w: w, h: 45*px, color: "#A7F3D0")
        for b in [(2,39,4,5),(4,37,2,2),(10,41,3,3),(18,37,5,7),(20,35,3,2),(28,40,4,4),(36,38,6,6),(38,36,4,2),(40,35,2,1),(48,40,5,4),(56,39,4,5)] as [(Int,Int,Int,Int)] {
            fillRect(context, x: CGFloat(b.0)*px, y: mOff + CGFloat(b.1)*px, w: CGFloat(b.2)*px, h: CGFloat(b.3)*px, color: "#A7F3D0")
        }
        // Range 2
        fillRect(context, x: 0, y: mOff + 54*px, w: w, h: 35*px, color: "#6EE7B7")
        for b in [(6,49,6,5),(8,47,4,2),(22,50,8,4),(24,48,4,2),(40,49,10,5),(44,47,3,2),(56,51,4,3)] as [(Int,Int,Int,Int)] {
            fillRect(context, x: CGFloat(b.0)*px, y: mOff + CGFloat(b.1)*px, w: CGFloat(b.2)*px, h: CGFloat(b.3)*px, color: "#6EE7B7")
        }
        // Range 3 (darkest)
        fillRect(context, x: 0, y: mOff + 67*px, w: w, h: 22*px, color: "#34D399")
        fillRect(context, x: 0, y: mOff + 65*px, w: 14*px, h: 2*px, color: "#34D399")
        fillRect(context, x: 14*px, y: mOff + 63*px, w: 20*px, h: 4*px, color: "#34D399")
        fillRect(context, x: 34*px, y: mOff + 65*px, w: 26*px, h: 2*px, color: "#34D399")
        // Tree 1
        fillRect(context, x: 20*px, y: mOff + 62*px, w: 2*px, h: 5*px, color: "#92400E")
        fillRect(context, x: 18*px, y: mOff + 57*px, w: 6*px, h: 5*px, color: "#059669")
        fillRect(context, x: 19*px, y: mOff + 56*px, w: 4*px, h: px, color: "#059669")
        // Tree 2
        fillRect(context, x: 44*px, y: mOff + 63*px, w: 2*px, h: 4*px, color: "#92400E")
        fillRect(context, x: 42*px, y: mOff + 59*px, w: 6*px, h: 4*px, color: "#059669")
        // Grass
        for g in [(3,73),(8,75),(13,74),(29,76),(35,73),(50,74),(55,76),(38,78)] as [(Int,Int)] {
            fillRect(context, x: CGFloat(g.0)*px, y: mOff + CGFloat(g.1)*px, w: px, h: px, color: "#10B981")
        }
    }

    // MARK: - Afternoon Scene

    private func drawAfternoon(_ context: GraphicsContext, w: CGFloat, h: CGFloat, px: CGFloat) {
        // Amber sky
        context.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(Color(hex: "#FEF3C7")))

        // Warm gradient band near horizon
        fillRect(context, x: 0, y: 36*px, w: w, h: 10*px, color: "#FBBF24", opacity: 0.1)
        fillRect(context, x: 0, y: 40*px, w: w, h: 8*px, color: "#F59E0B", opacity: 0.08)

        // Sun glow (soft oversized rect behind sun)
        fillRect(context, x: 43*px, y: 17*px, w: 8*px, h: 8*px, color: "#F59E0B", opacity: 0.3)

        // Sun halo rays
        fillRect(context, x: 44*px, y: 16*px, w: 6*px, h: px, color: "#FDE68A", opacity: 0.6)
        fillRect(context, x: 42*px, y: 19*px, w: px, h: 4*px, color: "#FDE68A", opacity: 0.6)
        fillRect(context, x: 51*px, y: 19*px, w: px, h: 4*px, color: "#FDE68A", opacity: 0.6)
        fillRect(context, x: 44*px, y: 25*px, w: 6*px, h: px, color: "#FDE68A", opacity: 0.6)

        // Sun body (crisp)
        fillRect(context, x: 45*px, y: 17*px, w: 4*px, h: px, color: "#F59E0B")
        fillRect(context, x: 44*px, y: 18*px, w: 6*px, h: px, color: "#F59E0B")
        fillRect(context, x: 43*px, y: 19*px, w: 8*px, h: 4*px, color: "#F59E0B")
        fillRect(context, x: 44*px, y: 23*px, w: 6*px, h: px, color: "#F59E0B")
        fillRect(context, x: 45*px, y: 24*px, w: 4*px, h: px, color: "#F59E0B")

        // Warm clouds
        fillRect(context, x: 5*px, y: 18*px, w: 6*px, h: px, color: "#FEF9C3", opacity: 0.65)
        fillRect(context, x: 3*px, y: 19*px, w: 10*px, h: 2*px, color: "#FEF9C3", opacity: 0.65)
        fillRect(context, x: 5*px, y: 21*px, w: 6*px, h: px, color: "#FEF9C3", opacity: 0.65)
        fillRect(context, x: 20*px, y: 26*px, w: 5*px, h: px, color: "#FEF9C3", opacity: 0.65)
        fillRect(context, x: 18*px, y: 27*px, w: 9*px, h: 2*px, color: "#FEF9C3", opacity: 0.65)
        fillRect(context, x: 20*px, y: 29*px, w: 5*px, h: px, color: "#FEF9C3", opacity: 0.65)

        // Sparkles with glow (3×3 halo behind each)
        for star in [(14,8),(36,12),(8,14),(30,6),(55,10)] as [(Int,Int)] {
            let sx = CGFloat(star.0) * px
            let sy = CGFloat(star.1) * px
            fillRect(context, x: sx - px, y: sy - px, w: 3*px, h: 3*px, color: "#F59E0B", opacity: 0.15)
            fillRect(context, x: sx, y: sy, w: px, h: px, color: "#F59E0B", opacity: 0.6)
        }

        // Mountains
        let mOff = h * 0.35 - 11*px
        drawAfternoonTerrain(context, w: w, px: px, mOff: mOff)
    }

    private func drawAfternoonTerrain(_ context: GraphicsContext, w: CGFloat, px: CGFloat, mOff: CGFloat) {
        // Back range (olive-warm, lighter)
        fillRect(context, x: 0, y: mOff + 55*px, w: w, h: 45*px, color: "#BEF264", opacity: 0.7)
        for b in [(2,50,4,5),(4,48,2,2),(10,52,3,3),(18,48,5,7),(20,46,3,2),(28,51,4,4),(36,49,6,6),(38,47,4,2),(48,51,5,4),(56,50,4,5)] as [(Int,Int,Int,Int)] {
            fillRect(context, x: CGFloat(b.0)*px, y: mOff + CGFloat(b.1)*px, w: CGFloat(b.2)*px, h: CGFloat(b.3)*px, color: "#BEF264", opacity: 0.7)
        }
        // Mid range
        fillRect(context, x: 0, y: mOff + 65*px, w: w, h: 35*px, color: "#A3E635", opacity: 0.8)
        for b in [(6,60,6,5),(8,58,4,2),(22,61,8,4),(24,59,4,2),(40,60,10,5),(44,58,3,2),(56,62,4,3)] as [(Int,Int,Int,Int)] {
            fillRect(context, x: CGFloat(b.0)*px, y: mOff + CGFloat(b.1)*px, w: CGFloat(b.2)*px, h: CGFloat(b.3)*px, color: "#A3E635", opacity: 0.8)
        }
        // Front range (darkest)
        fillRect(context, x: 0, y: mOff + 78*px, w: w, h: 22*px, color: "#65A30D")
        fillRect(context, x: 0, y: mOff + 76*px, w: 14*px, h: 2*px, color: "#65A30D")
        fillRect(context, x: 14*px, y: mOff + 74*px, w: 20*px, h: 4*px, color: "#65A30D")
        fillRect(context, x: 34*px, y: mOff + 76*px, w: 26*px, h: 2*px, color: "#65A30D")
        // Tree 1
        fillRect(context, x: 20*px, y: mOff + 73*px, w: 2*px, h: 5*px, color: "#78350F")
        fillRect(context, x: 18*px, y: mOff + 68*px, w: 6*px, h: 5*px, color: "#65A30D")
        fillRect(context, x: 19*px, y: mOff + 67*px, w: 4*px, h: px, color: "#65A30D")
        // Tree 2
        fillRect(context, x: 44*px, y: mOff + 74*px, w: 2*px, h: 4*px, color: "#78350F")
        fillRect(context, x: 42*px, y: mOff + 70*px, w: 6*px, h: 4*px, color: "#65A30D")
        // Grass
        for g in [(3,84),(8,86),(13,85),(29,87),(35,84),(50,85),(55,87)] as [(Int,Int)] {
            fillRect(context, x: CGFloat(g.0)*px, y: mOff + CGFloat(g.1)*px, w: px, h: px, color: "#4D7C0F")
        }
    }

    // MARK: - Night Scene

    private func drawNight(_ context: GraphicsContext, w: CGFloat, h: CGFloat, px: CGFloat) {
        // Deep navy sky
        context.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(Color(hex: "#0F172A")))

        // Moon glow (soft halo)
        fillRect(context, x: 44*px, y: 4*px, w: 6*px, h: 8*px, color: "#C7D2FE", opacity: 0.35)

        // Moon body (full circle)
        fillRect(context, x: 46*px, y: 4*px, w: 3*px, h: px, color: "#E0E7FF")
        fillRect(context, x: 44*px, y: 5*px, w: 6*px, h: px, color: "#E0E7FF")
        fillRect(context, x: 43*px, y: 6*px, w: 7*px, h: 3*px, color: "#E0E7FF")
        fillRect(context, x: 44*px, y: 9*px, w: 6*px, h: px, color: "#E0E7FF")
        fillRect(context, x: 46*px, y: 10*px, w: 3*px, h: px, color: "#E0E7FF")
        // Moon shadow (crescent cutout)
        fillRect(context, x: 46*px, y: 5*px, w: 3*px, h: px, color: "#0F172A")
        fillRect(context, x: 46*px, y: 6*px, w: 4*px, h: 2*px, color: "#0F172A")
        fillRect(context, x: 46*px, y: 8*px, w: 3*px, h: px, color: "#0F172A")

        // Stars with glow (3×3 halo behind each 1×1 star)
        let stars: [(Int,Int)] = [(5,4),(12,8),(20,3),(28,7),(35,2),(15,15),(55,6),(8,22),(38,14),(52,20),(25,18),(3,12),(33,25),(48,28),(10,30),(57,15)]
        for s in stars {
            let sx = CGFloat(s.0) * px
            let sy = CGFloat(s.1) * px
            fillRect(context, x: sx - px, y: sy - px, w: 3*px, h: 3*px, color: "#C7D2FE", opacity: 0.15)
            fillRect(context, x: sx, y: sy, w: px, h: px, color: "#FFFFFF", opacity: 0.85)
        }

        // Twinkling cross-stars (1×3 vertical + 3×1 horizontal)
        let crosses: [(Int,Int)] = [(19,9),(7,17),(39,4)]
        for c in crosses {
            let cx = CGFloat(c.0) * px
            let cy = CGFloat(c.1) * px
            // Glow behind
            fillRect(context, x: cx - 2*px, y: cy - 2*px, w: 5*px, h: 5*px, color: "#C7D2FE", opacity: 0.12)
            // Cross
            fillRect(context, x: cx, y: cy - px, w: px, h: 3*px, color: "#C7D2FE", opacity: 0.8)
            fillRect(context, x: cx - px, y: cy, w: 3*px, h: px, color: "#C7D2FE", opacity: 0.8)
        }

        // Mountains
        let mOff = h * 0.35 - 11*px
        drawNightTerrain(context, w: w, px: px, mOff: mOff)
    }

    private func drawNightTerrain(_ context: GraphicsContext, w: CGFloat, px: CGFloat, mOff: CGFloat) {
        // Back silhouette
        fillRect(context, x: 0, y: mOff + 55*px, w: w, h: 45*px, color: "#1E293B")
        for b in [(2,50,4,5),(4,48,2,2),(10,52,3,3),(18,48,5,7),(20,46,3,2),(28,51,4,4),(36,49,6,6),(38,47,4,2),(48,51,5,4),(56,50,4,5)] as [(Int,Int,Int,Int)] {
            fillRect(context, x: CGFloat(b.0)*px, y: mOff + CGFloat(b.1)*px, w: CGFloat(b.2)*px, h: CGFloat(b.3)*px, color: "#1E293B")
        }
        // Mid silhouette
        fillRect(context, x: 0, y: mOff + 65*px, w: w, h: 35*px, color: "#1E1B4B")
        for b in [(6,60,6,5),(8,58,4,2),(22,61,8,4),(24,59,4,2),(40,60,10,5),(44,58,3,2),(56,62,4,3)] as [(Int,Int,Int,Int)] {
            fillRect(context, x: CGFloat(b.0)*px, y: mOff + CGFloat(b.1)*px, w: CGFloat(b.2)*px, h: CGFloat(b.3)*px, color: "#1E1B4B")
        }
        // Front silhouette
        fillRect(context, x: 0, y: mOff + 78*px, w: w, h: 22*px, color: "#0F0E2A")
        fillRect(context, x: 0, y: mOff + 76*px, w: 14*px, h: 2*px, color: "#0F0E2A")
        fillRect(context, x: 14*px, y: mOff + 74*px, w: 20*px, h: 4*px, color: "#0F0E2A")
        fillRect(context, x: 34*px, y: mOff + 76*px, w: 26*px, h: 2*px, color: "#0F0E2A")
        // Tree 1 silhouette
        fillRect(context, x: 20*px, y: mOff + 73*px, w: 2*px, h: 5*px, color: "#1C1917")
        fillRect(context, x: 18*px, y: mOff + 68*px, w: 6*px, h: 5*px, color: "#1E293B")
        fillRect(context, x: 19*px, y: mOff + 67*px, w: 4*px, h: px, color: "#1E293B")
        fillRect(context, x: 20*px, y: mOff + 68*px, w: px, h: px, color: "#334155") // moonlit highlight
        // Tree 2 silhouette
        fillRect(context, x: 44*px, y: mOff + 74*px, w: 2*px, h: 4*px, color: "#1C1917")
        fillRect(context, x: 42*px, y: mOff + 70*px, w: 6*px, h: 4*px, color: "#1E293B")
        fillRect(context, x: 44*px, y: mOff + 70*px, w: px, h: px, color: "#334155") // moonlit highlight

        // Fireflies with glow
        let fireflies: [(Int,Int)] = [(16,71),(26,76),(39,73),(50,78),(9,80),(33,82),(46,84)]
        for f in fireflies {
            let fx = CGFloat(f.0) * px
            let fy = mOff + CGFloat(f.1) * px
            fillRect(context, x: fx - px, y: fy - px, w: 3*px, h: 3*px, color: "#FDE68A", opacity: 0.2)
            fillRect(context, x: fx, y: fy, w: px, h: px, color: "#FDE68A", opacity: 0.7)
        }
    }

    // MARK: - Helper

    private func fillRect(_ context: GraphicsContext, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, color: String, opacity: Double = 1.0) {
        context.fill(Path(CGRect(x: x, y: y, width: w, height: h)), with: .color(Color(hex: color).opacity(opacity)))
    }
}

// MARK: - Bresenham Pixel Calorie Ring

struct PixelCalorieRing: View {
    let progress: Double
    let calories: Int
    var filledColor: Color = DesignSystem.Colors.primary
    var emptyColor: Color = Color(hex: "#E5E7EB")
    var textColor: Color = DesignSystem.Colors.textPrimary
    var labelColor: Color = DesignSystem.Colors.textSecondary

    private let gridSize = 15
    private let pixelSize: CGFloat = 14
    private let radius = 7

    var body: some View {
        ZStack {
            Canvas { context, size in
                let pixels = bresenhamCircle(radius: radius)
                let sorted = sortClockwise(pixels)
                let fillCount = Int((progress * Double(sorted.count)).rounded())

                for (index, point) in sorted.enumerated() {
                    let x = CGFloat(point.0 + radius) * pixelSize
                    let y = CGFloat(point.1 + radius) * pixelSize
                    let rect = CGRect(x: x, y: y, width: pixelSize, height: pixelSize)
                    let color: Color = index < fillCount ? filledColor : emptyColor
                    context.fill(Path(rect), with: .color(color))
                }
            }
            .frame(width: 210, height: 210)

            VStack(spacing: 10) {
                Text("\(calories)")
                    .font(AppFont.regular(30))
                    .foregroundColor(textColor)
                    .tracking(1)
                Text("Calories")
                    .font(AppFont.regular(13))
                    .foregroundColor(labelColor)
            }
        }
    }

    private func bresenhamCircle(radius: Int) -> [(Int, Int)] {
        var pts: [(Int, Int)] = []
        var seen = Set<String>()
        var x = 0
        var y = radius
        var d = 1 - radius

        func plot(_ px: Int, _ py: Int) {
            let key = "\(px),\(py)"
            if !seen.contains(key) {
                seen.insert(key)
                pts.append((px, py))
            }
        }

        while y >= x {
            plot(x, y); plot(-x, y); plot(x, -y); plot(-x, -y)
            plot(y, x); plot(-y, x); plot(y, -x); plot(-y, -x)
            if d < 0 {
                d += 2 * x + 3
            } else {
                d += 2 * (x - y) + 5
                y -= 1
            }
            x += 1
        }
        return pts
    }

    private func sortClockwise(_ pts: [(Int, Int)]) -> [(Int, Int)] {
        pts.sorted { a, b in
            let angleA = atan2(Double(a.0), Double(-a.1))
            let angleB = atan2(Double(b.0), Double(-b.1))
            let normA = angleA < 0 ? angleA + 2 * .pi : angleA
            let normB = angleB < 0 ? angleB + 2 * .pi : angleB
            return normA < normB
        }
    }
}

// MARK: - Purity Vertical Bar

struct PurityVerticalBar: View {
    let score: Int
    var borderColor: Color = DesignSystem.Colors.primary
    var trackColor: Color = Color(hex: "#E5E7EB")
    var band1: Color = Color(hex: "#DC2626")
    var band2: Color = Color(hex: "#EA580C")
    var band3: Color = Color(hex: "#84CC16")
    var band4: Color = Color(hex: "#059669")
    var labelColor: Color = DesignSystem.Colors.textSecondary
    var valueColor: Color = DesignSystem.Colors.textPrimary

    var body: some View {
        VStack(spacing: 8) {
            Text("Purity")
                .font(AppFont.regular(13))
                .foregroundColor(labelColor)
                .multilineTextAlignment(.center)
            Text("Score")
                .font(AppFont.regular(13))
                .foregroundColor(labelColor)
                .multilineTextAlignment(.center)

            ZStack {
                AdaptivePillShapeStyle()
                    .fill(borderColor)
                AdaptivePillShapeStyle()
                    .fill(trackColor)
                    .padding(2)
                GeometryReader { geo in
                    VStack(spacing: 0) {
                        Spacer()
                        let fillHeight = geo.size.height * min(CGFloat(score) / 100.0, 1.0)
                        LinearGradient(
                            stops: [
                                .init(color: band1, location: 0),
                                .init(color: band1, location: 0.35),
                                .init(color: band2, location: 0.35),
                                .init(color: band2, location: 0.65),
                                .init(color: band3, location: 0.65),
                                .init(color: band3, location: 0.90),
                                .init(color: band4, location: 0.90),
                                .init(color: band4, location: 1.0),
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                        .frame(height: geo.size.height)
                        .frame(height: fillHeight, alignment: .bottom)
                        .clipped()
                    }
                }
                .padding(2)
                .clipShape(AdaptivePillShapeStyle())
            }
            .frame(width: 24, height: 150)

            Text("\(score)")
                .font(AppFont.bold(22))
                .foregroundColor(valueColor)
        }
    }
}

// MARK: - Wooden Board Background

struct WoodenBoardBackground: View {
    var style: ThemeColors.QuestBoardStyle = .wood

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height

            switch style {
            case .wood:
                drawWood(context, w: w, h: h)
            case .crystal:
                drawCrystal(context, w: w, h: h)
            }
        }
        .drawingGroup()
    }

    private func drawWood(_ context: GraphicsContext, w: CGFloat, h: CGFloat) {
        // Outer frame
        context.fill(Path(CGRect(origin: .zero, size: CGSize(width: w, height: h))), with: .color(DesignSystem.Colors.woodDark))
        // Inner frame
        context.fill(Path(CGRect(x: 3, y: 3, width: w-6, height: h-6)), with: .color(DesignSystem.Colors.woodMid))
        // Wood fill
        context.fill(Path(CGRect(x: 6, y: 6, width: w-12, height: h-12)), with: .color(DesignSystem.Colors.woodFill))

        // Horizontal plank lines
        let plankCount = 5
        let plankH = (h - 12) / CGFloat(plankCount)
        for i in 0..<plankCount {
            let y = 6 + CGFloat(i) * plankH
            context.fill(Path(CGRect(x: 6, y: y, width: w-12, height: plankH * 0.1)), with: .color(DesignSystem.Colors.woodHighlight))
            context.fill(Path(CGRect(x: 6, y: y + plankH * 0.85, width: w-12, height: plankH * 0.15)), with: .color(DesignSystem.Colors.woodShadow))
            if i > 0 {
                context.fill(Path(CGRect(x: 6, y: y - 1, width: w-12, height: 2)), with: .color(DesignSystem.Colors.woodSeam))
            }
        }

        drawBrackets(context, w: w, h: h, bracketColor: DesignSystem.Colors.woodBracket, nailColor: DesignSystem.Colors.woodNail)
    }

    private func drawCrystal(_ context: GraphicsContext, w: CGFloat, h: CGFloat) {
        let outerFrame = Color(hex: "#0F0E2A")
        let innerFrame = Color(hex: "#1E1B4B")
        let fill = Color(hex: "#292556")
        let highlight = Color(hex: "#312E81")
        let seam = Color(hex: "#1E1B4B")
        let nailGlow = Color(hex: "#4338CA")

        // Outer frame
        context.fill(Path(CGRect(origin: .zero, size: CGSize(width: w, height: h))), with: .color(outerFrame))
        // Inner frame
        context.fill(Path(CGRect(x: 3, y: 3, width: w-6, height: h-6)), with: .color(innerFrame))
        // Crystal fill
        context.fill(Path(CGRect(x: 6, y: 6, width: w-12, height: h-12)), with: .color(fill))

        // Horizontal plank lines (crystal stone)
        let plankCount = 5
        let plankH = (h - 12) / CGFloat(plankCount)
        for i in 0..<plankCount {
            let y = 6 + CGFloat(i) * plankH
            context.fill(Path(CGRect(x: 6, y: y, width: w-12, height: plankH * 0.1)), with: .color(highlight))
            context.fill(Path(CGRect(x: 6, y: y + plankH * 0.85, width: w-12, height: plankH * 0.15)), with: .color(highlight))
            if i > 0 {
                context.fill(Path(CGRect(x: 6, y: y - 1, width: w-12, height: 2)), with: .color(seam))
            }
        }

        drawBrackets(context, w: w, h: h, bracketColor: outerFrame, nailColor: nailGlow)
    }

    private func drawBrackets(_ context: GraphicsContext, w: CGFloat, h: CGFloat, bracketColor: Color, nailColor: Color) {
        let bracketSize: CGFloat = 10
        let nailSize: CGFloat = 3

        // Corner brackets
        context.fill(Path(CGRect(x: 3, y: 3, width: bracketSize, height: 3)), with: .color(bracketColor))
        context.fill(Path(CGRect(x: 3, y: 3, width: 3, height: bracketSize)), with: .color(bracketColor))
        context.fill(Path(CGRect(x: w - 3 - bracketSize, y: 3, width: bracketSize, height: 3)), with: .color(bracketColor))
        context.fill(Path(CGRect(x: w - 6, y: 3, width: 3, height: bracketSize)), with: .color(bracketColor))
        context.fill(Path(CGRect(x: 3, y: h - 6, width: bracketSize, height: 3)), with: .color(bracketColor))
        context.fill(Path(CGRect(x: 3, y: h - 3 - bracketSize, width: 3, height: bracketSize)), with: .color(bracketColor))
        context.fill(Path(CGRect(x: w - 3 - bracketSize, y: h - 6, width: bracketSize, height: 3)), with: .color(bracketColor))
        context.fill(Path(CGRect(x: w - 6, y: h - 3 - bracketSize, width: 3, height: bracketSize)), with: .color(bracketColor))

        // Nail pegs
        context.fill(Path(CGRect(x: 8, y: 8, width: nailSize, height: nailSize)), with: .color(nailColor))
        context.fill(Path(CGRect(x: w - 11, y: 8, width: nailSize, height: nailSize)), with: .color(nailColor))
        context.fill(Path(CGRect(x: 8, y: h - 11, width: nailSize, height: nailSize)), with: .color(nailColor))
        context.fill(Path(CGRect(x: w - 11, y: h - 11, width: nailSize, height: nailSize)), with: .color(nailColor))
    }
}

// MARK: - Pixel Bookmark

struct PixelBookmark: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height

            // Base
            context.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(DesignSystem.Colors.bookmarkDark))
            // Mid
            context.fill(Path(CGRect(x: 1, y: 0, width: w-2, height: h-2)), with: .color(DesignSystem.Colors.bookmarkMid))
            // Highlight
            context.fill(Path(CGRect(x: 1, y: 0, width: w-2, height: 4)), with: .color(DesignSystem.Colors.bookmarkLight))
            // V-notch at bottom
            context.fill(Path(CGRect(x: 1, y: h-4, width: 3, height: 4)), with: .color(DesignSystem.Colors.bookmarkDark))
            context.fill(Path(CGRect(x: w-4, y: h-4, width: 3, height: 4)), with: .color(DesignSystem.Colors.bookmarkDark))
            context.fill(Path(CGRect(x: 4, y: h-2, width: 2, height: 2)), with: .color(DesignSystem.Colors.bookmarkDark))
        }
        .frame(width: 10, height: 22)
    }
}

// MARK: - HomeView

struct HomeView: View {

    // MARK: - Properties

    @State private var viewModel: HomeViewModel

    /// Friend leaderboard (Friend System Phase 5): owned here so it loads on its
    /// own async path and renders as a section below the dashboard. Ranking and
    /// fetch logic stay in the view model — never duplicated into HomeViewModel.
    @State private var leaderboardViewModel: LeaderboardViewModel

    @Binding var selectedTab: Int
    /// R3a: drives the push to FriendsView off Home's NavigationStack.
    @State private var showFriends: Bool = false
    @State private var showingPurityScoreInfo: Bool = false
    @State private var settings = SettingsManager.shared
    @State private var showMoodCheck: Bool = false
    /// Daily Spark QTE (D1d) — presented from the Home card; the gate reloads on finish.
    @State private var showSparkQTE: Bool = false
    @State private var sparkPlayedToday: Bool = false
    @State private var currentTheme: TimeOfDayTheme = SettingsManager.shared.activeTheme
    @Environment(\.scenePhase) private var scenePhase
    /// R6b §2: prefer the environment value over `UIAccessibility.isReduceMotionEnabled` — when
    /// on, the Home entrance reveal is skipped and blocks render settled from the first frame.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Flips true on `cleanContent`'s first appear to trigger the one-time staggered entrance
    /// reveal (R6b §2). Never reset, so tab switches on a live TabView don't replay it.
    @State private var hasRevealed = false
    @AppStorage("insightsCardDismissedDate") private var insightsCardDismissedDate: String = ""

    /// Retained to construct the FriendProfileView sheet presented from the
    /// leaderboard section (Friend System Phase 4/5).
    private let coordinator: AppCoordinator

    /// Read-only — gates the leaderboard's guest state and its load trigger so
    /// guests never fetch.
    private let authService: any AuthService

    /// Triggers the existing guest → signup path; forwarded into the pushed
    /// FriendsView (R3a).
    private let onCreateAccount: () -> Void

    /// Whether the clean UI theme is active
    private var isClean: Bool { settings.isCleanUI }

    /// All theme colors resolved from the current theme
    private var tc: ThemeColors {
        settings.isCleanUI ? settings.activeColors : currentTheme.colors
    }

    // MARK: - Quest card colors (theme-aware)

    private var questCardBorder: Color {
        isClean ? tc.primary.opacity(0.06) : (currentTheme == .night ? Color(hex: "#78716C") : DesignSystem.Colors.parchmentBorder)
    }
    private var questCardFill: Color {
        isClean ? tc.cardBackground : (currentTheme == .night ? Color(hex: "#292524") : DesignSystem.Colors.parchmentFill)
    }
    private var questTextColor: Color {
        isClean ? tc.textPrimary : (currentTheme == .night ? Color(hex: "#D6D3D1") : DesignSystem.Colors.parchmentText)
    }
    private var questSecondaryColor: Color {
        isClean ? tc.textSecondary : (currentTheme == .night ? Color(hex: "#A8A29E") : DesignSystem.Colors.parchmentSecondary)
    }
    private var questDoneBorder: Color {
        isClean ? tc.textTertiary : (currentTheme == .night ? Color(hex: "#57534E") : Color(hex: "#8B7040"))
    }
    private var questDoneFill: Color {
        isClean ? tc.cardBackground : (currentTheme == .night ? Color(hex: "#1C1917") : Color(hex: "#ECD9B5"))
    }
    private var questDoneText: Color {
        isClean ? tc.textTertiary : (currentTheme == .night ? Color(hex: "#78716C") : DesignSystem.Colors.parchmentBorder)
    }
    private var xpBadgeBorder: Color {
        isClean ? tc.primary : (currentTheme == .night ? Color(hex: "#7C3AED") : DesignSystem.Colors.goldBorder)
    }
    private var xpBadgeGradient: LinearGradient {
        if isClean {
            return LinearGradient(colors: [tc.xpFillLight, tc.xpFillDark], startPoint: .top, endPoint: .bottom)
        }
        return currentTheme == .night
            ? DesignSystem.Colors.threeBand(light: Color(hex: "#C084FC"), mid: Color(hex: "#A855F7"), dark: Color(hex: "#7C3AED"))
            : DesignSystem.Colors.band3Gold
    }
    private var xpBadgeDoneGradient: LinearGradient {
        if isClean {
            return LinearGradient(colors: [tc.xpFillLight, tc.xpFillDark], startPoint: .top, endPoint: .bottom)
        }
        return currentTheme == .night
            ? DesignSystem.Colors.threeBand(light: Color(hex: "#C084FC"), mid: Color(hex: "#A855F7"), dark: Color(hex: "#7C3AED"))
            : DesignSystem.Colors.threeBand(light: Color(hex: "#FBBF24"), mid: Color(hex: "#D97706"), dark: Color(hex: "#92400E"))
    }

    // MARK: - Initialization

    init(
        coordinator: AppCoordinator,
        selectedTab: Binding<Int>,
        authService: any AuthService = FirebaseAuthService.shared,
        onCreateAccount: @escaping () -> Void = {}
    ) {
        self._viewModel = State(initialValue: HomeViewModel(coordinator: coordinator))
        self._leaderboardViewModel = State(initialValue: LeaderboardViewModel(coordinator: coordinator))
        self.coordinator = coordinator
        self.authService = authService
        self.onCreateAccount = onCreateAccount
        self._selectedTab = selectedTab
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                tc.primaryBackground
                    .ignoresSafeArea()

                if !isClean {
                    PixelLandscapeBackground(theme: currentTheme)
                        .ignoresSafeArea()
                }

                if viewModel.isLoading {
                    loadingView
                } else if let error = viewModel.errorMessage {
                    errorView(error)
                } else {
                    contentView
                }
            }
            .animation(.easeInOut(duration: 0.8), value: currentTheme)
            .toolbar(.hidden, for: .navigationBar)
            // R3a: Friends is a pushed destination off Home (was tab 3).
            .navigationDestination(isPresented: $showFriends) {
                FriendsView(
                    coordinator: coordinator,
                    authService: authService,
                    onCreateAccount: onCreateAccount
                )
            }
            .refreshable {
                // Dashboard and leaderboard refresh concurrently — the dashboard
                // refresh must never wait on the leaderboard's per-friend fetch.
                // Guests skip the leaderboard entirely (it would fetch nothing
                // and surface a false error).
                if authService.isGuest {
                    await viewModel.refresh()
                } else {
                    async let dashboard: Void = viewModel.refresh()
                    async let leaderboard: Void = leaderboardViewModel.refresh()
                    async let duels: Void = viewModel.loadDuels(myUid: authService.currentUserEmail ?? "")
                    _ = await (dashboard, leaderboard, duels)
                }
            }
            .task {
                await viewModel.loadData()
                await viewModel.checkForStreakMilestone()
                await viewModel.loadDailyInsights()
                await viewModel.loadWeeklySummary()
                // TUT-1a: load tutorial state on first appearance (guest guard lives in
                // DataManager ⇒ guests resolve to `.guest`/done and never show anything).
                await viewModel.loadTutorialState()
            }
            // Independent leaderboard load: its own async path so it never delays
            // or fails the dashboard. A plain .task runs exactly once per Home
            // appearance (cancels on disappear) — not on every body recompute.
            .task {
                guard !authService.isGuest else { return }
                async let leaderboard: Void = leaderboardViewModel.refresh()
                async let duels: Void = viewModel.loadDuels(myUid: authService.currentUserEmail ?? "")
                _ = await (leaderboard, duels)
                sparkPlayedToday = (await coordinator.todayQTEState())?.sparkPlayed ?? false
            }
            .sheet(isPresented: $showSparkQTE) {
                SparkQTESheet(coordinator: coordinator, dateKey: QTEDay.dateKey(for: Date())) {
                    Task { sparkPlayedToday = (await coordinator.todayQTEState())?.sparkPlayed ?? false }
                }
            }
            .task(id: "themeAutoRefresh") {
                // Auto-refresh theme every 60s when preference is "auto"
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(60))
                    if settings.themePreference == "auto" {
                        let resolved = TimeOfDayTheme.current()
                        if resolved != currentTheme {
                            currentTheme = resolved
                        }
                    }
                }
            }
            .overlay {
                if viewModel.showXPToast {
                    VStack {
                        XPToastContainer(
                            totalXP: viewModel.xpToastAmount,
                            questCount: viewModel.xpToastQuestCount,
                            isShowing: $viewModel.showXPToast
                        )
                        Spacer()
                    }
                }

                if viewModel.showQuestRollbackToast, let message = viewModel.questRollbackMessage {
                    VStack {
                        QuestRollbackToast(questTitle: message)
                            .padding(.top, 80)
                        Spacer()
                    }
                    .allowsHitTesting(false)
                }

                if viewModel.showMilestoneToast, let milestone = viewModel.pendingMilestone {
                    StreakMilestoneToastContainer(
                        milestone: milestone,
                        isShowing: $viewModel.showMilestoneToast
                    )
                }

                if showMoodCheck {
                    MoodCheckContainer(
                        isPresented: $showMoodCheck,
                        onMoodSelected: { mood in
                            Task {
                                try? await viewModel.coordinator.logMood(mood)
                            }
                        }
                    )
                }

                // TUT-1a: welcome popup — a body-level overlay above all content, dimming
                // whichever content arm is active. `showTutorialPopup` is only ever true
                // once state has loaded AND (!seen && !done), so guests never see it. The
                // greeting name is the cached UserProfile displayName, resolved by the VM
                // (empty ⇒ "Hey there").
                if viewModel.showTutorialPopup {
                    TutorialWelcomePopup(
                        greetingName: viewModel.greetingName,
                        onStart: { Task { await viewModel.startTutorial() } },
                        onSkip: { Task { await viewModel.skipTutorialTapped() } }
                    )
                    .transition(.opacity)
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    checkForMoodPrompt()
                    currentTheme = settings.activeTheme
                    Task {
                        await viewModel.loadData()
                        await viewModel.refreshWeeklyIfNeeded()
                        await viewModel.loadDailyInsights()
                    }
                }
            }
            .onChange(of: settings.themePreference) { _, _ in
                currentTheme = settings.activeTheme
            }
            .onChange(of: selectedTab) { _, newTab in
                if newTab == 0 {
                    Task {
                        await viewModel.loadData()
                        await viewModel.refreshWeeklyIfNeeded()
                        await viewModel.loadDailyInsights()
                    }
                }
            }
        }
    }

    // MARK: - Insights Dismissal

    private var isInsightsCardDismissedToday: Bool {
        let todayString = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
        return insightsCardDismissedDate == todayString
    }

    private func dismissInsightsCard() {
        let todayString = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
        insightsCardDismissedDate = todayString
    }

    // MARK: - Mood Check

    private func checkForMoodPrompt() {
        // Decision 12: while the tutorial welcome popup is visible, the 7pm mood check must
        // not fire (the popup takes precedence on Home).
        guard !viewModel.showTutorialPopup else { return }
        guard settings.dailyMoodCheckEnabled else { return }
        let hour = Calendar.current.component(.hour, from: Date())
        guard hour >= 19 else { return }
        Task {
            let alreadyLogged = try? await viewModel.coordinator.checkIfMoodLoggedToday()
            if alreadyLogged == false {
                await MainActor.run { showMoodCheck = true }
            }
        }
    }

    // MARK: - Subviews

    private var loadingView: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading your progress...")
                .font(AppFont.regular(16))
                .foregroundColor(tc.textSecondary)
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 64, weight: .regular))
                .foregroundStyle(DesignSystem.Colors.danger)

            VStack(spacing: DesignSystem.Spacing.sm) {
                Text("Error Loading Data")
                    .font(AppFont.bold(22))
                    .foregroundColor(tc.textPrimary)
                Text(message)
                    .font(AppFont.regular(14))
                    .foregroundColor(tc.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DesignSystem.Spacing.xl)
            }

            AppButton(title: "Try Again", style: .primary, action: {
                Task { await viewModel.loadData() }
            })
            .padding(.horizontal, DesignSystem.Spacing.xl)
        }
        .padding()
    }

    // MARK: - Main Content

    private var contentView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if isClean {
                    cleanContent(proxy)
                } else {
                    pixelContent
                }
            }
            .scrollIndicators(.hidden)
            // R2 §5: the tab bar is a `.safeAreaInset` on the TabView, which doesn't propagate
            // through this tab's NavigationStack to the ScrollView — reserve the bar's height so
            // bottom content clears the translucent bar (matches ProfileView).
            .contentMargins(.bottom, DesignSystem.Erewhon.tabBarContentHeight + 12, for: .scrollContent)
        }
    }

    // MARK: - Pixel Home Content (byte-identical to pre-R3b, except the TUT-1a insertion)

    /// Pixel-theme dashboard: the section order and bodies are preserved exactly, with ONE
    /// deliberate exception — the pinned First-Quests card (TUT-1a) is inserted at the top
    /// of the card stack. Adding a new self-contained section is permitted here; mutating an
    /// existing pixel widget is not. Rendered only when `!isClean`, so every section takes
    /// its pixel branch.
    private var pixelContent: some View {
        VStack(spacing: 0) {
            Text("Overheal")
                .font(AppFont.serifTitle(32))
                .foregroundColor(tc.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 22)

            VStack(spacing: 14) {
                    // 0. Pinned First-Quests card — renders off the LIVE shared store (TUT-1b amend)
                    // so visibility, N/6 and the current step advance the moment a step completes on
                    // any tab. The VM mirror only refreshed on Home re-appearance. nil/done ⇒ nothing.
                    if let tut = TutorialProgress.shared.state {
                        FirstQuestsCard(state: tut, onSkip: { Task { await viewModel.skipTutorialTapped() } })
                    }

                    // 1. XP / Rank Card
                    xpAndStreakSection

                    // 1a. Daily Spark QTE (D1d) — non-guests mid-duel who haven't played today.
                    sparkQTECard

                    // 1b. Active duels strip (D1c) — non-guests with active duels only.
                    duelStripSection

                    // 2. Today's Nutrition heading
                    sectionLabel("Nutrition")
                        .padding(.top, 8)

                    // 3. Calorie Ring + Purity Bar
                    nutritionTopRow

                    // 4. Macro row
                    macroRow

                    // 5. Action buttons
                    actionButtons

                    // 6-7. Daily Quests section (heading + board). Wrapped so the whole section is
                    // one checkQuests tap target (Decision 5); the inner spacing 14 preserves the
                    // prior inter-item gaps exactly. The beacon (Decision 7) rides the heading below.
                    VStack(spacing: 14) {
                        // 6. Daily Quests heading
                        HStack {
                            sectionLabel("Daily Quests")
                                // TUT-1b checkQuests beacon (Decision 7) — Daily Quests header (pixel arm).
                                // A flat text header — trace it with the small rectangular radius.
                                .questBeacon(TutorialCatalog.checkQuestsId, cornerRadius: DesignSystem.CornerRadius.sm)
                            Spacer()
                            Text(viewModel.questProgressText)
                                .font(AppFont.regular(12))
                                .foregroundColor(tc.textSecondary)
                        }
                        .padding(.top, 8)

                        // 7. Wooden quest board
                        questBoard
                    }
                    // TUT-1b checkQuests detection (Decision 4/5) — section-container tap; child
                    // quest rows keep priority via SwiftUI child-first hit-testing.
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if TutorialProgress.shared.shouldAttempt(TutorialCatalog.checkQuestsId) {
                            Task { _ = try? await coordinator.completeTutorialStep(TutorialCatalog.checkQuestsId) }
                        }
                    }

                    // 8. Today's Meals heading
                    sectionLabel("Today's Meals")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)

                    // 9. Inventory grid
                    inventoryGrid

                    // 10. Weekly Summary heading
                    sectionLabel("Weekly Summary")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)

                    // 11-13. Weekly content
                    weeklyContent

                    // 14. Friend leaderboard (Friend System Phase 5) — the last
                    // block on Home. A LazyVStack of rows (no nested scroll) so
                    // the whole page scrolls as one; loads on its own path so the
                    // dashboard above stays interactive while it fetches.
                    LeaderboardSection(
                        viewModel: leaderboardViewModel,
                        coordinator: coordinator,
                        authService: authService,
                        onAddFriends: { showFriends = true }
                    )
                    .padding(.top, 8)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
    }

    // MARK: - Erewhon (Flat) Home Content — R3b

    /// Anchor id for the Quests jump target (D3).
    private static let questsAnchorID = "erewhon-quests-anchor"

    // R6b §2 — Erewhon entrance reveal tuning (no magic numbers at the call sites).
    private static let entranceDuration: Double = 0.35
    private static let entranceStagger: Double = 0.045
    private static let entranceRise: CGFloat = 8
    private static let entranceBlockCap: Int = 8

    /// R6b §2 — one-time staggered entrance for the flat Home blocks (Erewhon only). Each block
    /// fades in and rises `entranceRise` pt into place; `index` sets the per-block delay, capped
    /// at `entranceBlockCap` so below-the-fold blocks settle together. Reduce Motion renders the
    /// settled state from the first frame (no animation).
    private struct EntranceReveal: ViewModifier {
        let index: Int
        let isRevealed: Bool
        let reduceMotion: Bool

        func body(content: Content) -> some View {
            if reduceMotion {
                content
            } else {
                let delay = Double(min(index, HomeView.entranceBlockCap)) * HomeView.entranceStagger
                content
                    .opacity(isRevealed ? 1 : 0)
                    .offset(y: isRevealed ? 0 : HomeView.entranceRise)
                    .animation(.easeOut(duration: HomeView.entranceDuration).delay(delay), value: isRevealed)
            }
        }
    }

    /// Flat dashboard rebuilt to the committed mockup's `#screen-home`
    /// (design/erewhon/arena.html). Rendered only when `isClean`; pixel uses `pixelContent`.
    private func cleanContent(_ proxy: ScrollViewProxy) -> some View {
        let insightsShown = viewModel.dailyInsights != nil && !isInsightsCardDismissedToday
        return VStack(spacing: 0) {
            Group {
                appHead
                    .padding(.top, 6)
                    .modifier(EntranceReveal(index: 0, isRevealed: hasRevealed, reduceMotion: reduceMotion))

                // Pinned First-Quests card — renders off the LIVE shared store (TUT-1b amend) so
                // visibility, N/6 and the current step advance the moment a step completes on any
                // tab. The VM mirror only refreshed on Home re-appearance. nil/done ⇒ nothing.
                if let tut = TutorialProgress.shared.state {
                    FirstQuestsCard(state: tut, onSkip: { Task { await viewModel.skipTutorialTapped() } })
                        .padding(.top, 18)
                        .modifier(EntranceReveal(index: 0, isRevealed: hasRevealed, reduceMotion: reduceMotion))
                }

                if let summary = viewModel.summary {
                    resourceRow(summary)
                        .padding(.top, 20)
                        .modifier(EntranceReveal(index: 1, isRevealed: hasRevealed, reduceMotion: reduceMotion))
                    calorieHero(summary)
                        .padding(.top, 28)
                        .modifier(EntranceReveal(index: 2, isRevealed: hasRevealed, reduceMotion: reduceMotion))
                }

                jumpCards(proxy)
                    .padding(.top, 18)
                    .modifier(EntranceReveal(index: 3, isRevealed: hasRevealed, reduceMotion: reduceMotion))

                if let summary = viewModel.summary {
                    purityBlock(summary)
                        .padding(.top, 26)
                        .modifier(EntranceReveal(index: 4, isRevealed: hasRevealed, reduceMotion: reduceMotion))
                }

                // Daily Spark (kept) — renders nothing unless a mid-duel non-guest hasn't played.
                sparkQTECard
                    .modifier(EntranceReveal(index: 5, isRevealed: hasRevealed, reduceMotion: reduceMotion))

                // Active duels (kept), recontainerized into the block + sec-head language.
                cleanDuelsBlock
                    .modifier(EntranceReveal(index: 6, isRevealed: hasRevealed, reduceMotion: reduceMotion))
            }

            Group {
                // Nutrition block (macros)
                if let summary = viewModel.summary {
                    VStack(spacing: 0) {
                        secHead("Nutrition", "Macros")
                        macrosCard(summary)
                    }
                    .padding(.top, 30)
                    .modifier(EntranceReveal(index: 7, isRevealed: hasRevealed, reduceMotion: reduceMotion))
                }

                actionsRow
                    .padding(.top, 24)
                    .modifier(EntranceReveal(index: 8, isRevealed: hasRevealed, reduceMotion: reduceMotion))

                // Insights (kept) — position unchanged relative to the quests block.
                if insightsShown, let insights = viewModel.dailyInsights {
                    insightsCard(insights)
                        .padding(.top, 30)
                        .modifier(EntranceReveal(index: 9, isRevealed: hasRevealed, reduceMotion: reduceMotion))
                }

                questsBlockClean
                    .padding(.top, insightsShown ? 16 : 30)
                    .id(Self.questsAnchorID)
                    .modifier(EntranceReveal(index: 10, isRevealed: hasRevealed, reduceMotion: reduceMotion))

                mealsBlockClean
                    .padding(.top, 30)
                    .modifier(EntranceReveal(index: 11, isRevealed: hasRevealed, reduceMotion: reduceMotion))

                VStack(spacing: 0) {
                    secHead("Weekly summary", nil)
                    weeklyContent
                }
                .padding(.top, 30)
                .modifier(EntranceReveal(index: 12, isRevealed: hasRevealed, reduceMotion: reduceMotion))

                LeaderboardSection(
                    viewModel: leaderboardViewModel,
                    coordinator: coordinator,
                    authService: authService,
                    onAddFriends: { showFriends = true }
                )
                .padding(.top, 30)
                .modifier(EntranceReveal(index: 13, isRevealed: hasRevealed, reduceMotion: reduceMotion))
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 24)
        .onAppear { hasRevealed = true }
    }

    // MARK: Flat — shared card treatment + section header

    /// Erewhon surface card: fill + hairline + subtle shadow. `radius` defaults to the
    /// mockup's 14 (`.res`/`.jump`/`.macros`); meal slots pass 16 (`.slot`).
    private func flatCard<Content: View>(
        radius: CGFloat = DesignSystem.Erewhon.buttonRadius,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        content()
            .background(RoundedRectangle(cornerRadius: radius).fill(tc.cardBackground))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(DesignSystem.Erewhon.line, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .shadow(color: DesignSystem.Erewhon.subtleShadow.color,
                    radius: DesignSystem.Erewhon.subtleShadow.radius,
                    x: 0, y: DesignSystem.Erewhon.subtleShadow.y)
    }

    /// Mockup `.sec-head`: title + optional right-aligned meta over a soft hairline.
    private func secHead(_ title: String, _ meta: String?) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(AppFont.display(15))
                    .foregroundColor(tc.textPrimary)
                Spacer()
                if let meta {
                    Text(meta)
                        .font(AppFont.regular(11))
                        .foregroundColor(tc.textTertiary)
                }
            }
            .padding(.bottom, 10)
            Rectangle()
                .fill(DesignSystem.Erewhon.lineSoft)
                .frame(height: 1)
        }
        .padding(.bottom, 14)
    }

    // MARK: Flat — app head + resource row + XP line

    /// Mockup `.app-head`: centered leaf wordmark over a short accent tick.
    private var appHead: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "leaf")
                    .font(AppFont.regular(18))
                    .foregroundColor(tc.primary)
                // R4c: wordmark → display (Bebas), reversing the R3b deviation now that the
                // Tier-B rule (R4 D1) is the standing convention for the flat branch.
                Text("Overheal")
                    .font(AppFont.display(27))
                    .foregroundColor(tc.textPrimary)
            }
            // Accent tick under the wordmark. §1.1 suggested Erewhon.lineSoft, but the HTML
            // (which wins) uses accent @ 0.55 — a lineSoft hairline would be invisible here.
            RoundedRectangle(cornerRadius: 2)
                .fill(tc.primary.opacity(0.55))
                .frame(width: 38, height: 2)
                .padding(.top, 13)
        }
        .frame(maxWidth: .infinity)
    }

    private var resDivider: some View {
        Rectangle().fill(DesignSystem.Erewhon.lineSoft).frame(width: 1)
    }

    private func resChip<V: View>(icon: String, label: String, @ViewBuilder value: () -> V) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(AppFont.regular(18))
                .foregroundColor(tc.textSecondary)
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(AppFont.regular(10))
                    .foregroundColor(tc.textTertiary)
                value()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 13)
        .padding(.horizontal, 14)
    }

    /// R7b §4a: icon-slot overload of `resChip` — identical chip layout, but the leading glyph
    /// is caller-supplied (the Rank chip routes its RankPlaque through here). The 20×20 icon
    /// frame + padding match the `icon: String` sibling so the row stays aligned.
    private func resChip<Icon: View, V: View>(
        @ViewBuilder icon: () -> Icon,
        label: String,
        @ViewBuilder value: () -> V
    ) -> some View {
        HStack(spacing: 10) {
            icon()
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(AppFont.regular(10))
                    .foregroundColor(tc.textTertiary)
                value()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 13)
        .padding(.horizontal, 14)
    }

    /// Mockup `.resource`, R7b §3: Rank | Total XP (the Streak chip moved to the persistent top
    /// bar). R7b §4a: the Rank chip shows the shared RankPlaque instead of an SF glyph.
    private func resourceRow(_ summary: TodaySummary) -> some View {
        flatCard {
            HStack(spacing: 0) {
                resChip(icon: {
                    RankPlaque(rank: summary.currentRankTier.rank, size: 22)
                }, label: "Rank") {
                    Text(summary.currentRankTier.displayName)
                        .font(AppFont.display(17)).foregroundColor(tc.textPrimary)
                }
                resDivider
                resChip(icon: "bolt", label: "Total XP") {
                    Text(summary.totalXP.formatted())
                        .font(AppFont.display(17)).foregroundColor(tc.textPrimary)
                }
            }
        }
    }

    // MARK: Flat — calorie hero + jump cards

    /// Mockup `.hero`: big Bebas calorie numeral (D4 — display's first Erewhon call site).
    private func calorieHero(_ summary: TodaySummary) -> some View {
        let goal = summary.goal.calorieTarget
        let total = summary.totalCalories
        let pct = viewModel.calorieProgressPercentage
        let remaining = max(0, goal - total)
        return VStack(alignment: .leading, spacing: 0) {
            Text("Today's fuel")
                .font(AppFont.display(12))
                .foregroundColor(tc.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 11) {
                Text("\(total)")
                    .font(AppFont.display(76))
                    .foregroundColor(tc.textPrimary)
                    .fixedSize()
                Text("/ \(goal.formatted()) kcal")
                    .font(AppFont.bold(14))
                    .foregroundColor(tc.textSecondary)
            }
            .padding(.top, 5)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(tc.segBackground)
                    Capsule()
                        .fill(LinearGradient(colors: [tc.primaryDark, tc.primary],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * min(max(pct, 0), 1))
                }
            }
            .frame(height: 9)
            .padding(.top, 16)
            HStack(spacing: 5) {
                Text("\(Int((pct * 100).rounded()))%")
                    .font(AppFont.bold(12))
                    .foregroundColor(tc.primary)
                Text("of goal · \(remaining) kcal left")
                    .font(AppFont.regular(12))
                    .foregroundColor(tc.textTertiary)
            }
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Mockup `.hero-jump`: Quests (scrolls to the quests block) + Squad (pushes Friends).
    private func jumpCards(_ proxy: ScrollViewProxy) -> some View {
        let completed = viewModel.completedQuestsCount
        let total = viewModel.totalQuestsCount
        let friendCount = leaderboardViewModel.entries.filter { !$0.isCurrentUser }.count
        let showSquadBadge = !authService.isGuest && viewModel.incomingRequestCount > 0
        return HStack(spacing: 11) {
            jumpCard(
                icon: "list.bullet",
                iconColor: tc.primary,
                title: "Quests",
                subtitle: "\(completed) of \(total) done",
                badge: "\(completed)/\(total)",
                a11y: "Daily quests, \(completed) of \(total) complete",
                action: {
                    withAnimation(DesignSystem.Erewhon.ease(0.5)) {
                        proxy.scrollTo(Self.questsAnchorID, anchor: .top)
                    }
                }
            )
            jumpCard(
                icon: "person.2",
                iconColor: DesignSystem.Erewhon.social,
                title: "Squad",
                subtitle: friendCount > 0 ? "\(friendCount) friend\(friendCount == 1 ? "" : "s")" : "Add friends",
                badge: showSquadBadge ? "\(viewModel.incomingRequestCount)" : nil,
                a11y: "Squad, \(friendCount) friends"
                    + (showSquadBadge ? ", \(viewModel.incomingRequestCount) requests" : ""),
                action: { showFriends = true }
            )
        }
    }

    private func jumpCard(icon: String, iconColor: Color, title: String, subtitle: String,
                          badge: String?, a11y: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            flatCard {
                HStack(spacing: 11) {
                    Image(systemName: icon)
                        .font(AppFont.regular(20))
                        .foregroundColor(iconColor)
                        .frame(width: 22, height: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(AppFont.bold(13))
                            .foregroundColor(tc.textPrimary)
                        Text(subtitle)
                            .font(AppFont.regular(10.5))
                            .foregroundColor(tc.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if let badge {
                        Text(badge)
                            .font(AppFont.bold(13))
                            .foregroundColor(tc.textPrimary)
                    }
                }
                .padding(.vertical, 13)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(a11y)
    }

    // MARK: Flat — purity + macros

    /// Purity band name + chip color, mirroring PurityScoreInfoSheet's toxin-score taxonomy
    /// (lower score = purer). Reuses the app's canonical band language.
    private func purityBand(_ score: Int) -> (name: String, color: Color) {
        switch score {
        case ..<21:  return ("Clean", tc.primary)
        case ..<41:  return ("Good", tc.primaryDark)
        case ..<61:  return ("Moderate", tc.macroBarFat)
        case ..<81:  return ("High", tc.macroBarCarbs)
        default:     return ("Very High", DesignSystem.Colors.danger)
        }
    }

    /// Mockup `.purity`: horizontal bar with the target notch at `target/100` (D1.6).
    private func purityBlock(_ summary: TodaySummary) -> some View {
        let score = summary.dailyToxinScore
        let target = summary.goal.purityTarget
        let band = purityBand(score)
        let fillFrac = min(max(Double(score) / 100.0, 0), 1)
        let notchFrac = min(max(Double(target) / 100.0, 0), 1)
        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text("Purity")
                    .font(AppFont.display(12))
                    .foregroundColor(tc.textPrimary)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("\(score)")
                        .font(AppFont.display(16))
                        .foregroundColor(tc.textPrimary)
                    Text(" / \(target)")
                        .font(AppFont.regular(11))
                        .foregroundColor(tc.textSecondary)
                    Text(band.name)
                        .font(AppFont.bold(11))
                        .foregroundColor(band.color)
                        .padding(.leading, 6)
                }
            }
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(tc.segBackground).frame(height: 8)
                    Capsule().fill(band.color).frame(width: w * fillFrac, height: 8)
                    Rectangle()
                        .fill(tc.textPrimary.opacity(0.38))
                        .frame(width: 2, height: 14)
                        .offset(x: w * notchFrac - 1)
                }
            }
            .frame(height: 8)
        }
    }

    private var macroDivider: some View {
        Rectangle().fill(DesignSystem.Erewhon.lineSoft).frame(width: 1)
    }

    private func macroColumn(label: String, value: Int, target: Int, progress: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 8, height: 8)
                Text(label).font(AppFont.bold(11)).foregroundColor(color)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(value)").font(AppFont.display(30)).foregroundColor(tc.textPrimary)
                Text("/\(target) g").font(AppFont.regular(11)).foregroundColor(tc.textTertiary)
            }
            .padding(.vertical, 9)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(tc.segBackground)
                    Capsule().fill(color).frame(width: geo.size.width * min(max(progress, 0), 1))
                }
            }
            .frame(height: 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 15)
        .padding(.horizontal, 14)
    }

    /// Mockup `.macros`: three colored macro columns in one hairlined surface card.
    private func macrosCard(_ summary: TodaySummary) -> some View {
        flatCard {
            HStack(spacing: 0) {
                macroColumn(
                    label: "Protein", value: Int(summary.totalProtein), target: Int(summary.goal.proteinTarget),
                    progress: summary.goal.proteinTarget > 0 ? summary.totalProtein / summary.goal.proteinTarget : 0,
                    color: tc.macroBarProtein
                )
                macroDivider
                macroColumn(
                    label: "Carbs", value: Int(summary.totalCarbs), target: Int(summary.goal.carbTarget),
                    progress: summary.goal.carbTarget > 0 ? summary.totalCarbs / summary.goal.carbTarget : 0,
                    color: tc.macroBarCarbs
                )
                macroDivider
                macroColumn(
                    label: "Fat", value: Int(summary.totalFat), target: Int(summary.goal.fatTarget),
                    progress: summary.goal.fatTarget > 0 ? summary.totalFat / summary.goal.fatTarget : 0,
                    color: tc.macroBarFat
                )
            }
        }
    }

    // MARK: Flat — actions + quests + meals + duels

    /// Mockup `.actions` (D5): primary "Log food" + ghost "Scan" via AppButton (R2 styling).
    private var actionsRow: some View {
        HStack(spacing: 11) {
            AppButton(title: "Log food", style: .primary,
                      action: { selectedTab = 1 }, icon: "arrow.up.right")
            AppButton(title: "Scan", style: .secondary,
                      action: { viewModel.showQuickScan = true }, icon: "viewfinder")
                // TUT-1b quickLog beacon (Decision 7) — the Home quick-log control (clean arm).
                // AppButton's own radius IS the modifier default (Erewhon.buttonRadius, 14).
                .questBeacon(TutorialCatalog.quickLogId)
        }
        .sheet(isPresented: $viewModel.showQuickScan) {
            QuickScanView(viewModel: viewModel, selectedTab: $selectedTab)
        }
    }

    /// Mockup `.quest` rows under a sec-head. Scroll target for the Quests jump.
    private var questsBlockClean: some View {
        let quests = viewModel.summary?.quests ?? []
        let completed = viewModel.completedQuestsCount
        let total = viewModel.totalQuestsCount
        return VStack(spacing: 0) {
            secHead("Daily quests", "\(completed) / \(total) done")
                // TUT-1b checkQuests beacon (Decision 7) — the Daily Quests header (clean arm).
                // A flat sec-head row — trace it with the small rectangular radius.
                .questBeacon(TutorialCatalog.checkQuestsId, cornerRadius: DesignSystem.CornerRadius.sm)
            if viewModel.allQuestsComplete {
                AllQuestsCompleteView(totalXPFromQuests: viewModel.totalQuestXPEarnedToday)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else if !quests.isEmpty {
                ForEach(Array(quests.enumerated()), id: \.element.id) { index, quest in
                    cleanQuestRowNew(quest, isLast: index == quests.count - 1)
                }
            } else {
                Text("No quests today")
                    .font(AppFont.regular(14))
                    .foregroundColor(tc.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 20)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.allQuestsComplete)
        // TUT-1b checkQuests detection (Decision 4/5) — section-container tap. contentShape makes
        // the whole block tappable; the display-only quest rows carry no gesture to swallow.
        .contentShape(Rectangle())
        .onTapGesture {
            if TutorialProgress.shared.shouldAttempt(TutorialCatalog.checkQuestsId) {
                Task { _ = try? await coordinator.completeTutorialStep(TutorialCatalog.checkQuestsId) }
            }
        }
    }

    private func cleanQuestRowNew(_ quest: DailyQuest, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(quest.isCompleted ? tc.primary : Color.clear)
                    .frame(width: 25, height: 25)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(quest.isCompleted ? tc.primary : DesignSystem.Erewhon.line, lineWidth: 2)
                    )
                    .overlay {
                        if quest.isCompleted {
                            Image(systemName: "checkmark")
                                .font(AppFont.bold(11))
                                .foregroundColor(DesignSystem.Erewhon.onAccent)
                        }
                    }
                VStack(alignment: .leading, spacing: 3) {
                    Text(quest.title)
                        .font(AppFont.bold(14.5))
                        .foregroundColor(quest.isCompleted ? tc.textSecondary : tc.textPrimary)
                        .strikethrough(quest.isCompleted)
                    Text(quest.questDescription)
                        .font(AppFont.regular(12))
                        .foregroundColor(tc.textTertiary)
                }
                Spacer()
                Text("+\(quest.xpReward) XP")
                    .font(AppFont.bold(12))
                    .foregroundColor(quest.isCompleted ? tc.textTertiary : tc.primary)
            }
            .padding(.vertical, 15)
            if !isLast {
                Rectangle().fill(DesignSystem.Erewhon.lineSoft).frame(height: 1)
            }
        }
    }

    /// Mockup `.inv`: 2-column meal grid + a single dashed empty slot that jumps to Food.
    private var mealsBlockClean: some View {
        let entries = viewModel.summary?.entries ?? []
        return VStack(spacing: 0) {
            secHead("Today's meals", "\(entries.count) logged")
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 11), GridItem(.flexible(), spacing: 11)],
                spacing: 11
            ) {
                ForEach(entries) { entry in
                    mealSlot(entry)
                }
                emptyMealSlot
            }
        }
    }

    // MEALROW-1: photo-conditional — split-card face when a photo decodes (photo left,
    // the existing icon/time/name/calories restacked into the right column), else the
    // existing meal slot unchanged.
    @ViewBuilder
    private func mealSlot(_ entry: FoodEntry) -> some View {
        if let photoData = entry.photoData,
           let uiImage = UIImage(data: photoData) {
            flatCard(radius: DesignSystem.CornerRadius.lg) {
                PhotoSplitCard(image: uiImage, cornerRadius: DesignSystem.CornerRadius.lg, height: 116) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Image(systemName: entry.mealType.icon)
                                .font(AppFont.regular(18))
                                .foregroundColor(tc.textSecondary)
                            Spacer()
                            Text(mealTimeString(from: entry.date))
                                .font(AppFont.regular(10))
                                .foregroundColor(tc.textTertiary)
                        }
                        Spacer(minLength: 12)
                        Text(entry.name)
                            .font(AppFont.bold(13.5))
                            .foregroundColor(tc.textPrimary)
                            .lineLimit(2)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(entry.calories)")
                                .font(AppFont.bold(22))
                                .foregroundColor(tc.textPrimary)
                            Text("kcal")
                                .font(AppFont.regular(10))
                                .foregroundColor(tc.textTertiary)
                        }
                        .padding(.top, 7)
                    }
                    .padding(15)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
            }
        } else {
            flatCard(radius: DesignSystem.CornerRadius.lg) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Image(systemName: entry.mealType.icon)
                            .font(AppFont.regular(18))
                            .foregroundColor(tc.textSecondary)
                        Spacer()
                        Text(mealTimeString(from: entry.date))
                            .font(AppFont.regular(10))
                            .foregroundColor(tc.textTertiary)
                    }
                    Spacer(minLength: 12)
                    Text(entry.name)
                        .font(AppFont.bold(13.5))
                        .foregroundColor(tc.textPrimary)
                        .lineLimit(2)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(entry.calories)")
                            .font(AppFont.bold(22))
                            .foregroundColor(tc.textPrimary)
                        Text("kcal")
                            .font(AppFont.regular(10))
                            .foregroundColor(tc.textTertiary)
                    }
                    .padding(.top, 7)
                }
                .padding(15)
                .frame(maxWidth: .infinity, minHeight: 116, alignment: .leading)
            }
        }
    }

    private var emptyMealSlot: some View {
        Button {
            selectedTab = 1
        } label: {
            VStack(spacing: 11) {
                Image(systemName: "plus")
                    .font(AppFont.regular(16))
                    .foregroundColor(tc.textTertiary)
                    .frame(width: 34, height: 34)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(DesignSystem.Erewhon.line, style: StrokeStyle(lineWidth: 1.5, dash: [3]))
                    )
                Text("Empty slot")
                    .font(AppFont.regular(10.5))
                    .foregroundColor(tc.textTertiary)
            }
            .frame(maxWidth: .infinity, minHeight: 116)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                    .stroke(DesignSystem.Erewhon.line, style: StrokeStyle(lineWidth: 1, dash: [4]))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Empty meal slot, add a meal")
    }

    private func mealTimeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    /// Active duels (kept), recontainerized into the block + sec-head language for flat.
    @ViewBuilder
    private var cleanDuelsBlock: some View {
        if !viewModel.activeDuels.isEmpty {
            VStack(spacing: 0) {
                secHead("Active duels", "\(viewModel.activeDuels.count) live")
                VStack(spacing: 11) {
                    ForEach(viewModel.activeDuels) { duel in
                        duelStripCard(duel)
                    }
                }
            }
            .padding(.top, 26)
        }
    }

    // MARK: - Active Duels Strip (D1c)

    @ViewBuilder
    private var duelStripSection: some View {
        if !viewModel.activeDuels.isEmpty {
            VStack(spacing: 8) {
                sectionLabel("Active Duels")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                ForEach(viewModel.activeDuels) { duel in
                    duelStripCard(duel)
                }
            }
        }
    }

    // MARK: - Daily Spark QTE (D1d)

    @ViewBuilder
    private var sparkQTECard: some View {
        if !authService.isGuest && !viewModel.activeDuels.isEmpty && !sparkPlayedToday {
            Button { showSparkQTE = true } label: {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Image(systemName: "bolt.fill").foregroundColor(tc.primary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Daily Spark").font(AppFont.bold(14)).foregroundColor(tc.textPrimary)
                        Text("Tap to earn duel points").font(AppFont.regular(12)).foregroundColor(tc.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(AppFont.regular(12)).foregroundColor(tc.textTertiary)
                }
                .padding(DesignSystem.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .adaptiveCard(borderColor: tc.primary.opacity(0.25), fillColor: tc.cardBackground)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
    }

    private func duelStripCard(_ duel: DuelDTO) -> some View {
        let myUid = authService.currentUserEmail ?? ""
        let mine = Int(duel.myScore(myUid).rounded())
        let theirs = Int(duel.theirScore(myUid).rounded())
        let iLead = Int((duel.myScore(myUid) * 10).rounded()) > Int((duel.theirScore(myUid) * 10).rounded())
        let isEndgame = duel.endAt.map { $0.timeIntervalSinceNow < DuelConstants.secondsPerDay } ?? false
        let opponent = duel.opponentLabel(of: myUid)
        return Button {
            DuelUIState.shared.pendingArenaDuelId = duel.id
            selectedTab = 2
        } label: {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: "flag.2.crossed.fill") // TODO: swap for a custom crossed-swords pixel asset
                    .foregroundColor(tc.primary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(opponent).font(AppFont.bold(14)).foregroundColor(tc.textPrimary)
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Text("You \(mine) — \(theirs) \(opponent)")
                            .font(AppFont.regular(12))
                            .foregroundColor(iLead ? tc.primary : tc.textSecondary)
                        if let delta = viewModel.deltaSinceSeen(for: duel, myUid: myUid) {
                            deltaChip(delta, opponent: opponent)
                        }
                    }
                }
                Spacer()
                if let endAt = duel.endAt {
                    Text(endAt, style: .relative)
                        .font(AppFont.regular(11))
                        .foregroundColor(isEndgame ? DesignSystem.Colors.danger : tc.textTertiary)
                }
            }
            .padding(DesignSystem.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .adaptiveCard(borderColor: tc.primary.opacity(0.25), fillColor: tc.cardBackground)
        }
        .buttonStyle(.plain)
    }

    private func deltaChip(_ delta: Double, opponent: String) -> some View {
        let rounded = Int(delta.rounded())
        let sign = rounded >= 0 ? "+" : ""
        return Text("\(opponent) \(sign)\(rounded) since you looked")
            .font(AppFont.bold(10))
            .foregroundColor(tc.primary)
            .padding(.horizontal, DesignSystem.Spacing.sm)
            .padding(.vertical, 2)
            .background(tc.primary.opacity(0.15))
            .clipShape(Capsule())
    }

    // MARK: - XP and Streak Section

    private var xpAndStreakSection: some View {
        rpgHeroCard
    }

    /// RPG mode hero card: flat card with icon pills
    private var rpgHeroCard: some View {
        AdaptiveCard(borderColor: tc.primary, fillColor: tc.cardBackground, isSelected: true) {  // R6c: preserved implicit-selection (review intent later)
            VStack(spacing: 14) {
                if let summary = viewModel.summary {
                    HStack(spacing: 12) {
                        // Rank badge
                        AdaptivePill(borderColor: tc.iconGreen.border, fillGradient: DesignSystem.Colors.threeBand(light: tc.iconGreen.mid, mid: tc.iconGreen.dark, dark: tc.iconGreen.border)) {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 26))
                                .foregroundColor(.white)
                        }
                        .frame(width: 50, height: 50)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(summary.currentRankTier.displayName)
                                .font(AppFont.regular(20))
                                .foregroundColor(tc.textPrimary)
                            Text("Level \(summary.currentLevel)")
                                .font(AppFont.regular(13))
                                .foregroundColor(tc.textSecondary)
                        }

                        Spacer()

                        // Streak pill
                        AdaptivePill(borderColor: tc.iconOrange.border, fillGradient: DesignSystem.Colors.threeBand(light: tc.iconOrange.light, mid: tc.iconOrange.mid, dark: tc.iconOrange.dark)) {
                            HStack(spacing: 6) {
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.white)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(summary.currentStreak)")
                                        .font(AppFont.bold(16))
                                        .foregroundColor(.white)
                                    Text("days")
                                        .font(AppFont.regular(11))
                                        .foregroundColor(.white.opacity(0.85))
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                        .fixedSize()
                    }

                    // XP Progress
                    VStack(spacing: 8) {
                        HStack {
                            Text("XP Progress")
                                .font(AppFont.regular(13))
                                .foregroundColor(tc.textSecondary)
                            Spacer()
                            Text("\(summary.xpForNextLevel) XP to next level")
                                .font(AppFont.regular(11))
                                .foregroundColor(tc.textTertiary)
                        }

                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(tc.xpTrackBackground)
                                .frame(height: 10)
                                .overlay(
                                    Rectangle()
                                        .stroke(tc.xpTrackBorder, lineWidth: 2)
                                )

                            GeometryReader { geo in
                                LinearGradient(
                                    stops: [
                                        .init(color: tc.xpFillLight, location: 0),
                                        .init(color: tc.xpFillLight, location: 0.5),
                                        .init(color: tc.xpFillDark, location: 0.5),
                                        .init(color: tc.xpFillDark, location: 1.0)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                .frame(width: geo.size.width * viewModel.levelProgressPercentage, height: 10)
                            }
                            .frame(height: 10)
                        }
                        .frame(height: 10)
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Nutrition Top Row (Ring + Purity)

    private var nutritionTopRow: some View {
        HStack(spacing: 12) {
            // Calorie ring (2.4fr)
            AdaptiveCard(borderColor: tc.primary, fillColor: tc.cardBackground, isSelected: true) {  // R6c: preserved implicit-selection (review intent later)
                PixelCalorieRing(
                    progress: viewModel.calorieProgressPercentage,
                    calories: viewModel.summary?.totalCalories ?? 0,
                    filledColor: tc.ringFilled,
                    emptyColor: tc.ringEmpty,
                    textColor: tc.textPrimary,
                    labelColor: tc.textSecondary
                )
                .padding(14)
            }
            .frame(height: 240)

            // Purity bar (1fr)
            AdaptiveCard(borderColor: tc.primary, fillColor: tc.cardBackground, isSelected: true) {  // R6c: preserved implicit-selection (review intent later)
                PurityVerticalBar(
                    score: viewModel.summary?.dailyToxinScore ?? 0,
                    borderColor: tc.primary,
                    trackColor: tc.ringEmpty,
                    band1: tc.purityBand1,
                    band2: tc.purityBand2,
                    band3: tc.purityBand3,
                    band4: tc.purityBand4,
                    labelColor: tc.textSecondary,
                    valueColor: tc.textPrimary
                )
                    .padding(.vertical, 10)
                    .padding(.horizontal, 6)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 240)
        }
        .sheet(isPresented: $showingPurityScoreInfo) {
            PurityScoreInfoSheet()
        }
    }

    // MARK: - Macro Row

    private var macroRow: some View {
        HStack(spacing: 8) {
            if let summary = viewModel.summary {
                rpgMacroCard(
                    icon: "leaf.fill", label: "Protein",
                    value: "\(Int(summary.totalProtein))g",
                    progress: summary.goal.proteinTarget > 0 ? summary.totalProtein / summary.goal.proteinTarget : 0,
                    progressColor: tc.macroBarProtein,
                    iconGradient: DesignSystem.Colors.threeBand(light: tc.iconGreen.light, mid: tc.iconGreen.mid, dark: tc.iconGreen.dark)
                )
                rpgMacroCard(
                    icon: "flame.fill", label: "Carbs",
                    value: "\(Int(summary.totalCarbs))g",
                    progress: summary.goal.carbTarget > 0 ? summary.totalCarbs / summary.goal.carbTarget : 0,
                    progressColor: tc.macroBarCarbs,
                    iconGradient: DesignSystem.Colors.threeBand(light: tc.iconOrange.light, mid: tc.iconOrange.mid, dark: tc.iconOrange.dark)
                )
                rpgMacroCard(
                    icon: "drop.fill", label: "Fat",
                    value: "\(Int(summary.totalFat))g",
                    progress: summary.goal.fatTarget > 0 ? summary.totalFat / summary.goal.fatTarget : 0,
                    progressColor: tc.macroBarFat,
                    iconGradient: DesignSystem.Colors.threeBand(light: tc.iconAmber.light, mid: tc.iconAmber.mid, dark: tc.iconAmber.dark)
                )
            }
        }
    }

    /// RPG mode macro card with icon pill and progress bar
    private func rpgMacroCard(icon: String, label: String, value: String, progress: Double, progressColor: Color, iconGradient: LinearGradient) -> some View {
        AdaptiveCard(borderColor: tc.primary, fillColor: tc.cardBackground, isSelected: true) {  // R6c: preserved implicit-selection (review intent later)
            VStack(spacing: 0) {
                AdaptivePill(borderColor: tc.primary, fillGradient: iconGradient, isSelected: true) {  // R6c: preserved implicit-selection (review intent later)
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                }
                .frame(width: 34, height: 34)

                Text(label)
                    .font(AppFont.regular(13))
                    .foregroundColor(tc.textSecondary)
                    .padding(.top, 8)

                Text(value)
                    .font(AppFont.bold(22))
                    .foregroundColor(tc.textPrimary)
                    .padding(.top, 6)
                    .padding(.bottom, 10)

                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(tc.macroBarTrack)
                        .frame(height: 4)
                    GeometryReader { geo in
                        Rectangle()
                            .fill(progressColor)
                            .frame(width: geo.size.width * min(max(progress, 0), 1), height: 4)
                    }
                    .frame(height: 4)
                }
            }
            .padding(12)
        }
    }

    // MARK: - Section Label

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(AppFont.bold(22))
            .foregroundColor(tc.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 8) {
            // Log Food button
            Button {
                selectedTab = 1
            } label: {
                AdaptiveCard(borderColor: tc.buttonBorder, fillGradient: DesignSystem.Colors.threeBand(light: tc.buttonLight, mid: tc.buttonMid, dark: tc.buttonDark)) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.white)
                        Text("Log Food")
                            .font(AppFont.bold(16))
                            .foregroundColor(.white)
                    }
                }
                .frame(height: 54)
            }

            // Scan button
            Button {
                viewModel.showQuickScan = true
            } label: {
                AdaptiveCard(borderColor: tc.buttonBorder, fillGradient: DesignSystem.Colors.threeBand(light: tc.buttonLight, mid: tc.buttonMid, dark: tc.buttonDark)) {
                    VStack(spacing: 4) {
                        Image(systemName: "barcode.viewfinder")
                            .font(.system(size: 22))
                            .foregroundColor(.white)
                        Text("Scan")
                            .font(AppFont.regular(11))
                            .foregroundColor(.white)
                    }
                }
                .frame(width: 80, height: 54)
            }
            // TUT-1b quickLog beacon (Decision 7) — the Home quick-log control (pixel arm).
            // The pixel Scan button is a stepped AdaptiveCard tile — trace it near-square.
            .questBeacon(TutorialCatalog.quickLogId, cornerRadius: DesignSystem.CornerRadius.sm)
        }
        .sheet(isPresented: $viewModel.showQuickScan) {
            QuickScanView(viewModel: viewModel, selectedTab: $selectedTab)
        }
    }

    // MARK: - Quest Board

    private var questBoard: some View {
        ZStack {
            WoodenBoardBackground(style: tc.questBoardStyle)
                .clipShape(PixelCardShape(step: 4, steps: 4))

            VStack(spacing: 10) {
                // Insights card (inside board)
                if let insights = viewModel.dailyInsights, !isInsightsCardDismissedToday {
                    insightsCard(insights)
                }

                // Quest cards
                if viewModel.allQuestsComplete {
                    AllQuestsCompleteView(totalXPFromQuests: viewModel.totalQuestXPEarnedToday)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                } else if let quests = viewModel.summary?.quests, !quests.isEmpty {
                    ForEach(quests, id: \.id) { quest in
                        questRow(quest)
                    }
                } else {
                    Text("No quests today")
                        .font(AppFont.regular(14))
                        .foregroundColor(questSecondaryColor)
                        .padding(.vertical, 20)
                }
            }
            .padding(18)
        }
        .padding(.top, 14)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.allQuestsComplete)
    }

    private func insightsCard(_ insights: DailyInsights) -> some View {
        let insightAccent = currentTheme == .night ? Color(hex: "#A855F7") : Color(hex: "#C2410C")
        let dismissBtnColors = currentTheme == .night
            ? (border: Color(hex: "#57534E"), light: Color(hex: "#78716C"), mid: Color(hex: "#57534E"), dark: Color(hex: "#44403C"))
            : (border: DesignSystem.Colors.parchmentBorder, light: Color(hex: "#D4B488"), mid: Color(hex: "#A0845C"), dark: Color(hex: "#6B5530"))

        return AdaptiveCard(borderColor: insightAccent, fillColor: questCardFill) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 22))
                        .foregroundColor(insightAccent)
                    Text("Today's Insights")
                        .font(AppFont.regular(18))
                        .foregroundColor(questTextColor)
                    Spacer()
                    Button {
                        dismissInsightsCard()
                    } label: {
                        AdaptivePill(borderColor: isClean ? .clear : dismissBtnColors.border, fillGradient: DesignSystem.Colors.adaptiveGradient(light: dismissBtnColors.light, mid: dismissBtnColors.mid, dark: dismissBtnColors.dark)) {
                            Text("\u{00D7}")
                                .font(.system(size: 14))
                                .foregroundColor(isClean ? tc.textSecondary : .white)
                        }
                        .frame(width: 28, height: 28)
                    }
                }

                Text(insights.insightMessage)
                    .font(AppFont.regular(14))
                    .foregroundColor(questSecondaryColor)

                HStack(spacing: 24) {
                    HStack(spacing: 8) {
                        Image(systemName: "fork.knife")
                            .font(.system(size: 20))
                            .foregroundColor(insightAccent)
                        Text("\(insights.mealCount)")
                            .font(AppFont.bold(18))
                            .foregroundColor(questTextColor)
                        Text("meals")
                            .font(AppFont.regular(12))
                            .foregroundColor(questSecondaryColor)
                    }

                    HStack(spacing: 8) {
                        Circle()
                            .stroke(insightAccent, lineWidth: 2.5)
                            .frame(width: 20, height: 20)
                        Text("\(Int(insights.proteinProgress * 100))%")
                            .font(AppFont.bold(18))
                            .foregroundColor(questTextColor)
                        Text("protein")
                            .font(AppFont.regular(12))
                            .foregroundColor(questSecondaryColor)
                    }
                }
            }
            .padding(14)
        }
    }

    private func questRow(_ quest: DailyQuest) -> some View {
        rpgQuestRow(quest)
    }

    /// RPG mode quest row: pixel cards with bookmarks
    @ViewBuilder
    private func rpgQuestRow(_ quest: DailyQuest) -> some View {
        let checkBorder = currentTheme == .night
            ? (done: Color(hex: "#44403C"), open: Color(hex: "#78716C"))
            : (done: Color(hex: "#6B5530"), open: DesignSystem.Colors.parchmentBorder)
        let checkFillOpen = currentTheme == .night ? Color(hex: "#1C1917") : Color(hex: "#EDE0C8")
        let checkGradDone = currentTheme == .night
                ? DesignSystem.Colors.threeBand(light: Color(hex: "#78716C"), mid: Color(hex: "#57534E"), dark: Color(hex: "#44403C"))
                : DesignSystem.Colors.threeBand(light: Color(hex: "#A0845C"), mid: Color(hex: "#8B7040"), dark: Color(hex: "#6B5530"))
        let descDoneColor = currentTheme == .night ? Color(hex: "#78716C") : Color(hex: "#B09870")

        AdaptiveCard(borderColor: quest.isCompleted ? questDoneBorder : questCardBorder,
                  fillColor: quest.isCompleted ? questDoneFill : questCardFill) {
            HStack(spacing: 12) {
                AdaptivePill(
                    borderColor: quest.isCompleted ? checkBorder.done : checkBorder.open,
                    fillColor: quest.isCompleted ? .clear : checkFillOpen,
                    fillGradient: quest.isCompleted ? checkGradDone : nil
                ) {
                    if quest.isCompleted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    } else {
                        Circle()
                            .stroke(questCardBorder, lineWidth: 2)
                            .frame(width: 16, height: 16)
                    }
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 6) {
                    Text(quest.title)
                        .font(AppFont.regular(16))
                        .foregroundColor(quest.isCompleted ? questDoneText : questTextColor)
                        .strikethrough(quest.isCompleted)
                    Text(quest.questDescription)
                        .font(AppFont.regular(13))
                        .foregroundColor(quest.isCompleted ? descDoneColor : questSecondaryColor)
                }

                Spacer()

                AdaptivePill(
                    borderColor: xpBadgeBorder,
                    fillGradient: quest.isCompleted ? xpBadgeDoneGradient : xpBadgeGradient,
                    // R6c: preserve retired heuristic — xpBadgeBorder == accent under Erewhon
                    isSelected: isClean
                ) {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 11))
                            .foregroundColor(quest.isCompleted ? .white : questTextColor)
                        Text("+\(quest.xpReward) XP")
                            .font(AppFont.bold(13))
                            .foregroundColor(quest.isCompleted ? .white : questTextColor)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .fixedSize()
            }
            .padding(12)
            .padding(.leading, 8)
            .overlay(alignment: .topLeading) {
                PixelBookmark()
                    .offset(x: 8, y: -2)
                    .opacity(quest.isCompleted ? 0 : 1)
            }
        }
    }

    // MARK: - Inventory Grid

    private var inventoryGrid: some View {
        let entries = viewModel.summary?.entries ?? []
        let remainder = entries.count % 3
        let slotCount = max(6, entries.count + (remainder == 0 ? 0 : 3 - remainder))

        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(0..<slotCount, id: \.self) { index in
                if index < entries.count {
                    filledInventorySlot(entries[index])
                } else {
                    emptyInventorySlot()
                }
            }
        }
    }

    private func filledInventorySlot(_ entry: FoodEntry) -> some View {
        AdaptiveCard(borderColor: tc.invBorderColor, fillColor: tc.cardBackground) {
            VStack(spacing: 0) {
                // Icon area
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let photoData = entry.photoData,
                           let uiImage = UIImage(data: photoData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                        } else {
                            Image(systemName: "fork.knife")
                                .font(.system(size: 24))
                                .foregroundColor(tc.primary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Time badge
                    Text(timeString(from: entry.date))
                        .font(AppFont.regular(9))
                        .foregroundColor(tc.textSecondary)
                        .padding(2)
                        .background(tc.invTimeBg)
                        .padding(4)
                }

                // Divider
                Rectangle()
                    .fill(tc.invBorderColor.opacity(0.2))
                    .frame(height: 2)

                // Label area
                VStack(spacing: 4) {
                    Text(entry.name)
                        .font(AppFont.regular(11))
                        .foregroundColor(tc.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text("\(entry.calories) cal")
                        .font(AppFont.bold(11))
                        .foregroundColor(tc.primary)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
            }
        }
        .aspectRatio(1/1.1, contentMode: .fit)
    }

    private func emptyInventorySlot() -> some View {
        let emptyBorder: Color
        let emptyFill: Color
        let emptyIcon: Color
        let emptyText: Color

        if currentTheme == .night {
            emptyBorder = Color(hex: "#312E81")
            emptyFill = Color(hex: "#1E1B4B").opacity(0.3)
            emptyIcon = Color(hex: "#312E81")
            emptyText = Color(hex: "#6366F1")
        } else {
            emptyBorder = Color(hex: "#D1D5DB")
            emptyFill = Color(hex: "#E5E7EB").opacity(0.3)
            emptyIcon = Color(hex: "#D1D5DB")
            emptyText = Color(hex: "#9CA3AF")
        }

        return AdaptiveCard(borderColor: emptyBorder, fillColor: emptyFill) {
            VStack(spacing: 0) {
                Image(systemName: "plus")
                    .font(.system(size: 24))
                    .foregroundColor(emptyIcon)
                    .opacity(0.3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Rectangle()
                    .fill(Color.black.opacity(0.05))
                    .frame(height: 2)

                VStack(spacing: 4) {
                    Text("Empty")
                        .font(AppFont.regular(11))
                        .foregroundColor(emptyText)
                    Text("\u{2014}")
                        .font(AppFont.regular(11))
                        .foregroundColor(emptyText)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
            }
        }
        .aspectRatio(1/1.1, contentMode: .fit)
    }

    // MARK: - Weekly Content

    private var weeklyContent: some View {
        Group {
            if viewModel.isLoadingWeekly {
                VStack(spacing: DesignSystem.Spacing.md) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Loading weekly data...")
                        .font(AppFont.regular(14))
                        .foregroundColor(tc.textSecondary)
                }
                .frame(minHeight: 300)
            } else if let weeklySummary = viewModel.weeklySummary {
                WeeklySummaryView(summary: weeklySummary, theme: currentTheme)
            } else {
                EmptyStateView(
                    icon: "calendar",
                    title: "No Weekly Data",
                    message: "Log some meals to see your weekly summary!"
                )
                .frame(minHeight: 300)
            }
        }
    }

    // MARK: - Helpers

    private func toxinScoreColor(_ score: Int, target: Int) -> Color {
        if score <= target {
            return DesignSystem.Colors.primary
        } else if Double(score) <= Double(target) * 1.5 {
            return DesignSystem.Colors.warning
        } else {
            return DesignSystem.Colors.danger
        }
    }

    private func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Preview

#Preview("Home View - With Data") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: FoodEntry.self, DailyGoal.self, UserProgress.self, DailyQuest.self, configurations: config)
    let context = container.mainContext

    let sampleEntry = FoodEntry(
        name: "Grilled Chicken Salad",
        date: Date(),
        calories: 450,
        protein: 42.0,
        carbs: 25.0,
        fat: 18.0,
        toxinScore: 15
    )

    let sampleGoal = DailyGoal(
        date: Date(),
        calorieTarget: 2000,
        proteinTarget: 150.0,
        carbTarget: 200.0,
        fatTarget: 65.0,
        purityTarget: 30
    )

    let sampleProgress = UserProgress(
        totalXP: 350,
        currentStreak: 7,
        longestStreak: 12,
        lastActiveDate: Date()
    )

    context.insert(sampleEntry)
    context.insert(sampleGoal)
    context.insert(sampleProgress)

    let coordinator = AppCoordinator(modelContext: context)

    return HomeView(coordinator: coordinator, selectedTab: .constant(0))
}

// MARK: - Quick Scan View

/// Quick scan view for fast barcode scanning from home screen
struct QuickScanView: View {

    @Bindable var viewModel: HomeViewModel
    @Binding var selectedTab: Int
    @Environment(\.dismiss) private var dismiss

    @State private var showManualEntry = false
    @State private var showScanner = false
    @State private var manualBarcodeInput = ""
    @State private var isLoadingBarcode = false
    @State private var barcodeError: String?
    @State private var scannedNutrition: FoodNutrition?
    @State private var showAddFoodForm = false

    private var tc: ThemeColors { SettingsManager.shared.activeColors }

    var body: some View {
        NavigationStack {
            VStack(spacing: DesignSystem.Spacing.xl) {
                // Icon
                ZStack {
                    Circle()
                        .fill(tc.primary.opacity(0.15))
                        .frame(width: 100, height: 100)

                    Image(systemName: "barcode.viewfinder")
                        .font(.system(size: 50, weight: .semibold))
                        .foregroundColor(tc.primary)
                }
                .padding(.top, DesignSystem.Spacing.xxl)

                // Title and description
                VStack(spacing: DesignSystem.Spacing.sm) {
                    Text("Quick Scan")
                        .font(.system(size: DesignSystem.FontSizes.title, weight: .bold))
                        .foregroundColor(tc.textPrimary)

                    Text("Scan a barcode or enter manually to quickly log packaged foods")
                        .font(.system(size: DesignSystem.FontSizes.callout, weight: .regular))
                        .foregroundColor(tc.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DesignSystem.Spacing.xl)
                }

                Spacer()

                // Action buttons
                VStack(spacing: DesignSystem.Spacing.md) {
                    AppButton(
                        title: "Scan with Camera",
                        style: .primary,
                        action: {
                            showScanner = true
                        },
                        icon: "camera.fill"
                    )

                    AppButton(
                        title: "Enter Barcode Manually",
                        style: .secondary,
                        action: {
                            showManualEntry = true
                        },
                        icon: "keyboard"
                    )

                    Button {
                        dismiss()
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(tc.textSecondary)
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.xl)
                .padding(.bottom, DesignSystem.Spacing.xl)
            }
            .background(tc.primaryBackground)
            .navigationTitle("Quick Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .fullScreenCover(isPresented: $showScanner) {
                BarcodeScannerView { barcode in
                    dismiss()
                    selectedTab = 1
                }
            }
            .sheet(isPresented: $showManualEntry) {
                QuickScanManualEntryView(
                    manualBarcodeInput: $manualBarcodeInput,
                    isLoadingBarcode: $isLoadingBarcode,
                    barcodeError: $barcodeError,
                    onBarcodeSubmit: { barcode in
                        Task {
                            await handleBarcodeSubmit(barcode)
                        }
                    },
                    onDismiss: {
                        showManualEntry = false
                    }
                )
            }
            .sheet(isPresented: $showAddFoodForm) {
                if let nutrition = scannedNutrition {
                    QuickScanAddFoodView(
                        nutrition: nutrition,
                        barcode: manualBarcodeInput,
                        coordinator: viewModel.coordinator,
                        onComplete: {
                            scannedNutrition = nil
                            manualBarcodeInput = ""
                            showAddFoodForm = false
                            dismiss()
                        },
                        onCancel: {
                            showAddFoodForm = false
                        }
                    )
                }
            }
        }
    }

    private func handleBarcodeSubmit(_ barcode: String) async {
        isLoadingBarcode = true
        barcodeError = nil

        let barcodeService = BarcodeService()

        do {
            let nutrition = try await barcodeService.fetchNutrition(barcode: barcode)
            await MainActor.run {
                scannedNutrition = nutrition
                isLoadingBarcode = false
                showManualEntry = false
                showAddFoodForm = true
            }
        } catch let error as BarcodeError {
            await MainActor.run {
                barcodeError = error.localizedDescription
                isLoadingBarcode = false
            }
        } catch {
            await MainActor.run {
                barcodeError = "Failed to fetch product data. Please try again."
                isLoadingBarcode = false
            }
        }
    }
}

// MARK: - Quick Scan Manual Entry View

struct QuickScanManualEntryView: View {

    @Binding var manualBarcodeInput: String
    @Binding var isLoadingBarcode: Bool
    @Binding var barcodeError: String?
    let onBarcodeSubmit: (String) -> Void
    let onDismiss: () -> Void

    @FocusState private var isFocused: Bool

    private var tc: ThemeColors { SettingsManager.shared.activeColors }

    var body: some View {
        NavigationStack {
            VStack(spacing: DesignSystem.Spacing.xl) {
                ZStack {
                    Circle()
                        .fill(tc.primary.opacity(0.15))
                        .frame(width: 80, height: 80)

                    Image(systemName: "keyboard")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundColor(tc.primary)
                }
                .padding(.top, DesignSystem.Spacing.xl)

                VStack(spacing: DesignSystem.Spacing.sm) {
                    Text("Enter Barcode Number")
                        .font(.system(size: DesignSystem.FontSizes.title2, weight: .semibold))
                        .foregroundColor(tc.textPrimary)

                    Text("Enter the UPC or EAN barcode from the product packaging")
                        .font(.system(size: DesignSystem.FontSizes.callout, weight: .regular))
                        .foregroundColor(tc.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DesignSystem.Spacing.xl)
                }

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    TextField("e.g., 737628064502", text: $manualBarcodeInput)
                        .font(.system(size: DesignSystem.FontSizes.body, weight: .regular))
                        .keyboardType(.numberPad)
                        .textFieldStyle(.plain)
                        .padding(DesignSystem.Spacing.md)
                        .background(tc.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                                .strokeBorder(tc.primary.opacity(0.3), lineWidth: 1)
                        )
                        .focused($isFocused)

                    Text("Note: Nutrition shown is per 100g, not per serving")
                        .font(.system(size: DesignSystem.FontSizes.caption, weight: .regular))
                        .foregroundColor(DesignSystem.Colors.warning)
                        .padding(.top, DesignSystem.Spacing.sm)

                    if let error = barcodeError {
                        HStack(spacing: DesignSystem.Spacing.xs) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(DesignSystem.Colors.danger)

                            Text(error)
                                .font(.system(size: DesignSystem.FontSizes.caption, weight: .regular))
                                .foregroundColor(DesignSystem.Colors.danger)
                        }
                        .padding(.top, DesignSystem.Spacing.xs)
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.xl)

                Spacer()

                VStack(spacing: DesignSystem.Spacing.md) {
                    AppButton(
                        title: "Look Up Nutrition",
                        style: .primary,
                        action: {
                            let barcode = manualBarcodeInput.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !barcode.isEmpty else { return }
                            onBarcodeSubmit(barcode)
                        },
                        isLoading: isLoadingBarcode,
                        isDisabled: manualBarcodeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoadingBarcode,
                        icon: "magnifyingglass"
                    )

                    Button {
                        onDismiss()
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(tc.textSecondary)
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.xl)
                .padding(.bottom, DesignSystem.Spacing.xl)
            }
            .background(tc.primaryBackground)
            .navigationTitle("Enter Barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDismiss()
                    }
                }
            }
            .onAppear {
                isFocused = true
            }
        }
    }
}

// MARK: - Quick Scan Add Food View

struct QuickScanAddFoodView: View {

    let nutrition: FoodNutrition
    let barcode: String
    let coordinator: AppCoordinator
    let onComplete: () -> Void
    let onCancel: () -> Void

    @State private var foodName: String = ""
    @State private var calories: String = ""
    @State private var protein: String = ""
    @State private var carbs: String = ""
    @State private var fat: String = ""
    @State private var toxinScore: Double = 30.0
    @State private var servingSize: String = "100"
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var tc: ThemeColors { SettingsManager.shared.activeColors }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.lg) {
                    VStack(spacing: DesignSystem.Spacing.sm) {
                        ZStack {
                            Circle()
                                .fill(tc.primary.opacity(0.15))
                                .frame(width: 80, height: 80)

                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 40, weight: .medium))
                                .foregroundColor(tc.primary)
                        }

                        Text("Product Found!")
                            .font(.system(size: DesignSystem.FontSizes.title2, weight: .bold))
                            .foregroundColor(tc.textPrimary)

                        if let brand = nutrition.brand {
                            Text(brand)
                                .font(.system(size: DesignSystem.FontSizes.footnote, weight: .medium))
                                .foregroundColor(tc.textSecondary)
                        }
                    }
                    .padding(.bottom, DesignSystem.Spacing.md)

                    HStack {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.warning)

                        Text("Values are per 100g - adjust serving size below")
                            .font(.system(size: DesignSystem.FontSizes.caption, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.warning)
                    }
                    .padding(DesignSystem.Spacing.md)
                    .background(DesignSystem.Colors.warning.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm))

                    servingSizeSection

                    inputField(title: "Food Name", text: $foodName, placeholder: "Product name")

                    nutritionInputs

                    toxinScoreSection

                    if let error = errorMessage {
                        Text(error)
                            .font(.system(size: DesignSystem.FontSizes.caption, weight: .regular))
                            .foregroundColor(DesignSystem.Colors.danger)
                    }

                    VStack(spacing: DesignSystem.Spacing.md) {
                        AppButton(
                            title: "Add to Food Log",
                            style: .primary,
                            action: {
                                Task { await saveFood() }
                            },
                            isLoading: isSubmitting,
                            isDisabled: isSubmitting,
                            icon: "checkmark.circle.fill"
                        )

                        Button {
                            onCancel()
                        } label: {
                            Text("Cancel")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundColor(tc.textSecondary)
                        }
                    }
                    .padding(.top, DesignSystem.Spacing.md)
                }
                .padding(DesignSystem.Spacing.lg)
            }
            .background(tc.primaryBackground)
            .navigationTitle("Add Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
            }
            .onAppear {
                foodName = nutrition.name
                calories = String(nutrition.calories)
                protein = String(format: "%.1f", nutrition.protein)
                carbs = String(format: "%.1f", nutrition.carbs)
                fat = String(format: "%.1f", nutrition.fat)
                toxinScore = Double(nutrition.toxinScore)
            }
        }
    }

    private var servingSizeSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Serving Size")
                .font(.system(size: DesignSystem.FontSizes.footnote, weight: .semibold))
                .foregroundColor(tc.textSecondary)

            HStack(spacing: DesignSystem.Spacing.md) {
                TextField("100", text: $servingSize)
                    .font(.system(size: DesignSystem.FontSizes.body, weight: .medium))
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.plain)
                    .padding(DesignSystem.Spacing.md)
                    .background(tc.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                            .strokeBorder(tc.primary.opacity(0.3), lineWidth: 1)
                    )
                    .frame(maxWidth: .infinity)

                Text("grams")
                    .font(.system(size: DesignSystem.FontSizes.callout, weight: .medium))
                    .foregroundColor(tc.textSecondary)

                Button {
                    applyServingSize()
                } label: {
                    Text("Apply")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, DesignSystem.Spacing.md)
                        .padding(.vertical, DesignSystem.Spacing.sm)
                        .background(tc.primary)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm))
                }
            }
        }
    }

    private var nutritionInputs: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            Text("Nutrition Info")
                .font(.system(size: DesignSystem.FontSizes.headline, weight: .semibold))
                .foregroundColor(tc.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            inputField(title: "Calories", text: $calories, placeholder: "0", unit: "cal", keyboardType: .numberPad)
            inputField(title: "Protein", text: $protein, placeholder: "0", unit: "g", keyboardType: .decimalPad)
            inputField(title: "Carbs", text: $carbs, placeholder: "0", unit: "g", keyboardType: .decimalPad)
            inputField(title: "Fat", text: $fat, placeholder: "0", unit: "g", keyboardType: .decimalPad)
        }
    }

    private func inputField(
        title: String, text: Binding<String>, placeholder: String,
        unit: String? = nil, keyboardType: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text(title)
                .font(.system(size: DesignSystem.FontSizes.footnote, weight: .semibold))
                .foregroundColor(tc.textSecondary)

            HStack {
                TextField(placeholder, text: text)
                    .font(.system(size: DesignSystem.FontSizes.body, weight: .regular))
                    .keyboardType(keyboardType)
                    .textFieldStyle(.plain)

                if let unit = unit {
                    Text(unit)
                        .font(.system(size: DesignSystem.FontSizes.footnote, weight: .medium))
                        .foregroundColor(tc.textTertiary)
                }
            }
            .padding(DesignSystem.Spacing.md)
            .background(tc.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                    .strokeBorder(tc.primary.opacity(0.3), lineWidth: 1)
            )
        }
    }

    private var toxinScoreSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack {
                Text("Toxin Score")
                    .font(.system(size: DesignSystem.FontSizes.headline, weight: .semibold))
                    .foregroundColor(tc.textPrimary)

                Spacer()

                Text("\(Int(toxinScore))")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(toxinScoreColor)
            }

            Slider(value: $toxinScore, in: 0...100, step: 1)
                .tint(toxinScoreColor)

            HStack {
                Text("Clean")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(DesignSystem.Colors.primary)

                Spacer()

                Text("Processed")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(DesignSystem.Colors.danger)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(tc.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
    }

    private var toxinScoreColor: Color {
        if toxinScore < 30 {
            return DesignSystem.Colors.primary
        } else if toxinScore < 60 {
            return DesignSystem.Colors.warning
        } else {
            return DesignSystem.Colors.danger
        }
    }

    private func applyServingSize() {
        guard let grams = Double(servingSize), grams > 0 else { return }
        let multiplier = grams / 100.0
        calories = String(Int(Double(nutrition.calories) * multiplier))
        protein = String(format: "%.1f", nutrition.protein * multiplier)
        carbs = String(format: "%.1f", nutrition.carbs * multiplier)
        fat = String(format: "%.1f", nutrition.fat * multiplier)
    }

    private func saveFood() async {
        guard !foodName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Food name is required"
            return
        }

        guard let caloriesInt = Int(calories) else {
            errorMessage = "Invalid calorie value"
            return
        }

        isSubmitting = true
        errorMessage = nil

        do {
            _ = try await coordinator.addFoodEntry(
                name: foodName.trimmingCharacters(in: .whitespacesAndNewlines),
                calories: caloriesInt,
                protein: Double(protein) ?? 0.0,
                carbs: Double(carbs) ?? 0.0,
                fat: Double(fat) ?? 0.0,
                toxinScore: Int(toxinScore),
                photoData: nil,
                barcodeUPC: barcode
            )

            #if os(iOS)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            #endif

            isSubmitting = false
            // TUT-1b quickLog detection (Decision 4/5) — same success path that closes the sheet.
            if TutorialProgress.shared.shouldAttempt(TutorialCatalog.quickLogId) {
                Task { _ = try? await coordinator.completeTutorialStep(TutorialCatalog.quickLogId) }
            }
            onComplete()

        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
            isSubmitting = false
        }
    }
}
