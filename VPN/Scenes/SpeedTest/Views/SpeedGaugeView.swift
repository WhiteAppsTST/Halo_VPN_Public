import SwiftUI
import CoreGraphics

struct SpeedGaugeView: View {
    var progress: Double

    private let figmaWidth: CGFloat = 402
    private let ellipseRadius: CGFloat = 286.5
    private let ellipseCenterY: CGFloat = 333.5
    private let arcLineWidth: CGFloat = 44
    private let tickInset: CGFloat = 12
    private let tickLongLength: CGFloat = 10
    private let tickShortLength: CGFloat = 7
    private let tickLineWidth: CGFloat = 1.5
    private let needleSize: CGFloat = 46

    private let scaleMarks: [(label: String, xFig: CGFloat, yFig: CGFloat, isTop: Bool)] = [
        ("0",    8.4,   45.4, false),
        ("50",   92.6,  16.1, false),
        ("100",  201,   0,    true),
        ("200",  312.4, 16.1, false),
        ("300+", 377.1, 45.4, false)
    ]

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let s = w / figmaWidth
            let R = ellipseRadius * s
            let cy = ellipseCenterY * s
            let arcW = arcLineWidth * s
            let center = CGPoint(x: w / 2, y: cy)
            let baseDelta: CGFloat = CoreGraphics.asin(min(0.999, (w / 2) / R))
            let deltaTheta: CGFloat = min(.pi / 2 - 0.01, baseDelta + 0.12)

            ZStack {
                arcPath(center: center, radius: R, from: -deltaTheta, to: deltaTheta)
                    .stroke(.white.opacity(0.06), style: StrokeStyle(lineWidth: arcW, lineCap: .round))

                let fillEndθ: CGFloat = -deltaTheta + 2 * deltaTheta * CGFloat(max(0, min(1, progress)))
                arcPath(center: center, radius: R, from: -deltaTheta, to: fillEndθ)
                    .stroke(
                        LinearGradient(
                            colors: [Color(hex: "5B9BFF"), Color(hex: "1B4B95")],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: arcW, lineCap: .round)
                    )
                    .shadow(color: Color(hex: "5B9BFF").opacity(0.55), radius: 14)

                ForEach(0..<21, id: \.self) { i in
                    tickView(index: i, center: center, arcRadius: R, arcW: arcW, deltaTheta: deltaTheta, scale: s)
                }

                ForEach(scaleMarks.indices, id: \.self) { i in
                    let mark = scaleMarks[i]
                    Text(mark.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(mark.isTop ? 1 : 0.35))
                        .position(x: mark.xFig * s, y: mark.yFig)
                }

                needleView(center: center, radius: R, deltaTheta: deltaTheta, scale: s)
            }
        }
    }

    private func arcPath(center: CGPoint, radius: CGFloat, from θ1: CGFloat, to θ2: CGFloat) -> Path {
        Path { p in
            let steps = 140
            for i in 0...steps {
                let t = CGFloat(i) / CGFloat(steps)
                let θ = θ1 + (θ2 - θ1) * t
                let x = center.x + radius * CoreGraphics.sin(θ)
                let y = center.y - radius * CoreGraphics.cos(θ)
                if i == 0 {
                    p.move(to: CGPoint(x: x, y: y))
                } else {
                    p.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
    }

    private func tickView(index: Int, center: CGPoint, arcRadius: CGFloat, arcW: CGFloat, deltaTheta: CGFloat, scale: CGFloat) -> some View {
        let isLong = index % 5 == 0
        let length = (isLong ? tickLongLength : tickShortLength) * scale
        let fraction: CGFloat = CGFloat(index) / 20.0
        let θ: CGFloat = -deltaTheta + 2 * deltaTheta * fraction
        let rStart = arcRadius - arcW / 2 - tickInset * scale
        let rEnd = rStart - length
        let x1 = center.x + rStart * CoreGraphics.sin(θ)
        let y1 = center.y - rStart * CoreGraphics.cos(θ)
        let x2 = center.x + rEnd * CoreGraphics.sin(θ)
        let y2 = center.y - rEnd * CoreGraphics.cos(θ)
        return Path { p in
            p.move(to: CGPoint(x: x1, y: y1))
            p.addLine(to: CGPoint(x: x2, y: y2))
        }
        .stroke(.white, style: StrokeStyle(lineWidth: tickLineWidth, lineCap: .round))
    }

    private func needleView(center: CGPoint, radius: CGFloat, deltaTheta: CGFloat, scale: CGFloat) -> some View {
        let p: CGFloat = CGFloat(max(0, min(1, progress)))
        let θ: CGFloat = -deltaTheta + 2 * deltaTheta * p
        let x = center.x + radius * CoreGraphics.sin(θ)
        let y = center.y - radius * CoreGraphics.cos(θ)
        let size = needleSize * scale
        return Circle()
            .fill(
                RadialGradient(
                    colors: [.white, Color(hex: "5B9BFF")],
                    center: UnitPoint(x: 0.4, y: 0.4),
                    startRadius: 0,
                    endRadius: size / 2
                )
            )
            .frame(width: size, height: size)
            .shadow(color: Color(hex: "5B9BFF").opacity(0.6), radius: 12 * scale)
            .position(x: x, y: y)
    }
}
