import SwiftUI

/// Appearance settings: theme, accent color, font size, vibrant transparency.
/// Matches the design with large theme cards, accent swatches, and font preview.
public struct AppearanceSettingsView: View {
    @Environment(\.appearanceManager) private var appearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var baseBodySize: CGFloat = 17

    private static let accentOptions: [(UInt, String)] = [
        (0x007AFF, "Blue"),
        (0xFF3B30, "Red"),
        (0x34C759, "Green"),
        (0xF2994A, "Orange"),
        (0xAF52DE, "Purple"),
        (0xFF2D55, "Pink"),
        (0x8E8E93, "Gray"),
    ]

    public init() {}

    public var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    ForEach(AppearanceManager.Theme.allCases, id: \.self) { theme in
                        ThemeCard(
                            theme: theme,
                            isSelected: appearance.theme == theme
                        ) {
                            withAnimation(reduceMotion ? .default : QuartzAnimation.standard) {
                                appearance.theme = theme
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            } header: {
                Text(String(localized: "Theme", bundle: .module))
            }

            Section {
                HStack(spacing: 12) {
                    ForEach(Array(Self.accentOptions.enumerated()), id: \.offset) { _, item in
                        Button {
                            withAnimation(reduceMotion ? .default : QuartzAnimation.soft) {
                                appearance.accentColorHex = item.0
                            }
                        } label: {
                            accentSwatch(color: Color(hex: item.0), isSelected: appearance.accentColorHex == item.0)
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        // Custom color – future enhancement
                    } label: {
                        Image(systemName: "pencil")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .background(Circle().strokeBorder(.separator, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            } header: {
                Text(String(localized: "Accent Color", bundle: .module))
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(String(localized: "Editor Font Size", bundle: .module))
                            .font(.subheadline)
                        Spacer()
                        Text("\(Int(baseBodySize * appearance.editorFontScale * 0.85))px")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(appearance.accentColor)
                            .monospacedDigit()
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(appearance.accentColor.opacity(0.15))
                            )
                    }

                    Slider(
                        value: Binding(
                            get: { appearance.editorFontScale },
                            set: { appearance.editorFontScale = $0 }
                        ),
                        in: 0.8...2.0,
                        step: 0.1
                    )
                    .tint(appearance.accentColor)

                    Text(String(localized: "The quick brown fox jumps over the lazy dog. Quartz makes note-taking effortless and beautiful.", bundle: .module))
                        .font(.system(size: baseBodySize * appearance.editorFontScale * 0.85))
                        .foregroundStyle(.secondary)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.fill.quaternary.opacity(0.5))
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 2, dash: [8]))
                        }
                        .animation(reduceMotion ? .default : QuartzAnimation.fontScale, value: appearance.editorFontScale)
                }
            } header: {
                Text(String(localized: "Editor", bundle: .module))
            }

            Section {
                Toggle(isOn: Binding(
                    get: { appearance.vibrantTransparency },
                    set: { appearance.vibrantTransparency = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Vibrant Transparency", bundle: .module))
                        Text(String(localized: "Apply a glass effect to sidebar and title bar", bundle: .module))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(appearance.accentColor)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(String(localized: "Appearance", bundle: .module))
    }

    private func accentSwatch(color: Color, isSelected: Bool) -> some View {
        Circle()
            .fill(color)
            .frame(width: 32, height: 32)
            .overlay {
                Circle()
                    .strokeBorder(isSelected ? color : .clear, lineWidth: 3)
            }
    }
}

// MARK: - Theme Card

private struct ThemeCard: View {
    let theme: AppearanceManager.Theme
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.appearanceManager) private var appearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                // Mini preview
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(previewFill)
                    .frame(height: 48)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                isSelected ? appearance.accentColor : .clear,
                                lineWidth: 2.5
                            )
                    }
                    .shadow(color: .black.opacity(0.06), radius: 4, y: 2)

                // Selected indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(appearance.accentColor)
                        .transition(.scale.combined(with: .opacity))
                }

                Text(theme.displayName)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .scaleEffect(isSelected ? 1.05 : 1.0)
            .animation(reduceMotion ? .default : QuartzAnimation.soft, value: isSelected)
        }
        .buttonStyle(QuartzCardButtonStyle())
        .accessibilityLabel(String(localized: "\(theme.displayName) theme", bundle: .module))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var previewFill: some ShapeStyle {
        switch theme {
        case .light:
            return AnyShapeStyle(Color.white)
        case .dark:
            return AnyShapeStyle(Color(white: 0.15))
        case .system:
            return AnyShapeStyle(
                LinearGradient(
                    stops: [
                        .init(color: .white, location: 0.5),
                        .init(color: Color(white: 0.15), location: 0.5)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
    }
}
