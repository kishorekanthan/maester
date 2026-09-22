import SwiftUI
import AppKit

extension HealthState {
    var badgeSymbol: String {
        switch self {
        case .ok:    return "checkmark.circle.fill"
        case .warn:  return "exclamationmark.circle.fill"
        case .error: return "xmark.circle.fill"
        case .off:   return "moon.circle.fill"
        }
    }

    var menuBarTemplate: String {
        switch self {
        case .ok:    return "ok"
        case .warn:  return "warn"
        case .error: return "error"
        case .off:   return "sleep"
        }
    }

    var menuBarSymbol: String {
        switch self {
        case .ok:    return "checkmark.seal"
        case .warn:  return "exclamationmark.triangle"
        case .error: return "xmark.seal"
        case .off:   return "moon.zzz"
        }
    }

    var spoken: String {
        switch self {
        case .ok: return "healthy"
        case .warn: return "needs attention"
        case .error: return "error"
        case .off: return "stopped"
        }
    }
}

enum PanelLayout {
    static let columnIdeal: CGFloat = 348
    static let columnFloor: CGFloat = 240
    static let columnGap: CGFloat = 16
    static let screenInset: CGFloat = 12
    static let heightSlack: CGFloat = 120
    static let heightCap: CGFloat = 880
}

enum PanelLayoutMath {
    static func columns(providers: Int, screenWidth: CGFloat) -> Int {
        let safe = screenWidth - 2 * PanelLayout.screenInset
        let unit = PanelLayout.columnIdeal + PanelLayout.columnGap
        let fit = Int(((safe + PanelLayout.columnGap) / unit).rounded(.down))
        return max(1, min(3, min(max(providers, 1), fit)))
    }

    static func contentWidth(columns cols: Int, screenWidth: CGFloat) -> CGFloat {
        let safe = screenWidth - 2 * PanelLayout.screenInset
        let n = CGFloat(max(cols, 1))
        let wanted = n * PanelLayout.columnIdeal + (n - 1) * PanelLayout.columnGap
        return min(wanted, safe)
    }

    static func panelHeight(contentHeight: CGFloat, screenHeight: CGFloat) -> CGFloat {
        let room = screenHeight - PanelLayout.heightSlack
        return max(60, min(contentHeight, min(room, PanelLayout.heightCap)))
    }

    static func originX(panelWidth: CGFloat, itemMidX: CGFloat, screenMinX: CGFloat, screenMaxX: CGFloat) -> CGFloat {
        var x = itemMidX - panelWidth / 2
        x = min(x, screenMaxX - panelWidth - PanelLayout.screenInset)
        x = max(x, screenMinX + PanelLayout.screenInset)
        return x
    }

    static func clampedFrame(current: CGRect, targetWidth: CGFloat, visible: CGRect) -> CGRect {
        var frame = current
        if abs(frame.width - targetWidth) > 0.5 {
            let centerX = frame.midX
            frame.size.width = targetWidth
            frame.origin.x = centerX - targetWidth / 2
        }
        if frame.height > visible.height {
            frame.size.height = visible.height
        }
        frame.origin.x = min(frame.origin.x, visible.maxX - frame.width - PanelLayout.screenInset)
        frame.origin.x = max(frame.origin.x, visible.minX + PanelLayout.screenInset)
        frame.origin.y = min(frame.origin.y, visible.maxY - frame.height)
        frame.origin.y = max(frame.origin.y, visible.minY)
        return frame
    }
}

private struct PanelWindowClamp: NSViewRepresentable {
    let targetWidth: CGFloat

    final class Coordinator {
        var observers: [NSObjectProtocol] = []
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { attach(to: view, coordinator: context.coordinator) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { clamp(nsView.window, targetWidth: targetWidth) }
    }

