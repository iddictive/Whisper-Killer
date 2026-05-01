import SwiftUI
import AppKit

enum SW {
    static let accent = Color.accentColor
    static let accentBlue = Color.accentColor
    static let accentIndigo = Color.accentColor
    static let success = Color.accentColor
    static let warning = Color.orange
    static let danger = Color.red

    static let windowBackground = Color(NSColor.windowBackgroundColor)
    static let sidebarBackground = Color(NSColor.controlBackgroundColor)
    static let contentBackground = Color(NSColor.textBackgroundColor).opacity(0.55)
    static let rowBackground = Color.primary.opacity(0.045)
    static let rowHover = Color.primary.opacity(0.075)
    static let card = Color.primary.opacity(0.045)
    static let cardHover = Color.primary.opacity(0.075)
    static let border = Color.primary.opacity(0.10)
    static let separator = Color.primary.opacity(0.08)
    static let primaryText = Color.primary
    static let secondaryText = Color.secondary
    static let tertiaryText = Color.secondary.opacity(0.72)

    static let bg = windowBackground
    static let text1 = primaryText
    static let text2 = secondaryText
    static let text3 = tertiaryText

    static let radiusSmall: CGFloat = 6
    static let radiusMedium: CGFloat = 8
    static let radiusLarge: CGFloat = 10
    static let cornerRadius = radiusMedium

    static let spacingXS: CGFloat = 4
    static let spacingS: CGFloat = 8
    static let spacingM: CGFloat = 12
    static let spacingL: CGFloat = 16
    static let spacingXL: CGFloat = 20
    static let cardPadding: CGFloat = 12
    static let sectionSpacing: CGFloat = 16

    static let titleFont = Font.system(size: 13, weight: .semibold)
    static let bodyFont = Font.system(size: 12)
    static let compactFont = Font.system(size: 11)
    static let labelFont = Font.system(size: 10, weight: .semibold)
    static let monoFont = Font.system(size: 10, weight: .medium, design: .monospaced)
}

struct SWCard: ViewModifier {
    var isSelected: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(SW.cardPadding)
            .background(isSelected ? SW.accent.opacity(0.08) : SW.card)
            .clipShape(RoundedRectangle(cornerRadius: SW.radiusMedium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SW.radiusMedium, style: .continuous)
                    .strokeBorder(isSelected ? SW.accent.opacity(0.35) : SW.border, lineWidth: 1)
            )
    }
}

extension View {
    func swCard(selected: Bool = false) -> some View {
        modifier(SWCard(isSelected: selected))
    }
}

struct SWSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(SW.labelFont)
            .foregroundStyle(SW.secondaryText)
    }
}

struct SWStatusBadge: View {
    let title: String
    let icon: String?
    var color: Color = SW.secondaryText

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
            }
            Text(title)
                .font(SW.labelFont)
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.11))
        .clipShape(RoundedRectangle(cornerRadius: SW.radiusSmall, style: .continuous))
    }
}

struct SWMetricBadge: View {
    let title: String
    let value: String
    var icon: String?
    var color: Color = SW.secondaryText

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
            }
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(SW.tertiaryText)
            Text(value)
                .font(SW.monoFont)
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(SW.rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: SW.radiusSmall, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SW.radiusSmall, style: .continuous)
                .strokeBorder(SW.border, lineWidth: 1)
        )
    }
}

struct SWIconButton: View {
    let icon: String
    var title: String?
    var role: ButtonRole?
    var color: Color = SW.primaryText
    var action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                if let title {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .foregroundStyle(color)
            .padding(.horizontal, title == nil ? 7 : 9)
            .padding(.vertical, 5)
            .background(SW.rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: SW.radiusSmall, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct SWPillButton: View {
    let title: String
    let icon: String
    var color: Color = SW.accent
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundStyle(.white)
            .background(RoundedRectangle(cornerRadius: SW.radiusMedium, style: .continuous).fill(color))
        }
        .buttonStyle(.plain)
    }
}

struct SWEmptyState: View {
    let icon: String
    let title: String
    let detail: String?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(SW.tertiaryText)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            if let detail {
                Text(detail)
                    .font(SW.compactFont)
                    .foregroundStyle(SW.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}
