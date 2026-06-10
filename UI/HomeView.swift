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
    @Binding var selectedTab: Int
    @State private var showingPurityScoreInfo: Bool = false
    @State private var settings = SettingsManager.shared
    @State private var showMoodCheck: Bool = false
    @State private var currentTheme: TimeOfDayTheme = SettingsManager.shared.activeTheme
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("insightsCardDismissedDate") private var insightsCardDismissedDate: String = ""

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

    init(coordinator: AppCoordinator, selectedTab: Binding<Int>) {
        self._viewModel = State(initialValue: HomeViewModel(coordinator: coordinator))
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
            .refreshable {
                await viewModel.refresh()
            }
            .task {
                await viewModel.loadData()
                await viewModel.checkForStreakMilestone()
                await viewModel.loadDailyInsights()
                await viewModel.loadWeeklySummary()
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
                .foregroundColor(DesignSystem.Colors.textSecondary)
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
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                Text(message)
                    .font(AppFont.regular(14))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
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
        ScrollView {
            VStack(spacing: 0) {
                // Title
                if isClean {
                    Text("HealthBar")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(tc.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 22)
                } else {
                    Text("HealthBar")
                        .font(AppFont.serifTitle(32))
                        .foregroundColor(tc.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 22)
                }

                VStack(spacing: 14) {
                    // 1. XP / Rank Card
                    xpAndStreakSection

                    // 2. Today's Nutrition heading
                    sectionLabel("Nutrition")
                        .padding(.top, 8)

                    // 3. Calorie Ring + Purity Bar
                    nutritionTopRow

                    // 4. Macro row
                    macroRow

                    // 5. Action buttons
                    actionButtons

                    // 6. Daily Quests heading
                    HStack {
                        sectionLabel("Daily Quests")
                        Spacer()
                        Text(viewModel.questProgressText)
                            .font(isClean ? .system(size: 11, weight: .medium, design: .rounded) : AppFont.regular(12))
                            .foregroundColor(tc.textSecondary)
                    }
                    .padding(.top, 8)

                    // 7. Wooden quest board
                    questBoard

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
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - XP and Streak Section

    private var xpAndStreakSection: some View {
        Group {
            if isClean {
                cleanHeroCard
            } else {
                rpgHeroCard
            }
        }
    }

    /// Clean mode hero card: teal gradient with decorative bubbles
    private var cleanHeroCard: some View {
        ZStack {
            // Gradient background
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color(hex: "#0A6B63"), location: 0),
                            .init(color: Color(hex: "#0D8A7E"), location: 0.5),
                            .init(color: Color(hex: "#11A594"), location: 1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Decorative bubbles
            Circle()
                .fill(Color.white.opacity(0.05))
                .frame(width: 120, height: 120)
                .offset(x: 90, y: -40)

            Circle()
                .fill(Color.white.opacity(0.03))
                .frame(width: 80, height: 80)
                .offset(x: -50, y: 50)

            // Content
            VStack(spacing: 0) {
                if let summary = viewModel.summary {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(summary.currentRank.displayName)
                                .font(.system(size: 20, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                                .tracking(-0.3)
                            Text("Level \(summary.currentLevel)")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.6))
                        }

                        Spacer()

                        // Streak pill
                        HStack(spacing: 5) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 15))
                                .foregroundColor(Color(hex: "#FBBF24"))
                            Text("\(summary.currentStreak)")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            Text("days")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color.black.opacity(0.2))
                        .clipShape(Capsule())
                    }

                    // XP Progress
                    VStack(spacing: 4) {
                        HStack {
                            Text("XP Progress")
                                .font(.system(size: 10, weight: .regular, design: .rounded))
                                .foregroundColor(.white.opacity(0.6))
                            Spacer()
                            Text("\(summary.xpForNextLevel) to next level")
                                .font(.system(size: 10, weight: .regular, design: .rounded))
                                .foregroundColor(.white.opacity(0.35))
                        }

                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.12))
                                .frame(height: 5)
                            GeometryReader { geo in
                                Capsule()
                                    .fill(Color.white.opacity(0.85))
                                    .frame(width: geo.size.width * viewModel.levelProgressPercentage, height: 5)
                            }
                            .frame(height: 5)
                        }
                    }
                    .padding(.top, 14)
                }
            }
            .padding(18)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    /// RPG mode hero card: flat card with icon pills
    private var rpgHeroCard: some View {
        AdaptiveCard(borderColor: tc.primary, fillColor: tc.cardBackground) {
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
                            Text(summary.currentRank.displayName)
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
            if isClean {
                cleanCalorieCard
                    .frame(height: 240)
            } else {
                AdaptiveCard(borderColor: tc.primary, fillColor: tc.cardBackground) {
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
            }

            // Purity bar (1fr)
            if isClean {
                cleanPurityCard
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)
            } else {
                AdaptiveCard(borderColor: tc.primary, fillColor: tc.cardBackground) {
                    PurityVerticalBar(
                        score: viewModel.summary?.totalToxinScore ?? 0,
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
        }
        .sheet(isPresented: $showingPurityScoreInfo) {
            PurityScoreInfoSheet()
        }
    }

    // MARK: - Macro Row

    private var macroRow: some View {
        HStack(spacing: 8) {
            if let summary = viewModel.summary {
                if isClean {
                    cleanMacroCell(
                        label: "Protein",
                        value: "\(Int(summary.totalProtein))g",
                        progress: summary.goal.proteinTarget > 0 ? summary.totalProtein / summary.goal.proteinTarget : 0,
                        dotColor: Color(hex: "#2DD4BF"),
                        labelColor: Color(hex: "#5EEAD4"),
                        valueColor: Color(hex: "#99F6E4"),
                        tintColor: Color(hex: "#0D9488"),
                        barColor: Color(hex: "#14B8A6"),
                        barTrackColor: Color(hex: "#0D9488").opacity(0.15)
                    )
                    cleanMacroCell(
                        label: "Carbs",
                        value: "\(Int(summary.totalCarbs))g",
                        progress: summary.goal.carbTarget > 0 ? summary.totalCarbs / summary.goal.carbTarget : 0,
                        dotColor: Color(hex: "#FBBF24"),
                        labelColor: Color(hex: "#D4A843"),
                        valueColor: Color(hex: "#FDE68A"),
                        tintColor: Color(hex: "#D4A843"),
                        barColor: Color(hex: "#D4A843"),
                        barTrackColor: Color(hex: "#D4A843").opacity(0.12)
                    )
                    cleanMacroCell(
                        label: "Fat",
                        value: "\(Int(summary.totalFat))g",
                        progress: summary.goal.fatTarget > 0 ? summary.totalFat / summary.goal.fatTarget : 0,
                        dotColor: Color(hex: "#E8956E"),
                        labelColor: Color(hex: "#C07A5C"),
                        valueColor: Color(hex: "#FDBA9E"),
                        tintColor: Color(hex: "#C07A5C"),
                        barColor: Color(hex: "#C07A5C"),
                        barTrackColor: Color(hex: "#C07A5C").opacity(0.12)
                    )
                } else {
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
    }

    /// Clean mode macro cell: tinted background, small dot, colored text
    private func cleanMacroCell(label: String, value: String, progress: Double, dotColor: Color, labelColor: Color, valueColor: Color, tintColor: Color, barColor: Color, barTrackColor: Color) -> some View {
        VStack(spacing: 0) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
                .padding(.bottom, 8)

            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(labelColor)

            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(valueColor)
                .tracking(-0.4)
                .padding(.top, 2)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(barTrackColor)
                    .frame(height: 3)
                GeometryReader { geo in
                    Capsule()
                        .fill(barColor)
                        .frame(width: geo.size.width * min(max(progress, 0), 1), height: 3)
                }
                .frame(height: 3)
            }
            .padding(.top, 8)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(tintColor.opacity(settings.isCleanDark ? 0.1 : 0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.04), lineWidth: 0.5)
                )
        )
    }

    /// RPG mode macro card with icon pill and progress bar
    private func rpgMacroCard(icon: String, label: String, value: String, progress: Double, progressColor: Color, iconGradient: LinearGradient) -> some View {
        AdaptiveCard(borderColor: tc.primary, fillColor: tc.cardBackground) {
            VStack(spacing: 0) {
                AdaptivePill(borderColor: tc.primary, fillGradient: iconGradient) {
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

    @ViewBuilder
    private func sectionLabel(_ text: String) -> some View {
        if isClean {
            Text(text.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(tc.textSecondary)
                .tracking(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(text)
                .font(AppFont.bold(22))
                .foregroundColor(tc.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Clean Calorie Card

    private var cleanRingTrackColor: Color {
        settings.isCleanDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }

    private var cleanCalorieCard: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(tc.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(settings.isCleanDark ? Color.white.opacity(0.05) : Color.black.opacity(0.04), lineWidth: 0.5)
            )
            .overlay {
                VStack(spacing: 0) {
                    ZStack {
                        Circle()
                            .stroke(cleanRingTrackColor, lineWidth: 14)
                        Circle()
                            .trim(from: 0, to: viewModel.calorieProgressPercentage)
                            .stroke(
                                LinearGradient(
                                    colors: [Color(hex: "#5EEAD4"), Color(hex: "#0D9488")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                style: StrokeStyle(lineWidth: 14, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .animation(.spring(response: 0.8, dampingFraction: 0.7), value: viewModel.calorieProgressPercentage)

                        VStack(spacing: 2) {
                            Text("\(viewModel.summary?.totalCalories ?? 0)")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundColor(tc.textPrimary)
                                .tracking(-0.5)
                                .contentTransition(.numericText())
                            Text("kcal")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundColor(tc.textSecondary)
                        }
                    }
                    .frame(width: 130, height: 130)

                    Text("of \(viewModel.summary?.goal.calorieTarget.formatted() ?? "2,100") goal")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(tc.textSecondary)
                        .padding(.top, 10)
                }
                .padding(16)
            }
    }

    // MARK: - Clean Purity Card

    private var cleanPurityCard: some View {
        let score = viewModel.summary?.totalToxinScore ?? 0
        let progress = min(CGFloat(score) / 100.0, 1.0)
        let barColor: Color = score < 30 ? Color(hex: "#22C55E") : score < 60 ? Color(hex: "#F97316") : Color(hex: "#EF4444")

        return RoundedRectangle(cornerRadius: 16)
            .fill(tc.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(settings.isCleanDark ? Color.white.opacity(0.05) : Color.black.opacity(0.04), lineWidth: 0.5)
            )
            .overlay {
                VStack(spacing: 6) {
                    Text("PURITY")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(tc.textSecondary)
                        .tracking(0.5)

                    ZStack(alignment: .bottom) {
                        Capsule()
                            .fill(settings.isCleanDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                            .frame(width: 20)

                        GeometryReader { geo in
                            VStack {
                                Spacer()
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [barColor, barColor.opacity(0.7)],
                                            startPoint: .bottom,
                                            endPoint: .top
                                        )
                                    )
                                    .frame(width: 20, height: geo.size.height * progress)
                                    .animation(.spring(response: 0.8, dampingFraction: 0.7), value: score)
                            }
                        }
                        .frame(width: 20)
                    }
                    .frame(height: 100)

                    Text("\(score)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(tc.textPrimary)
                }
                .padding(14)
            }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 8) {
            // Log Food button
            Button {
                selectedTab = 1
            } label: {
                if isClean {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                        Text("Log food")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color(hex: "#0D9488"))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
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
            }

            // Scan button
            Button {
                viewModel.showQuickScan = true
            } label: {
                if isClean {
                    Image(systemName: "barcode.viewfinder")
                        .font(.system(size: 18))
                        .foregroundColor(Color(hex: "#2DD4BF"))
                        .frame(width: 52, height: 48)
                        .background(tc.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                        )
                } else {
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
            }
        }
        .sheet(isPresented: $viewModel.showQuickScan) {
            QuickScanView(viewModel: viewModel, selectedTab: $selectedTab)
        }
    }

    // MARK: - Quest Board

    private var questBoard: some View {
        ZStack {
            if isClean {
                RoundedRectangle(cornerRadius: 16)
                    .fill(tc.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(tc.primary.opacity(settings.isCleanDark ? 0.08 : 0.06), lineWidth: 0.5)
                    )
            } else {
                WoodenBoardBackground(style: tc.questBoardStyle)
                    .clipShape(PixelCardShape(step: 4, steps: 4))
            }

            VStack(spacing: isClean ? 0 : 10) {
                // Insights card (inside board)
                if let insights = viewModel.dailyInsights, !isInsightsCardDismissedToday {
                    insightsCard(insights)
                }

                // Quest cards
                if viewModel.allQuestsComplete {
                    AllQuestsCompleteView(totalXPFromQuests: viewModel.totalQuestXPEarnedToday)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                } else if let quests = viewModel.summary?.quests, !quests.isEmpty {
                    if isClean {
                        ForEach(Array(quests.enumerated()), id: \.element.id) { index, quest in
                            questRow(quest)
                            if index < quests.count - 1 {
                                Divider()
                                    .background(Color.white.opacity(0.05))
                            }
                        }
                    } else {
                        ForEach(quests, id: \.id) { quest in
                            questRow(quest)
                        }
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

    @ViewBuilder
    private func questRow(_ quest: DailyQuest) -> some View {
        if isClean {
            cleanQuestRow(quest)
        } else {
            rpgQuestRow(quest)
        }
    }

    /// Clean mode quest row: minimal divider-separated layout
    @ViewBuilder
    private func cleanQuestRow(_ quest: DailyQuest) -> some View {
        HStack(spacing: 12) {
            // Simple check circle
            ZStack {
                Circle()
                    .fill(quest.isCompleted ? Color(hex: "#0D9488") : Color.clear)
                    .frame(width: 20, height: 20)
                    .overlay(
                        Circle()
                            .stroke(quest.isCompleted ? Color(hex: "#0D9488") : Color(hex: "#3A4D44"), lineWidth: 1.5)
                    )
                if quest.isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                }
            }

            // Title only (no description in clean mode)
            Text(quest.title)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(quest.isCompleted ? Color(hex: "#3F554A") : Color(hex: "#D0DBD5"))
                .strikethrough(quest.isCompleted)
                .lineLimit(1)

            Spacer()

            // Simple XP pill
            Text("+\(quest.xpReward) XP")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(0.3)
                .foregroundColor(quest.isCompleted ? Color(hex: "#3F554A") : Color(hex: "#2DD4BF"))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(quest.isCompleted
                            ? Color.white.opacity(0.04)
                            : Color(hex: "#0D9488").opacity(0.15))
                )
        }
        .padding(.vertical, 12)
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
                    fillGradient: quest.isCompleted ? xpBadgeDoneGradient : xpBadgeGradient
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

    @ViewBuilder
    private func filledInventorySlot(_ entry: FoodEntry) -> some View {
        if isClean {
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
                                .font(.system(size: 22))
                                .foregroundColor(tc.primary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Time badge
                    Text(timeString(from: entry.date))
                        .font(.system(size: 8, weight: .regular, design: .rounded))
                        .foregroundColor(tc.textTertiary)
                        .padding(3)
                }

                // Divider
                Rectangle()
                    .fill(settings.isCleanDark ? Color.white.opacity(0.05) : Color.black.opacity(0.05))
                    .frame(height: 0.5)

                // Label area
                VStack(spacing: 3) {
                    Text(entry.name)
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundColor(tc.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text("\(entry.calories) cal")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(tc.primary)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(tc.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(settings.isCleanDark ? Color.white.opacity(0.05) : Color.black.opacity(0.06), lineWidth: 0.5)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .aspectRatio(1/1.1, contentMode: .fit)
        } else {
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
    }

    private func emptyInventorySlot() -> some View {
        let emptyBorder: Color
        let emptyFill: Color
        let emptyIcon: Color
        let emptyText: Color

        if isClean {
            emptyBorder = settings.isCleanDark ? Color.white.opacity(0.04) : Color.black.opacity(0.06)
            emptyFill = settings.isCleanDark ? Color.white.opacity(0.02) : Color.black.opacity(0.02)
            emptyIcon = tc.textTertiary
            emptyText = tc.textTertiary
        } else if currentTheme == .night {
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
        lastActiveDate: Date(),
        rank: Rank.bronze.rawValue
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

    var body: some View {
        NavigationStack {
            VStack(spacing: DesignSystem.Spacing.xl) {
                // Icon
                ZStack {
                    Circle()
                        .fill(DesignSystem.Colors.secondary.opacity(0.15))
                        .frame(width: 100, height: 100)

                    Image(systemName: "barcode.viewfinder")
                        .font(.system(size: 50, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.secondary)
                }
                .padding(.top, DesignSystem.Spacing.xxl)

                // Title and description
                VStack(spacing: DesignSystem.Spacing.sm) {
                    Text("Quick Scan")
                        .font(.system(size: DesignSystem.FontSizes.title, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textPrimary)

                    Text("Scan a barcode or enter manually to quickly log packaged foods")
                        .font(.system(size: DesignSystem.FontSizes.callout, weight: .regular))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
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
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.xl)
                .padding(.bottom, DesignSystem.Spacing.xl)
            }
            .background(DesignSystem.Colors.primaryBackground)
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

    var body: some View {
        NavigationStack {
            VStack(spacing: DesignSystem.Spacing.xl) {
                ZStack {
                    Circle()
                        .fill(DesignSystem.Colors.secondary.opacity(0.15))
                        .frame(width: 80, height: 80)

                    Image(systemName: "keyboard")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.secondary)
                }
                .padding(.top, DesignSystem.Spacing.xl)

                VStack(spacing: DesignSystem.Spacing.sm) {
                    Text("Enter Barcode Number")
                        .font(.system(size: DesignSystem.FontSizes.title2, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textPrimary)

                    Text("Enter the UPC or EAN barcode from the product packaging")
                        .font(.system(size: DesignSystem.FontSizes.callout, weight: .regular))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DesignSystem.Spacing.xl)
                }

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    TextField("e.g., 737628064502", text: $manualBarcodeInput)
                        .font(.system(size: DesignSystem.FontSizes.body, weight: .regular))
                        .keyboardType(.numberPad)
                        .textFieldStyle(.plain)
                        .padding(DesignSystem.Spacing.md)
                        .background(DesignSystem.Colors.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                                .strokeBorder(DesignSystem.Colors.border, lineWidth: 1)
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
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.xl)
                .padding(.bottom, DesignSystem.Spacing.xl)
            }
            .background(DesignSystem.Colors.primaryBackground)
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.lg) {
                    VStack(spacing: DesignSystem.Spacing.sm) {
                        ZStack {
                            Circle()
                                .fill(DesignSystem.Colors.primary.opacity(0.15))
                                .frame(width: 80, height: 80)

                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 40, weight: .medium))
                                .foregroundColor(DesignSystem.Colors.primary)
                        }

                        Text("Product Found!")
                            .font(.system(size: DesignSystem.FontSizes.title2, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textPrimary)

                        if let brand = nutrition.brand {
                            Text(brand)
                                .font(.system(size: DesignSystem.FontSizes.footnote, weight: .medium))
                                .foregroundColor(DesignSystem.Colors.textSecondary)
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
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        }
                    }
                    .padding(.top, DesignSystem.Spacing.md)
                }
                .padding(DesignSystem.Spacing.lg)
            }
            .background(DesignSystem.Colors.primaryBackground)
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
                .foregroundColor(DesignSystem.Colors.textSecondary)

            HStack(spacing: DesignSystem.Spacing.md) {
                TextField("100", text: $servingSize)
                    .font(.system(size: DesignSystem.FontSizes.body, weight: .medium))
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.plain)
                    .padding(DesignSystem.Spacing.md)
                    .background(DesignSystem.Colors.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                            .strokeBorder(DesignSystem.Colors.border, lineWidth: 1)
                    )
                    .frame(maxWidth: .infinity)

                Text("grams")
                    .font(.system(size: DesignSystem.FontSizes.callout, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textSecondary)

                Button {
                    applyServingSize()
                } label: {
                    Text("Apply")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, DesignSystem.Spacing.md)
                        .padding(.vertical, DesignSystem.Spacing.sm)
                        .background(DesignSystem.Colors.secondary)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm))
                }
            }
        }
    }

    private var nutritionInputs: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            Text("Nutrition Info")
                .font(.system(size: DesignSystem.FontSizes.headline, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.textPrimary)
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
                .foregroundColor(DesignSystem.Colors.textSecondary)

            HStack {
                TextField(placeholder, text: text)
                    .font(.system(size: DesignSystem.FontSizes.body, weight: .regular))
                    .keyboardType(keyboardType)
                    .textFieldStyle(.plain)

                if let unit = unit {
                    Text(unit)
                        .font(.system(size: DesignSystem.FontSizes.footnote, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
            }
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                    .strokeBorder(DesignSystem.Colors.border, lineWidth: 1)
            )
        }
    }

    private var toxinScoreSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack {
                Text("Toxin Score")
                    .font(.system(size: DesignSystem.FontSizes.headline, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)

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
        .background(DesignSystem.Colors.cardBackground)
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
            onComplete()

        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
            isSubmitting = false
        }
    }
}
