import AppKit
import SwiftUI

enum Icon {
    private static var cache: [String: NSImage?] = [:]
    private static let lock = NSLock()

    private static var symbolCache: [String: Bool] = [:]
    private static let symbolLock = NSLock()
    static let fallbackSymbol = "questionmark.circle"

    static func image(_ hint: String?) -> NSImage? {
        guard let hint, !hint.isEmpty, !hint.hasPrefix("sf:") else { return nil }
        lock.lock(); defer { lock.unlock() }
        if let hit = cache[hint] { return hit }
        let image = resolve(hint)
        cache[hint] = image
        return image
    }

    static func systemSymbolAvailable(_ name: String) -> Bool {
        symbolLock.lock(); defer { symbolLock.unlock() }
        if let hit = symbolCache[name] { return hit }
        let available = NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
        symbolCache[name] = available
        return available
    }

    static func systemName(_ preferred: String) -> String {
        systemSymbolAvailable(preferred) ? preferred : fallbackSymbol
    }

    static func isTemplate(_ hint: String?) -> Bool {
        hint?.hasPrefix("asset:") ?? false
    }

    static func symbol(_ hint: String?) -> String? {
        guard let hint, hint.hasPrefix("sf:") else { return nil }
        let name = String(hint.dropFirst(3))
        return name.isEmpty ? nil : name
    }

    private static func resolve(_ hint: String) -> NSImage? {
        guard let colon = hint.firstIndex(of: ":") else { return nil }
        let scheme = String(hint[hint.startIndex..<colon])
        let value = String(hint[hint.index(after: colon)...])
        guard !value.isEmpty else { return nil }
        let ws = NSWorkspace.shared

        switch scheme {
        case "bundle":
            guard let url = ws.urlForApplication(withBundleIdentifier: value) else { return nil }
            return ws.icon(forFile: url.path)
        case "path":
            let target = appBundle(containing: value) ?? value
            guard FileManager.default.fileExists(atPath: target) else { return nil }
            return ws.icon(forFile: target)
        case "pid":
            guard let pid = pid_t(value),
                  let app = NSRunningApplication(processIdentifier: pid) else { return nil }
            return app.icon
        case "asset":
            guard let url = Bundle.main.url(forResource: value, withExtension: "png",
                                            subdirectory: "glyphs") else { return nil }
            return NSImage(contentsOf: url)
        default:
            return nil
        }
    }

    private static func appBundle(containing path: String) -> String? {
        guard let r = path.range(of: ".app/") else {
            return path.hasSuffix(".app") ? path : nil
        }
        return path[path.startIndex..<r.lowerBound] + ".app"
    }
}

struct StatusIcon: View {
    let icon: String?
    let state: HealthState
    let size: CGFloat

    private static let badgeDiameter: CGFloat = 11
    private static let badgeSymbolFloor: CGFloat = 20
    private static let badgeRing: CGFloat = 1.5

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        mark
            .frame(width: size, height: size)
            .opacity(state == .off ? 0.45 : 1)
            .overlay(alignment: .bottomTrailing) {
                if state != .ok {
                    badge
                        .offset(x: Self.badgeDiameter * 0.3, y: Self.badgeDiameter * 0.3)
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: state)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var badge: some View {
        ZStack {
            Circle().fill(state.tint)
            if size >= Self.badgeSymbolFloor {
                Image(systemName: Icon.systemName(state.badgeSymbol))
                    .font(.system(size: Self.badgeDiameter * 0.62, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: Self.badgeDiameter, height: Self.badgeDiameter)
        .background(Circle().fill(PanelGround.background).padding(-Self.badgeRing))
    }

    @ViewBuilder private var mark: some View {
        if let image = Icon.image(icon) {
            Image(nsImage: image)
                .resizable()
                .renderingMode(Icon.isTemplate(icon) ? .template : .original)
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.primary)
        } else if let sf = Icon.symbol(icon), Icon.systemSymbolAvailable(sf) {
            Image(systemName: sf)
                .font(.system(size: size * 0.84, weight: .medium))
                .foregroundStyle(.primary)
        } else {
            Image(systemName: Icon.systemName(state.symbol))
                .font(.system(size: size * 0.76, weight: .semibold))
                .foregroundStyle(state.tint)
        }
    }
}