    private func attach(to view: NSView, coordinator: Coordinator) {
        guard let window = view.window, coordinator.observers.isEmpty else { return }
        for name: Notification.Name in [NSWindow.didResizeNotification,
                                         NSWindow.didMoveNotification,
                                         NSWindow.didBecomeKeyNotification] {
            let token = NotificationCenter.default.addObserver(
                forName: name, object: window, queue: .main
            ) { [weak window] _ in clamp(window, targetWidth: targetWidth) }
            coordinator.observers.append(token)
        }
        for name: Notification.Name in [NSApplication.didChangeScreenParametersNotification,
                                         NSWorkspace.didWakeNotification] {
            let token = NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak window] _ in clamp(window, targetWidth: targetWidth) }
            coordinator.observers.append(token)
        }
        clamp(window, targetWidth: targetWidth)
    }

    private func clamp(_ window: NSWindow?, targetWidth: CGFloat) {
        guard let window else { return }
        applyClamp(window, targetWidth: targetWidth)
        for delay in [0.02, 0.08, 0.2, 0.4] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { applyClamp(window, targetWidth: targetWidth) }
        }
    }

    private func applyClamp(_ window: NSWindow, targetWidth: CGFloat) {
        guard window.isVisible else { return }
        let screen = window.screen
            ?? NSScreen.screens.first { $0.frame.contains(window.frame.origin) }
            ?? NSScreen.main
        guard let screen else { return }
        let corrected = PanelLayoutMath.clampedFrame(current: window.frame,
                                                       targetWidth: targetWidth,
                                                       visible: screen.visibleFrame)
        if corrected != window.frame {
            window.setFrame(corrected, display: true)
        }
    }
}

struct PanelView: View {
    @ObservedObject var monitor: Monitor

    @State private var contentHeight: CGFloat = 240
    private var density: Density { monitor.density }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static var targetScreen: NSScreen {
        NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
            ?? NSScreen.screens.first!
    }

    private var availableWidth: CGFloat {
        Self.targetScreen.visibleFrame.width
    }

    private var maxColumns: Int {
        PanelLayoutMath.columns(providers: monitor.providers.count, screenWidth: availableWidth)
    }

    private var columns: [[ProviderState]] {
        let all = monitor.providers
        guard all.count > 1 else { return [all] }
        var buckets: [[ProviderState]] = []
        for p in all {
            if buckets.count < maxColumns {
                buckets.append([p])
            } else {
                buckets[buckets.count - 1].append(p)
            }
        }
        return buckets
    }

    private var contentWidth: CGFloat {
        PanelLayoutMath.contentWidth(columns: max(columns.count, 1), screenWidth: availableWidth)
    }

    private var columnWidth: CGFloat {
        let n = CGFloat(max(columns.count, 1))
        let usable = contentWidth - (n - 1) * PanelLayout.columnGap
        return max(PanelLayout.columnFloor, usable / n)
    }

    private var panelWidth: CGFloat {
        contentWidth + 2 * PanelLayout.screenInset
    }

