import SwiftUI

// MARK: - Quartz Color Palette

/// Zentrale Farbpalette für Quartz – inspiriert von Apple Notes + Liquid Glass.
public enum QuartzColors {
    // Primary brand gradient
    public static let accentGradient = LinearGradient(
        colors: [Color(hex: 0xF7C948), Color(hex: 0xF2994A)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let warmGradient = LinearGradient(
        colors: [Color(hex: 0xFDCB6E), Color(hex: 0xE17055)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let coolGradient = LinearGradient(
        colors: [Color(hex: 0x74B9FF), Color(hex: 0xA29BFE)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // Semantic colors
    public static let sidebarBackground = Color("SidebarBG", bundle: nil)
    public static let cardBackground = Color(.secondarySystemBackground)
    public static let subtleText = Color(.tertiaryLabel)

    // Node type colors
    public static let folderYellow = Color(hex: 0xFDCB6E)
    public static let noteBlue = Color(hex: 0x74B9FF)
    public static let assetOrange = Color(hex: 0xE17055)
    public static let canvasPurple = Color(hex: 0xA29BFE)

    // Tag colors – cycle for variety
    public static let tagPalette: [Color] = [
        Color(hex: 0x74B9FF),
        Color(hex: 0xA29BFE),
        Color(hex: 0xFD79A8),
        Color(hex: 0xFDCB6E),
        Color(hex: 0x55EFC4),
        Color(hex: 0xE17055),
        Color(hex: 0x00CEC9),
        Color(hex: 0x6C5CE7),
    ]

    public static func tagColor(for tag: String) -> Color {
        let index = abs(tag.hashValue) % tagPalette.count
        return tagPalette[index]
    }
}

// MARK: - Hex Color Init

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: alpha
        )
    }
}

// MARK: - Liquid Glass Material

/// Ein Glasmorphismus-Effekt mit anpassbarer Transparenz und Blur.
public struct GlassBackground: ViewModifier {
    var cornerRadius: CGFloat
    var opacity: Double
    var shadowRadius: CGFloat

    public func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .opacity(opacity)
                    .shadow(color: .black.opacity(0.06), radius: shadowRadius, y: shadowRadius / 3)
            }
    }
}

/// Subtilere Glas-Variante für Karten.
public struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat

    public func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.04), radius: 8, y: 4)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.3), .white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            }
    }
}

/// Floating Action Button Stil.
public struct FloatingButtonStyle: ButtonStyle {
    var color: Color

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 52, height: 52)
            .background(
                Circle()
                    .fill(color.gradient)
                    .shadow(color: color.opacity(0.4), radius: 12, y: 6)
            )
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - View Extensions

public extension View {
    /// Glasmorphismus-Hintergrund.
    func glassBackground(
        cornerRadius: CGFloat = 16,
        opacity: Double = 1.0,
        shadowRadius: CGFloat = 12
    ) -> some View {
        modifier(GlassBackground(cornerRadius: cornerRadius, opacity: opacity, shadowRadius: shadowRadius))
    }

    /// Glas-Karten-Stil mit Border-Highlight.
    func glassCard(cornerRadius: CGFloat = 16) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }

    /// Sanfter Einblend-Effekt.
    func fadeIn(delay: Double = 0) -> some View {
        modifier(FadeInModifier(delay: delay))
    }

    /// Slide-up-Einblendung.
    func slideUp(delay: Double = 0) -> some View {
        modifier(SlideUpModifier(delay: delay))
    }
}

// MARK: - Animation Modifiers

private struct FadeInModifier: ViewModifier {
    let delay: Double
    @State private var opacity: Double = 0

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeOut(duration: 0.4).delay(delay)) {
                    opacity = 1
                }
            }
    }
}

private struct SlideUpModifier: ViewModifier {
    let delay: Double
    @State private var offset: CGFloat = 20
    @State private var opacity: Double = 0

    func body(content: Content) -> some View {
        content
            .offset(y: offset)
            .opacity(opacity)
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(delay)) {
                    offset = 0
                    opacity = 1
                }
            }
    }
}

// MARK: - Reusable Components

/// Pill-förmiger Tag-Badge.
public struct QuartzTagBadge: View {
    public let text: String
    public var isSelected: Bool = false
    public var showHash: Bool = true

    public init(text: String, isSelected: Bool = false, showHash: Bool = true) {
        self.text = text
        self.isSelected = isSelected
        self.showHash = showHash
    }

    private var tagColor: Color {
        QuartzColors.tagColor(for: text)
    }

    public var body: some View {
        HStack(spacing: 3) {
            if showHash {
                Text("#")
                    .fontWeight(.bold)
                    .foregroundStyle(isSelected ? .white : tagColor)
            }
            Text(text)
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background {
            Capsule()
                .fill(isSelected ? tagColor : tagColor.opacity(0.12))
        }
    }
}

/// Quartz-styled Section Header.
public struct QuartzSectionHeader: View {
    public let title: String
    public var icon: String?

    public init(_ title: String, icon: String? = nil) {
        self.title = title
        self.icon = icon
    }

    public var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
        }
    }
}

/// Prominenter CTA-Button im Quartz-Stil.
public struct QuartzButton: View {
    public let title: String
    public let icon: String?
    public let action: () -> Void

    public init(_ title: String, icon: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.body.weight(.semibold))
                }
                Text(title)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.accentColor.gradient)
            }
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}

/// Leere-State Darstellung mit Illustration.
public struct QuartzEmptyState: View {
    public let icon: String
    public let title: String
    public let subtitle: String

    public init(icon: String, title: String, subtitle: String) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
    }

    public var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)
                .symbolEffect(.pulse, options: .repeating)

            VStack(spacing: 6) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(40)
    }
}
