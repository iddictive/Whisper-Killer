import SwiftUI

// MARK: - Whisper Free Design System

/// Shared design tokens for the entire app.
/// Extracted from the SetupWizard's premium dark theme.
enum SW {
    // MARK: Colors — Native Premium Palette (Blue/Indigo based)
    static let accent      = Color.accentColor                              // System accent (usually blue)
    static let accentBlue  = Color(red: 0.0, green: 0.48, blue: 1.0)        // Vibrant Blue
    static let accentIndigo = Color(red: 0.35, green: 0.34, blue: 0.84)     // Indigo
    
    static let bg          = Color(red: 0.1, green: 0.1, blue: 0.14)        // Slightly lighter dark background
    static let card        = Color(white: 1.0, opacity: 0.04)               // More subtle card surface
    static let cardHover   = Color(white: 1.0, opacity: 0.07)               // Subtle hover
    static let border      = Color(white: 1.0, opacity: 0.1)                // Clearer border
    static let text1       = Color.white                                    // Primary text
    static let text2       = Color(white: 0.7)                              // More readable secondary text
    static let text3       = Color(white: 0.5)                              // Tertiary text
    
    static let danger      = Color(red: 1.0, green: 0.27, blue: 0.27)       // Refined Red
    static let success     = Color(red: 0.2, green: 0.8, blue: 0.45)        // Refined Green

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