    private var maxContentHeight: CGFloat {
        PanelLayoutMath.panelHeight(contentHeight: .greatestFiniteMagnitude,
                                    screenHeight: Self.targetScreen.visibleFrame.height)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().foregroundStyle(PanelGround.dividerMajor)
            if monitor.providers.isEmpty {
                empty
            } else {
                ScrollView {
                    HStack(alignment: .top, spacing: PanelLayout.columnGap) {
                        ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(column.enumerated()), id: \.element.id) { i, p in
                                    if i > 0 {
                                        Divider()
                                            .foregroundStyle(PanelGround.dividerSection)
                                            .padding(.horizontal, Space.xl)
                                            .padding(.vertical, Space.lg)
                                    }
                                    ProviderSection(monitor: monitor, provider: p, density: density)
                                        .transition(.opacity)
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(width: columnWidth, alignment: .topLeading)
                        }
                    }
                    .padding(.horizontal, Space.xl)
                    .padding(.vertical, Space.xl)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.15),
                               value: monitor.providers.map(\.id))
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                        contentHeight = h
                    }
                }
                .frame(height: min(max(contentHeight, 60), maxContentHeight))
            }
            Divider().foregroundStyle(PanelGround.dividerMajor)
            footer
        }
        .frame(minWidth: PanelLayout.columnFloor + 2 * PanelLayout.screenInset,
               idealWidth: panelWidth,
               maxWidth: max(PanelLayout.columnFloor + 2 * PanelLayout.screenInset,
                              availableWidth - 2 * PanelLayout.screenInset))
        .fixedSize(horizontal: true, vertical: false)
        .background(PanelGround.background)
        .clipShape(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
                .stroke(PanelGround.border, lineWidth: 1)
        )
        .background(PanelWindowClamp(targetWidth: panelWidth))
        .onAppear { monitor.panelDidAppear() }
        .onDisappear { monitor.panelDidDisappear() }
    }

    private var header: some View {
        HStack(spacing: Space.lg) {
            HStack(spacing: Space.lg) {
                StatusIcon(icon: "path:" + Bundle.main.bundlePath,
                           state: monitor.overall, size: 22)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.headerIcon, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Maester").font(.appName)
                    Text(monitor.headline)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Maester, \(monitor.overall.spoken). \(monitor.headline)")
            Spacer()
            HStack(spacing: 2) {
                Menu {
                    Section("Providers") {
                        ForEach(monitor.discovered) { p in
                            Toggle(isOn: Binding(
                                get: { !p.disabled },
                                set: { newValue in monitor.setDisabled(p.id, !newValue) }
                            )) {
                                Text(Self.gearTitle(p))
                            }
                            .accessibilityLabel(Self.gearAccessibilityLabel(p))
                        }
                    }
                    Section("Density") {
                        Picker("Density", selection: Binding(
                            get: { monitor.density },
                            set: { monitor.setDensity($0) }
                        )) {
                            ForEach(Density.allCases) { d in
                                Text(d.title).tag(d)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                    Toggle(isOn: Binding(
                        get: { LoginItem.isEnabled },
                        set: { LoginItem.setEnabled($0) }
                    )) {
                        Text("Open at Login")
                    }
                    .accessibilityLabel(LoginItem.needsApproval
                                         ? "Open at Login, needs approval in System Settings"
                                         : "Open at Login")
                    if LoginItem.needsApproval {
                        Button("Open Login Items Settings") { LoginItem.openSettings() }
                    }
                    Button("Refresh All") { monitor.refreshNow() }
                    Divider()
                    Button("Reveal Providers in Finder…") {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: MaesterConfig.root + "/providers")
                    }
                    Button("About Maester") {
                        NSApp.activate(ignoringOtherApps: true)
                        NSApp.orderFrontStandardAboutPanel(nil)
                    }
                } label: {
                    Image(systemName: Icon.systemName("gearshape"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.headerIcon, style: .continuous)
                                .fill(Color.dynamicOpacity(lightBlack: 0.06, darkWhite: 0.10))
                        )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("Provider settings")
                .help("Enable or disable providers")
                Button {
                    monitor.refreshNow()
                } label: {
                    Image(systemName: Icon.systemName("arrow.clockwise"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("r", modifiers: .command)
                .accessibilityLabel("Refresh every provider now")
                .help("Refresh every provider now")
            }
        }
        .padding(EdgeInsets(top: 11, leading: 12, bottom: 10, trailing: 12))
    }

    private static func gearTitle(_ p: ProviderState) -> String {
        let base = p.report?.title ?? p.id
        return p.refusal != nil ? "\(base) (refused)" : base
    }

    private static func gearAccessibilityLabel(_ p: ProviderState) -> String {
        let base = p.report?.title ?? p.id
        let state = p.disabled ? "off" : "on"
        if let refusal = p.refusal {
            return "\(base), refused: \(refusal), \(state)"
        }
        return "\(base), \(state)"
    }

    private var empty: some View {
        NoticePlate(kind: .empty,
                    symbol: "square.dashed",
                    title: "No providers",
                    detail: "Drop an executable in ~/.config/maester/providers. See CONTRACT.md.",
                    scale: .panel,
                    primaryLabel: "Reveal in Finder…",
                    primaryAction: {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: MaesterConfig.root + "/providers")
        })
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let e = monitor.actionError {
                Image(systemName: Icon.systemName("exclamationmark.triangle.fill"))
                    .foregroundStyle(HealthState.error.tint)
                Text(e).font(.footer).foregroundStyle(HealthState.error.tint).lineLimit(1)
            } else if let n = monitor.configNotice {
                Image(systemName: Icon.systemName("arrow.triangle.2.circlepath"))
                    .foregroundStyle(HealthState.warn.tint)
                Text(n.text).font(.footer).foregroundStyle(HealthState.warn.tint).lineLimit(1)
            } else {
                Text(monitor.footprint).font(.footer).foregroundStyle(PanelGround.secondaryText)
            }
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.caption)
                .keyboardShortcut("q", modifiers: .command)
        }
        .padding(.horizontal, Space.xl)
        .padding(.top, 7)
        .padding(.bottom, 8)
        .frame(minHeight: 28)
    }
}

private struct ProviderSection: View {
    @ObservedObject var monitor: Monitor
    let provider: ProviderState
    let density: Density

    @FocusState private var listFocused: Bool
    @State private var keyboardItemID: String?

    private var report: Report? { provider.report }

    private func moveFocus(_ direction: MoveCommandDirection, items: [ItemSpec]) {
        guard direction == .up || direction == .down else { return }
        guard let currentID = keyboardItemID, let idx = items.firstIndex(where: { $0.id == currentID }) else {
            keyboardItemID = items.first?.id
            return
        }
        let next = direction == .down ? idx + 1 : idx - 1
        guard items.indices.contains(next) else { return }
        keyboardItemID = items[next].id
    }

    private var sourceBadgeText: String? {
        if provider.source.hasPrefix("stream") { return "STREAM" }
        if provider.source.hasPrefix("poll") {
            return "POLL \(Int(report?.caps.interval ?? 5))s"
        }
        return nil
    }

    private var isEmptyReport: Bool {
        (report?.metrics?.isEmpty ?? true) && (report?.items?.isEmpty ?? true)
            && (report?.lines?.isEmpty ?? true)
    }

    private var notice: NoticeKind? {
        NoticeKind.forSection(hasReport: report != nil,
                              hasMessage: provider.message != nil,
                              messageIsFailure: provider.message?.severity == .failure,
                              reportStateIsOff: report?.state == .off,
                              reportIsEmpty: isEmptyReport)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            HStack(alignment: .center, spacing: Space.md) {
                StatusIcon(icon: report?.icon, state: provider.state, size: 17)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                Text(provider.title)
                    .font(.sectionTitle)
                    .lineLimit(1)
                if let badge = sourceBadgeText {
                    Text(badge)
                        .font(.sourceBadge)
                        .tracking(0.5)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(Color.dynamicOpacity(lightBlack: 0.16, darkWhite: 0.16), lineWidth: 1)
                        )
                }
                Spacer()
                trailingSummary
            }

            if let notice {
                NoticePlate(kind: notice,
                            symbol: noticeSymbol(notice),
                            title: noticeTitle(notice),
                            detail: noticeDetail(notice),
                            scale: .section,
                            primaryLabel: notice == .error || notice == .timedOut ? "Retry" : nil,
                            primaryAction: notice == .error || notice == .timedOut
                                ? { monitor.refreshNow() } : nil)
            } else {
                sectionBody
            }
        }
    }

    @ViewBuilder private var sectionBody: some View {
        if let message = provider.message {
            let fatal = message.severity == .failure
            Label(message.text,
                  systemImage: fatal ? "exclamationmark.octagon" : "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(fatal ? HealthState.error.tint : HealthState.warn.tint)
                .fixedSize(horizontal: false, vertical: true)
        } else if let s = report?.summary, !s.isEmpty {
            Text(s).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        if let metrics = report?.metrics, !metrics.isEmpty {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: density.tileGap),
                                GridItem(.flexible(), spacing: density.tileGap)],
                      spacing: density.tileGap) {
                ForEach(metrics) { m in
                    MetricCard(metric: m,
                               series: monitor.history.series(provider.id, nil, m.id),
                               tint: provider.state == .ok ? .accentNeutral : provider.state.tint,
                               density: density)
                }
            }
        }

        if let lines = report?.lines, !lines.isEmpty {
            VStack(spacing: 3) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                    HStack(spacing: 8) {
                        Text(l.label).font(.caption).foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Text(l.value ?? "—")
                            .font(.system(.caption, design: .rounded).weight(.medium))
                            .foregroundStyle(l.state.map { $0.tint } ?? .primary)
                    }
                }
            }
        }

        if let items = report?.items, !items.isEmpty {
            VStack(spacing: density.rowGap) {
                ForEach(items) { it in
                    ItemRow(monitor: monitor, providerID: provider.id, item: it, density: density,
                            isFocused: listFocused && keyboardItemID == it.id)
                }
            }
            .focusable()
            .focused($listFocused)
            .focusEffectDisabled()
            .onMoveCommand { moveFocus($0, items: items) }
            .onChange(of: monitor.panelVisible) { _, visible in
                if !visible { keyboardItemID = nil }
            }
            .onKeyPress(.return) {
                guard let id = keyboardItemID,
                      let it = items.first(where: { $0.id == id }),
                      let primary = it.actions?.first else { return .ignored }
                monitor.perform(provider: provider.id, action: primary.id, item: it.id)
                return .handled
            }
        }

        if let actions = report?.actions, !actions.isEmpty {
            HStack(spacing: 6) {
                ForEach(actions) { a in
                    ActionButton(monitor: monitor, providerID: provider.id,
                                 item: nil, action: a, prominent: true)
                }
                Spacer()
            }
        }
    }

    private func noticeSymbol(_ kind: NoticeKind) -> String {
        switch kind {
        case .error: return "exclamationmark.circle.fill"
        case .timedOut: return "clock.badge.questionmark"
        default: return "questionmark.circle"
        }
    }

    private func noticeTitle(_ kind: NoticeKind) -> String {
        switch kind {
        case .error: return "Failed to report"
        case .timedOut: return "Not responding"
        default: return "Waiting for first report"
        }
    }

    private func noticeDetail(_ kind: NoticeKind) -> String? {
        switch kind {
        case .error: return provider.message?.text
        case .timedOut: return "Last state: stopped"
        default: return nil
        }
    }

    @ViewBuilder private var trailingSummary: some View {
        if provider.state == .ok {
            Circle().fill(HealthState.ok.tint).frame(width: 6, height: 6)
        } else if let s = report?.summary, !s.isEmpty {
            Label {
                Text(s).font(.caption2).fontWeight(.semibold).lineLimit(1)
            } icon: {
                Image(systemName: Icon.systemName(provider.state.symbol)).font(.caption2)
            }
            .foregroundStyle(provider.state.tint)
        } else {
            Label {
                Text(provider.state.spoken).font(.caption2).fontWeight(.semibold).lineLimit(1)
            } icon: {
                Image(systemName: Icon.systemName(provider.state.symbol)).font(.caption2)
            }
            .foregroundStyle(provider.state.tint)
        }
    }
}

