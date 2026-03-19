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

/// Central color palette for Quartz – inspired by Apple Notes + Liquid Glass.
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
    #if canImport(UIKit)
    public static let sidebarBackground = Color(.systemGroupedBackground)
    public static let cardBackground = Color(.secondarySystemBackground)
    public static let subtleText = Color(.tertiaryLabel)
    #elseif canImport(AppKit)
    public static let sidebarBackground = Color(nsColor: .windowBackgroundColor)
    public static let cardBackground = Color(nsColor: .controlBackgroundColor)
    public static let subtleText = Color(nsColor: .tertiaryLabelColor)
    #endif

    // Accent color
    public static let accent = adaptiveColor(light: 0xF2994A, dark: 0xFFAB5E)

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

    /// Returns a deterministic color for a tag name.
    /// Uses a stable hash (DJB2) instead of `hashValue` which varies across launches.
    public static func tagColor(for tag: String) -> Color {
        var hash: UInt64 = 5381
        for byte in tag.utf8 {
            hash = ((hash &<< 5) &+ hash) &+ UInt64(byte)
        }
        let index = Int(hash % UInt64(tagPalette.count))
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

/// A glassmorphism effect with adjustable transparency and blur.
/// Uses native Liquid Glass (iOS 26+) when available, otherwise material.
public struct GlassBackground: ViewModifier {
    var cornerRadius: CGFloat
    var opacity: Double
    var shadowRadius: CGFloat

    public func body(content: Content) -> some View {
        if #available(iOS 26, macOS 26, *) {
            content
                .glassEffect(in: .rect(cornerRadius: cornerRadius))
                .shadow(color: .black.opacity(0.06), radius: shadowRadius, y: shadowRadius / 3)
        } else {
            content
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .opacity(opacity)
                        .shadow(color: .black.opacity(0.06), radius: shadowRadius, y: shadowRadius / 3)
                }
        }
    }
}

// MARK: - Liquid Glass (iOS 26+)

/// Applies the native Liquid Glass effect when available (iOS 26+), otherwise falls back to material.
/// Use when `vibrantTransparency` is enabled for sidebar and floating surfaces.
public struct QuartzLiquidGlassModifier: ViewModifier {
    var enabled: Bool
    var cornerRadius: CGFloat

    public init(enabled: Bool, cornerRadius: CGFloat = 20) {
        self.enabled = enabled
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        if enabled {
            if #available(iOS 26, macOS 26, *) {
                content.glassEffect(in: .rect(cornerRadius: cornerRadius))
            } else {
                content.background(.ultraThinMaterial)
            }
        } else {
            content
        }
    }
}

public extension View {
    /// Applies Liquid Glass when enabled and available (iOS 26+); otherwise material or no effect.
    func quartzLiquidGlass(enabled: Bool, cornerRadius: CGFloat = 20) -> some View {
        modifier(QuartzLiquidGlassModifier(enabled: enabled, cornerRadius: cornerRadius))
    }

    /// Applies Liquid Glass when available (iOS 26+), otherwise material. Use for toolbars, panels, floating bars.
    /// Set `preferRegularMaterial` to true for floating elements (e.g. search bar) to avoid dark/black rendering.
    func quartzMaterialBackground(cornerRadius: CGFloat = 16, shadowRadius: CGFloat = 0, preferRegularMaterial: Bool = false) -> some View {
        modifier(QuartzMaterialBackgroundModifier(cornerRadius: cornerRadius, shadowRadius: shadowRadius, preferRegularMaterial: preferRegularMaterial))
    }

    /// Applies Liquid Glass to circular views (e.g. icon buttons) when available.
    func quartzMaterialCircle() -> some View {
        modifier(QuartzMaterialCircleModifier())
    }
}

// MARK: - Material Background (always-on Liquid Glass with fallback)

/// Applies Liquid Glass when available (iOS 26+), otherwise material. For toolbars, panels, floating bars.
public struct QuartzMaterialBackgroundModifier: ViewModifier {
    var cornerRadius: CGFloat
    var shadowRadius: CGFloat
    var preferRegularMaterial: Bool

    public init(cornerRadius: CGFloat = 16, shadowRadius: CGFloat = 0, preferRegularMaterial: Bool = false) {
        self.cornerRadius = cornerRadius
        self.shadowRadius = shadowRadius
        self.preferRegularMaterial = preferRegularMaterial
    }

    public func body(content: Content) -> some View {
        Group {
            if #available(iOS 26, macOS 26, *) {
                content
                    .glassEffect(in: .rect(cornerRadius: cornerRadius))
            } else {
                content
                    .background {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(preferRegularMaterial ? .regularMaterial : .ultraThinMaterial)
                    }
            }
        }
        .shadow(color: shadowRadius > 0 ? .black.opacity(0.06) : .clear, radius: shadowRadius, y: shadowRadius / 4)
    }
}

/// Applies Liquid Glass to circular views when available (iOS 26+).
public struct QuartzMaterialCircleModifier: ViewModifier {
    public init() {}

    public func body(content: Content) -> some View {
        Group {
            if #available(iOS 26, macOS 26, *) {
                content.glassEffect(in: Circle())
            } else {
                content.background(Circle().fill(.regularMaterial))
            }
        }
    }
}

// MARK: - Glass Card

/// More subtle glass variant for cards. Uses Liquid Glass when available.
public struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat

    public func body(content: Content) -> some View {
        Group {
            if #available(iOS 26, macOS 26, *) {
                content
                    .glassEffect(in: .rect(cornerRadius: cornerRadius))
            } else {
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
    }
}

