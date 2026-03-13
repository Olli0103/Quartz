import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Adaptive Color Helper

/// Creates a Color that adapts between light and dark mode.
private func adaptiveColor(light: UInt, dark: UInt) -> Color {
    #if canImport(UIKit)
    return Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(
                red: CGFloat((dark >> 16) & 0xFF) / 255.0,
                green: CGFloat((dark >> 8) & 0xFF) / 255.0,
                blue: CGFloat(dark & 0xFF) / 255.0,
                alpha: 1.0
            )
            : UIColor(
                red: CGFloat((light >> 16) & 0xFF) / 255.0,
                green: CGFloat((light >> 8) & 0xFF) / 255.0,
                blue: CGFloat(light & 0xFF) / 255.0,
                alpha: 1.0
            )
    })
    #elseif canImport(AppKit)
    return Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let hex = isDark ? dark : light
        return NSColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: 1.0
        )
    })
    #endif
}

// MARK: - Quartz Color Palette

/// Zentrale Farbpalette für Quartz – inspiriert von Apple Notes + Liquid Glass.
public enum QuartzColors {
    // Primary brand gradient (slightly desaturated/brightened in dark mode)
    public static let accentGradient = LinearGradient(
        colors: [
            adaptiveColor(light: 0xF7C948, dark: 0xFFD95A),
            adaptiveColor(light: 0xF2994A, dark: 0xFFAB5E),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let warmGradient = LinearGradient(
        colors: [
            adaptiveColor(light: 0xFDCB6E, dark: 0xFFD97F),
            adaptiveColor(light: 0xE17055, dark: 0xF08070),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let coolGradient = LinearGradient(
        colors: [
            adaptiveColor(light: 0x74B9FF, dark: 0x8AC4FF),
            adaptiveColor(light: 0xA29BFE, dark: 0xB5AFFE),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // Semantic colors
    public static let sidebarBackground = Color("SidebarBG", bundle: nil)
    #if canImport(UIKit)
    public static let cardBackground = Color(.secondarySystemBackground)
    public static let subtleText = Color(.tertiaryLabel)
    #elseif canImport(AppKit)
    public static let cardBackground = Color(nsColor: .controlBackgroundColor)
    public static let subtleText = Color(nsColor: .tertiaryLabelColor)
    #endif

    // Node type colors (brighter variants for dark mode)
    public static let folderYellow = adaptiveColor(light: 0xFDCB6E, dark: 0xFFD97F)
    public static let noteBlue = adaptiveColor(light: 0x74B9FF, dark: 0x8AC4FF)
    public static let assetOrange = adaptiveColor(light: 0xE17055, dark: 0xF08070)
    public static let canvasPurple = adaptiveColor(light: 0xA29BFE, dark: 0xB5AFFE)

    // Tag colors – cycle for variety (with dark mode variants)
    public static let tagPalette: [Color] = [
        adaptiveColor(light: 0x74B9FF, dark: 0x8AC4FF),
        adaptiveColor(light: 0xA29BFE, dark: 0xB5AFFE),
        adaptiveColor(light: 0xFD79A8, dark: 0xFF8FB8),
        adaptiveColor(light: 0xFDCB6E, dark: 0xFFD97F),
        adaptiveColor(light: 0x55EFC4, dark: 0x6FF5D0),
        adaptiveColor(light: 0xE17055, dark: 0xF08070),
        adaptiveColor(light: 0x00CEC9, dark: 0x20DED9),
        adaptiveColor(light: 0x6C5CE7, dark: 0x8577F0),
    ]

    public static func tagColor(for tag: String) -> Color {
        let index = abs(tag.hashValue) % tagPalette.count
        return tagPalette[index]
    }
}

// MARK: - Hex Color Init

public extension Color {
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            .animation(reduceMotion ? .default : .spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
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

    /// Staggered-Einblendung für Listen-Elemente.
    func staggered(index: Int, baseDelay: Double = 0.05) -> some View {
        modifier(StaggeredAppearModifier(index: index, baseDelay: baseDelay))
    }

    /// Scale-In von der Mitte.
    func scaleIn(delay: Double = 0) -> some View {
        modifier(ScaleInModifier(delay: delay))
    }

    /// Shimmer-Loading-Effekt.
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }

    /// Sanftes Pulsieren.
    func pulse() -> some View {
        modifier(PulseModifier())
    }

    /// Rubber-Band Bounce.
    func bounceIn(delay: Double = 0) -> some View {
        modifier(BounceInModifier(delay: delay))
    }

    /// Rotation-Einblendung.
    func spinIn(delay: Double = 0) -> some View {
        modifier(SpinInModifier(delay: delay))
    }

    /// Parallax-Scroll-Effekt.
    func parallax(strength: CGFloat = 40) -> some View {
        modifier(ParallaxModifier(strength: strength))
    }
}

// MARK: - Animation Modifiers

private struct FadeInModifier: ViewModifier {
    let delay: Double
    @State private var opacity: Double = 0
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .onAppear {
                if reduceMotion {
                    opacity = 1
                } else {
                    withAnimation(.easeOut(duration: 0.4).delay(delay)) {
                        opacity = 1
                    }
                }
            }
    }
}

private struct SlideUpModifier: ViewModifier {
    let delay: Double
    @State private var offset: CGFloat = 20
    @State private var opacity: Double = 0
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    func body(content: Content) -> some View {
        content
            .offset(y: offset)
            .opacity(opacity)
            .onAppear {
                if reduceMotion {
                    offset = 0
                    opacity = 1
                } else {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(delay)) {
                        offset = 0
                        opacity = 1
                    }
                }
            }
    }
}

/// Staggered-Einblendung für Listen-Elemente (Index-basiert).
private struct StaggeredAppearModifier: ViewModifier {
    let index: Int
    let baseDelay: Double
    @State private var isVisible = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 12)
            .scaleEffect(isVisible ? 1 : 0.97)
            .onAppear {
                if reduceMotion {
                    isVisible = true
                } else {
                    let delay = baseDelay + Double(index) * 0.04
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.82).delay(delay)) {
                        isVisible = true
                    }
                }
            }
    }
}