private struct MetricCard: View {
    let metric: MetricSpec
    let series: [Double]
    var tint: Color
    let density: Density

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(metric.label ?? metric.id)
                .font(.system(.caption2, weight: .medium))
                .foregroundStyle(PanelGround.secondaryText)
                .lineLimit(1)
            if let number = metric.formattedNumber {
                (Text(number).font(density.tileValue)
                 + Text(metric.unit.map { " \($0)" } ?? "")
                    .font(.caption).fontWeight(.semibold).foregroundColor(.primary.opacity(0.5)))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text(metric.display)
                    .font(density.tileValue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            if metric.isNumeric {
                Sparkline(values: series, tint: tint).frame(height: Chart.tileHeight)
            }
            if let p = metric.pct {
                MeterBar(pct: p, tint: tint)
            }
        }
        .padding(density.tilePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(PanelGround.tileFill))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metric.label ?? metric.id): \(metric.display)")
    }
}

private struct ItemRow: View {
    @ObservedObject var monitor: Monitor
    let providerID: String
    let item: ItemSpec
    let density: Density

    let isFocused: Bool

    @State private var isHovered = false
    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var state: HealthState { item.state ?? .ok }
    private var unhealthy: Bool { state == .warn || state == .error }
    private var actionsRevealed: Bool { unhealthy || isHovered || isFocused }

