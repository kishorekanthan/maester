import SwiftUI
import AppKit

extension Color {
    static func token(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                           green:   CGFloat((hex >> 8)  & 0xFF) / 255,
                           blue:    CGFloat( hex        & 0xFF) / 255,
                           alpha:   1)
        })
    }

    static func dynamicOpacity(lightBlack: Double, darkWhite: Double) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor.white.withAlphaComponent(darkWhite)
                : NSColor.black.withAlphaComponent(lightBlack)
        })
    }

    static let accentNeutral = Color.token(light: 0x3A6EA5, dark: 0x7FB3F0)
}

extension HealthState {
    var tint: Color {
        switch self {
        case .ok:    return .token(light: 0x157F3C, dark: 0x4ADE80)
        case .warn:  return .token(light: 0x9A6400, dark: 0xF5BE4A)
        case .error: return .token(light: 0xB3261E, dark: 0xFF7A6E)
        case .off:   return .token(light: 0x6E6E73, dark: 0x98989F)
        }
    }

    var symbol: String {
        switch self {
        case .ok:    return "checkmark.circle.fill"
        case .warn:  return "exclamationmark.triangle.fill"
        case .error: return "exclamationmark.circle.fill"
        case .off:   return "pause.circle"
        }
    }
}

enum Space {
    static let xs: CGFloat = 3, sm: CGFloat = 5, md: CGFloat = 7
    static let lg: CGFloat = 9, xl: CGFloat = 12, xxl: CGFloat = 16
}

enum Radius {
    static let button: CGFloat = 5, icon: CGFloat = 5, headerIcon: CGFloat = 6
    static let card: CGFloat = 7, panel: CGFloat = 11
}

enum Chart {
    static let stroke: CGFloat = 1.4
    static let tileHeight: CGFloat = 16
    static let inlineSize = CGSize(width: 52, height: 12)
    static let meterHeight: CGFloat = 3
    static let samples = 60
    static let fillOpacity: (top: Double, bottom: Double) = (0.28, 0.02)
}

enum Density: String, CaseIterable, Identifiable {
    case compact, comfortable
    var id: String { rawValue }
    var title: String { self == .compact ? "Compact" : "Comfortable" }

    var tilePadding: EdgeInsets {
        self == .compact ? .init(top: 6, leading: 7, bottom: 6, trailing: 7)
                         : .init(top: 9, leading: 10, bottom: 9, trailing: 10)
    }
    var rowPadding: EdgeInsets {
        self == .compact ? .init(top: 7, leading: 7, bottom: 7, trailing: 7)
                         : .init(top: 9, leading: 9, bottom: 9, trailing: 9)
    }
    var tileGap: CGFloat      { self == .compact ? 5 : 7 }
    var rowGap: CGFloat       { self == .compact ? 3 : 5 }
    var rowIcon: CGFloat      { self == .compact ? 16 : 20 }
    var sectionPad: CGFloat   { self == .compact ? 8 : 12 }
    var tileValue: Font       { .system(self == .compact ? .callout : .title3,
                                        design: .rounded).weight(.bold)
                                  .monospacedDigit() }
    var showsHealthyDetail: Bool { self == .comfortable }
}

extension Font {
    static let appName      = Font.headline.weight(.semibold)
    static let sectionTitle = Font.subheadline.weight(.semibold)
    static let itemLabel    = Font.subheadline.weight(.medium)
    static let itemDetail   = Font.caption2.monospacedDigit()
    static let itemMetric   = Font.system(.caption2, design: .rounded)
                                  .weight(.medium).monospacedDigit()
    static let actionLabel  = Font.caption2.weight(.semibold)
    static let sourceBadge  = Font.caption2.weight(.semibold)
    static let footer       = Font.caption.monospacedDigit()
}

enum Motion {
    static let hover: TimeInterval = 0.13
    static let pressIn: TimeInterval = 0.05
    static let pressOut: TimeInterval = 0.18
    static let pressScale: CGFloat = 0.985
}

enum PanelGround {
    static let background      = Color.token(light: 0xF6F6F8, dark: 0x1F1F22)
    static let border           = Color.dynamicOpacity(lightBlack: 0.13, darkWhite: 0.10)
    static let dividerMajor     = Color.dynamicOpacity(lightBlack: 0.09, darkWhite: 0.09)
    static let dividerSection   = Color.dynamicOpacity(lightBlack: 0.07, darkWhite: 0.07)
    static let tileFill         = Color.dynamicOpacity(lightBlack: 0.045, darkWhite: 0.06)
    static let rowFill          = Color.dynamicOpacity(lightBlack: 0.03, darkWhite: 0.045)
    static let rowHover         = Color.dynamicOpacity(lightBlack: 0.075, darkWhite: 0.10)
    static let rowPressed       = Color.dynamicOpacity(lightBlack: 0.12, darkWhite: 0.16)
    static let secondaryText    = Color.dynamicOpacity(lightBlack: 0.52, darkWhite: 0.56)
    static let tertiaryText     = Color.dynamicOpacity(lightBlack: 0.45, darkWhite: 0.45)
}
