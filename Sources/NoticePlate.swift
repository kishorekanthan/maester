import SwiftUI

enum NoticeKind {
    case empty, loading, error, timedOut

    static func forSection(hasReport: Bool, hasMessage: Bool, messageIsFailure: Bool,
                            reportStateIsOff: Bool, reportIsEmpty: Bool) -> NoticeKind? {
        if !hasReport, !hasMessage { return .loading }
        if !hasReport, hasMessage, messageIsFailure { return .error }
        if hasReport, reportStateIsOff, reportIsEmpty, !hasMessage { return .timedOut }
        return nil
    }
}

enum NoticeScale {
    case panel, section
}

struct NoticePlate: View {
    let kind: NoticeKind
    let symbol: String
    let title: String
    let detail: String?
    let scale: NoticeScale
    var primaryLabel: String? = nil
    var primaryAction: (() -> Void)? = nil
    var secondaryLabel: String? = nil
    var secondaryAction: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmer = false
    @State private var shimmer2 = false

    var body: some View {
        Group {
            switch scale {
            case .panel: panelBody
            case .section: sectionBody
            }
        }
        .onAppear {
            guard kind == .loading, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                shimmer = true
            }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true).delay(0.2)) {
                shimmer2 = true
            }
        }
    }

    private var panelBody: some View {
        VStack(spacing: Space.lg) {
            Image(systemName: Icon.systemName(symbol))
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(PanelGround.secondaryText)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: Radius.headerIcon + 3, style: .continuous)
                        .fill(Color.dynamicOpacity(lightBlack: 0.05, darkWhite: 0.05))
                )
            VStack(spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(PanelGround.secondaryText)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let primaryLabel, let primaryAction {
                Button(primaryLabel, action: primaryAction)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder private var sectionBody: some View {
        if kind == .loading {
            skeleton
        } else {
            notice
        }
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(PanelGround.tileFill)
                .frame(width: 76, height: 8)
            HStack(spacing: Space.md) {
                skeletonTile.opacity(reduceMotion ? 0.5 : (shimmer ? 0.8 : 0.35))
                skeletonTile.opacity(reduceMotion ? 0.5 : (shimmer2 ? 0.8 : 0.35))
            }
        }
    }

    private var skeletonTile: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(PanelGround.secondaryText.opacity(0.3))
                .frame(width: 40, height: 6)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(PanelGround.secondaryText.opacity(0.3))
                .frame(width: 56, height: 10)
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                .foregroundStyle(PanelGround.secondaryText.opacity(0.3))
                .frame(height: Chart.tileHeight)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(PanelGround.tileFill))
    }

    private var notice: some View {
        HStack(alignment: .top, spacing: Space.lg) {
            Image(systemName: Icon.systemName(symbol))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(iconTint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(titleTint)
                if let detail {
                    Text(detail).font(.caption2).foregroundStyle(detailTint)
                }
            }
            Spacer(minLength: 4)
            if let secondaryLabel, let secondaryAction {
                Button(secondaryLabel, action: secondaryAction)
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
            }
            if let primaryLabel, let primaryAction {
                Button(primaryLabel, action: primaryAction)
                    .buttonStyle(.borderedProminent)
                    .tint(kind == .error ? HealthState.error.tint : nil)
                    .controlSize(.mini)
            }
        }
        .padding(EdgeInsets(top: 11, leading: 12, bottom: 11, trailing: 12))
        .background(fill)
        .overlay(border)
    }

    private var iconTint: Color {
        switch kind {
        case .error: return HealthState.error.tint
        case .timedOut: return PanelGround.tertiaryText
        default: return PanelGround.secondaryText
        }
    }

    private var titleTint: Color {
        switch kind {
        case .error: return HealthState.error.tint
        case .timedOut: return Color.dynamicOpacity(lightBlack: 0.62, darkWhite: 0.62)
        default: return .primary
        }
    }

    private var detailTint: Color {
        kind == .timedOut ? Color.dynamicOpacity(lightBlack: 0.45, darkWhite: 0.45)
                           : PanelGround.secondaryText
    }

    @ViewBuilder private var fill: some View {
        switch kind {
        case .error:
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(HealthState.error.tint.opacity(0.08))
        default:
            Color.clear
        }
    }

    @ViewBuilder private var border: some View {
        switch kind {
        case .error:
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(HealthState.error.tint.opacity(0.24), lineWidth: 1)
        case .timedOut:
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(Color.dynamicOpacity(lightBlack: 0.22, darkWhite: 0.22))
        default:
            EmptyView()
        }
    }
}
