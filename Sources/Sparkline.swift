import SwiftUI

struct Sparkline: View {
    let values: [Double]
    var tint: Color = .accentColor

    var body: some View {
        Canvas { ctx, size in
            guard size.width > 1, size.height > 1 else { return }
            let inset: CGFloat = 1.5
            let h = size.height - inset * 2
            let w = size.width

            guard values.count >= 2 else {
                var p = Path()
                p.move(to: CGPoint(x: 0, y: size.height - inset))
                p.addLine(to: CGPoint(x: w, y: size.height - inset))
                ctx.stroke(p, with: .color(Color.dynamicOpacity(lightBlack: 0.28, darkWhite: 0.28)),
                           style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                return
            }

            let lo = values.min() ?? 0
            let hi = values.max() ?? 1
            let span = (hi - lo) < 0.0001 ? 1.0 : (hi - lo)
            let step = w / CGFloat(values.count - 1)

            func point(_ i: Int) -> CGPoint {
                let norm = (values[i] - lo) / span
                return CGPoint(x: CGFloat(i) * step,
                               y: inset + h - CGFloat(norm) * h)
            }

            var line = Path()
            line.move(to: point(0))
            for i in 1..<values.count { line.addLine(to: point(i)) }

            var fill = line
            fill.addLine(to: CGPoint(x: w, y: size.height))
            fill.addLine(to: CGPoint(x: 0, y: size.height))
            fill.closeSubpath()

            ctx.fill(fill, with: .linearGradient(
                Gradient(colors: [tint.opacity(0.28), tint.opacity(0.02)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            ctx.stroke(line, with: .color(tint.opacity(0.9)),
                       style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))

            let last = point(values.count - 1)
            ctx.fill(Path(ellipseIn: CGRect(x: last.x - 2, y: last.y - 2, width: 4, height: 4)),
                     with: .color(tint))
        }
        .accessibilityHidden(true)
    }
}

struct MeterBar: View {
    let pct: Double
    var tint: Color = .accentColor

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let frac = max(0, min(pct / 100, 1))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.dynamicOpacity(lightBlack: 0.10, darkWhite: 0.10))
                Capsule().fill(tint)
                    .frame(width: max(2, geo.size.width * frac))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: frac)
            }
        }
        .frame(height: Chart.meterHeight)
        .accessibilityHidden(true)
    }
}