/// Floating action button style.
public struct FloatingButtonStyle: ButtonStyle {
    var color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 52, height: 52)
            .background(
                Circle()
                    .fill(color.gradient)
                    .shadow(color: color.opacity(0.4), radius: 12, y: 6)
            )
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(reduceMotion ? .default : QuartzAnimation.soft, value: configuration.isPressed)
    }
}

// MARK: - View Extensions

public extension View {
    /// Glassmorphism background.
    func glassBackground(
        cornerRadius: CGFloat = 16,
        opacity: Double = 1.0,
        shadowRadius: CGFloat = 12
    ) -> some View {
        modifier(GlassBackground(cornerRadius: cornerRadius, opacity: opacity, shadowRadius: shadowRadius))
    }

    /// Glass card style with border highlight.
    func glassCard(cornerRadius: CGFloat = 16) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }

    /// Soft fade-in effect.
    func fadeIn(delay: Double = 0) -> some View {
        modifier(FadeInModifier(delay: delay))
    }

    /// Slide-up appearance.
    func slideUp(delay: Double = 0) -> some View {
        modifier(SlideUpModifier(delay: delay))
    }

    /// Staggered appearance for list elements.
    func staggered(index: Int, baseDelay: Double = 0.05) -> some View {
        modifier(StaggeredAppearModifier(index: index, baseDelay: baseDelay))
    }

    /// Scale-in from the center.
    func scaleIn(delay: Double = 0) -> some View {
        modifier(ScaleInModifier(delay: delay))
    }

    /// Shimmer loading effect.
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }

    /// Soft pulsing.
    func pulse() -> some View {
        modifier(PulseModifier())
    }

    /// Rubber-Band Bounce.
    func bounceIn(delay: Double = 0) -> some View {
        modifier(BounceInModifier(delay: delay))
    }

    /// Rotation appearance.
    func spinIn(delay: Double = 0) -> some View {
        modifier(SpinInModifier(delay: delay))
    }

    /// Parallax scroll effect.
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
                    withAnimation(QuartzAnimation.appear.delay(delay)) {
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
                    withAnimation(QuartzAnimation.slideUp.delay(delay)) {
                        offset = 0
                        opacity = 1
                    }
                }
            }
    }
}

/// Staggered appearance for list elements (index-based).
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
                    withAnimation(QuartzAnimation.stagger.delay(delay)) {
                        isVisible = true
                    }
                }
            }
    }
}

/// Scale-in from the center – for buttons, icons, badges.
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
                    withAnimation(QuartzAnimation.scaleIn.delay(delay)) {
                        scale = 1
                        opacity = 1
                    }
                }
            }
    }
}

/// Shimmer effect for skeleton loading.
/// Automatically stops after 30 seconds to prevent unnecessary off-screen animation.
public struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1
    @State private var isActive = true
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    public func body(content: Content) -> some View {
        if reduceMotion || !isActive {
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
                                QuartzAnimation.shimmer
                                .repeatForever(autoreverses: false)
                            ) {
                                phase = 2
                            }
                        }
                    }
                    .mask(content)
                }
                .task {
                    try? await Task.sleep(for: .seconds(30))
                    guard !Task.isCancelled else { return }
                    withAnimation { isActive = false }
                }
        }
    }
}

/// Soft pulsing – e.g. for the save indicator.
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
                    QuartzAnimation.pulse
                    .repeatForever(autoreverses: true)
                ) {
                    isPulsing = true
                }
            }
    }
}

/// Rubber-band bounce on appearance.
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
                    withAnimation(QuartzAnimation.rubberBand.delay(delay)) {
                        scale = 1
                        opacity = 1
                    }
                }
            }
    }
}

/// Rotation-in – e.g. for checkmarks, icons.
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
                    withAnimation(QuartzAnimation.spinIn.delay(delay)) {
                        rotation = 0
                        opacity = 1
                    }
                }
            }
    }
}

/// Parallax effect based on scroll position.
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

/// Pill-shaped tag badge.
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
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            Capsule()
                .fill(isSelected ? tagColor : tagColor.opacity(0.12))
                .shadow(color: isSelected ? tagColor.opacity(0.3) : .clear, radius: 4, y: 2)
        }
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(reduceMotion ? .default : QuartzAnimation.soft, value: isSelected)
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
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption.weight(.medium))
                    .symbolRenderingMode(.hierarchical)
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

/// Prominent CTA button in Quartz style with press animation.
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
                        .symbolRenderingMode(.hierarchical)
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
        #if os(macOS)
        .focusable()
        #endif
    }
}

/// Press button style: soft press-in + shadow reduction.
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
            .animation(reduceMotion ? .default : QuartzAnimation.buttonPress, value: configuration.isPressed)
    }
}

/// Subtle card button style for interactive cards.
public struct QuartzCardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(reduceMotion ? .default : QuartzAnimation.cardPress, value: configuration.isPressed)
    }
}

/// Bounce button style for small buttons/icons.
public struct QuartzBounceButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.85 : 1.0)
            .animation(reduceMotion ? .default : QuartzAnimation.bounce, value: configuration.isPressed)
    }
}

/// Skeleton Loading Placeholder.
public struct SkeletonRow: View {
    private let titleWidth: CGFloat
    private let subtitleWidth: CGFloat

    public init() {
        titleWidth = .random(in: 80...160)
        subtitleWidth = .random(in: 50...100)
    }

    public var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(.fill.tertiary)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.fill.tertiary)
                    .frame(width: titleWidth, height: 12)

                RoundedRectangle(cornerRadius: 3)
                    .fill(.fill.quaternary)
                    .frame(width: subtitleWidth, height: 8)
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .shimmer()
    }
}

/// Empty state display with illustration.
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
                .font(.largeTitle.weight(.regular))
                .imageScale(.large)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.quaternary)

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
        .padding(48)
        .accessibilityElement(children: .combine)
    }
}
