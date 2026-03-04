import SwiftUI

// MARK: - Whisper Free Design System

/// Shared design tokens for the entire app.
/// Extracted from the SetupWizard's premium dark theme.
enum SW {
    // MARK: Colors
    static let accent = Color(red: 0.0, green: 0.85, blue: 1.0)     // Cyan
    static let bg     = Color(red: 0.07, green: 0.07, blue: 0.12)    // Dark background
    static let card   = Color(white: 1.0, opacity: 0.06)             // Card surface
    static let cardHover = Color(white: 1.0, opacity: 0.09)          // Card hover
    static let border = Color(white: 1.0, opacity: 0.08)             // Subtle borders
    static let text1  = Color.white                                   // Primary text
    static let text2  = Color(white: 0.55)                            // Secondary text
    static let danger = Color(red: 1.0, green: 0.35, blue: 0.35)     // Red/danger
    static let success = Color(red: 0.3, green: 0.85, blue: 0.4)     // Green/success

    // MARK: Spacing
    static let cornerRadius: CGFloat = 12
    static let cardPadding: CGFloat = 14
    static let sectionSpacing: CGFloat = 16
}

// MARK: - Card Modifier

struct SWCard: ViewModifier {
    var isSelected: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(SW.cardPadding)
            .background(SW.card)
            .clipShape(RoundedRectangle(cornerRadius: SW.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: SW.cornerRadius)
                    .strokeBorder(isSelected ? SW.accent.opacity(0.4) : SW.border, lineWidth: 1)
            )
    }
}

extension View {
    func swCard(selected: Bool = false) -> some View {
        modifier(SWCard(isSelected: selected))
    }
}

// MARK: - Section Header

struct SWSectionHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(SW.text2)
            .padding(.top, 4)
    }
}

// MARK: - Pill Button

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
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(color)
            )
        }
        .buttonStyle(.plain)
    }
}