    var body: some View {
        VStack(alignment: .leading, spacing: density.rowGap) {
            HStack(spacing: 6) {
                StatusIcon(icon: item.icon, state: state, size: density.rowIcon)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.icon, style: .continuous))
                Text(item.label)
                    .font(.itemLabel)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                ForEach(item.actions ?? []) { a in
                    ActionButton(monitor: monitor, providerID: providerID,
                                 item: item.id, action: a, prominent: false)
                        .opacity(actionsRevealed ? 1 : 0)
                        .allowsHitTesting(actionsRevealed)
                }
            }
            if let d = item.detail, !d.isEmpty {
                Text(d).font(.itemDetail)
                    .foregroundStyle(unhealthy ? state.tint : PanelGround.secondaryText)
                    .fontWeight(unhealthy ? .medium : .regular)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let ms = item.metrics, !ms.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(ms) { m in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(m.label ?? m.id) \(m.display)")
                                .font(.itemMetric)
                                .lineLimit(1)
                            if m.isNumeric {
                                Sparkline(values: monitor.history.series(providerID, item.id, m.id),
                                          tint: state == .ok ? .accentNeutral : state.tint)
                                    .frame(width: Chart.inlineSize.width, height: Chart.inlineSize.height)
                            }
                        }
                    }
                    Spacer()
                }
            }
        }
        .padding(density.rowPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(rowFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(unhealthy ? state.tint.opacity(0.22) : .clear, lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(isFocused ? Color.accentColor : .clear, lineWidth: 2)
                .padding(-1)
        )
        .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .scaleEffect(isPressed ? Motion.pressScale : 1)
        .animation(hoverCurve, value: isHovered)
        .animation(hoverCurve, value: isFocused)
        .animation(pressCurve, value: isPressed)
        .onHover { isHovered = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }

    private var hoverCurve: Animation? {
        reduceMotion ? nil : .easeOut(duration: Motion.hover)
    }

    private var pressCurve: Animation? {
        if reduceMotion { return nil }
        return .easeOut(duration: isPressed ? Motion.pressIn : Motion.pressOut)
    }

    private var rowFill: Color {
        if unhealthy { return state.tint.opacity(0.09) }
        if isPressed { return PanelGround.rowPressed }
        if isHovered { return PanelGround.rowHover }
        return PanelGround.rowFill
    }
}

private struct ActionButton: View {
    @ObservedObject var monitor: Monitor
    let providerID: String
    let item: String?
    let action: ActionSpec
    let prominent: Bool

    private var busy: Bool { monitor.isBusy(providerID, action.id, item) }

    var body: some View {
        Button {
            monitor.perform(provider: providerID, action: action.id, item: item)
        } label: {
            HStack(spacing: 4) {
                if busy {
                    ProgressView().controlSize(.mini).scaleEffect(0.7).frame(width: 10, height: 10)
                } else if action.terminal == true {
                    Image(systemName: Icon.systemName("apple.terminal")).font(.actionLabel)
                }
                Text(action.label)
                    .font(.actionLabel)
                    .lineLimit(1)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .frame(minHeight: 20)
        }
        .controlSize(.small)
        .disabled(busy || monitor.actionInFlight)
        .modifier(GlassButton(prominent: prominent))
        .accessibilityLabel(item.map { "\(action.label), \($0)" } ?? action.label)
        .help(action.label)
    }
}

private struct GlassButton: ViewModifier {
    let prominent: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        } else {
            content.buttonStyle(.bordered)
        }
    }
}