/// Scale-In von der Mitte – für Buttons, Icons, Badges.
private struct ScaleInModifier: ViewModifier {
    let delay: Double
    @State private var scale: CGFloat = 0.6
    @State private var opacity: Double = 0
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                if reduceMotion {
                    scale = 1
                    opacity = 1
                } else {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.7).delay(delay)) {
                        scale = 1
                        opacity = 1
                    }
                }
            }
    }
}

/// Shimmer-Effekt für Skeleton Loading.
public struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    public func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content
                .overlay {
                    GeometryReader { geo in
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: max(0, phase - 0.3)),
                                .init(color: .white.opacity(0.15), location: phase),
                                .init(color: .clear, location: min(1, phase + 0.3)),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .frame(width: geo.size.width, height: geo.size.height)
                        .onAppear {
                            withAnimation(
                                .linear(duration: 1.5)
                                .repeatForever(autoreverses: false)
                            ) {
                                phase = 2
                            }
                        }
                    }
                    .mask(content)
                }
        }
    }
}

/// Sanftes Pulsieren – z.B. für den Save-Indikator.
private struct PulseModifier: ViewModifier {
    @State private var isPulsing = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.15 : 1.0)
            .opacity(isPulsing ? 0.7 : 1.0)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(
                    .easeInOut(duration: 0.8)
                    .repeatForever(autoreverses: true)
                ) {
                    isPulsing = true
                }
            }
    }
}

/// Rubber-Band Bounce bei Erscheinen.
private struct BounceInModifier: ViewModifier {
    let delay: Double
    @State private var scale: CGFloat = 0.3
    @State private var opacity: Double = 0
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                if reduceMotion {
                    scale = 1
                    opacity = 1
                } else {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.55).delay(delay)) {
                        scale = 1
                        opacity = 1
                    }
                }
            }
    }
}

/// Rotation-In – z.B. für Checkmarks, Icons.
private struct SpinInModifier: ViewModifier {
    let delay: Double
    @State private var rotation: Double = -90
    @State private var opacity: Double = 0
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(rotation))
            .opacity(opacity)
            .onAppear {
                if reduceMotion {
                    rotation = 0
                    opacity = 1
                } else {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(delay)) {
                        rotation = 0
                        opacity = 1
                    }
                }
            }
    }
}

/// Parallax-Effekt basierend auf Scroll-Position.
public struct ParallaxModifier: ViewModifier {
    let strength: CGFloat
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    public func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            GeometryReader { geo in
                let midY = geo.frame(in: .global).midY
                let viewHeight = geo.size.height
                let offset = (midY / max(viewHeight, 1) - 1) * strength

                content
                    .offset(y: offset)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                .shadow(color: isSelected ? tagColor.opacity(0.3) : .clear, radius: 4, y: 2)
        }
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(reduceMotion ? .default : .spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
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

/// Prominenter CTA-Button im Quartz-Stil mit Press-Animation.
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
        .buttonStyle(QuartzPressButtonStyle())
    }
}

/// Press-ButtonStyle: sanftes Eindrücken + Schatten-Reduktion.
public struct QuartzPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .shadow(
                color: Color.accentColor.opacity(configuration.isPressed ? 0.1 : 0.3),
                radius: configuration.isPressed ? 4 : 12,
                y: configuration.isPressed ? 2 : 6
            )
            .animation(reduceMotion ? .default : .spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Subtiler Card-ButtonStyle für interaktive Karten.
public struct QuartzCardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(reduceMotion ? .default : .spring(response: 0.2, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

/// Bounce-ButtonStyle für kleine Buttons/Icons.
public struct QuartzBounceButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.85 : 1.0)
            .animation(reduceMotion ? .default : .spring(response: 0.25, dampingFraction: 0.5), value: configuration.isPressed)
    }
}

/// Skeleton Loading Placeholder.
public struct SkeletonRow: View {
    public init() {}

    public var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(.fill.tertiary)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.fill.tertiary)
                    .frame(width: .random(in: 80...160), height: 12)

                RoundedRectangle(cornerRadius: 3)
                    .fill(.fill.quaternary)
                    .frame(width: .random(in: 50...100), height: 8)
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .shimmer()
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
