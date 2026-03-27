import SwiftUI

/// Appearance settings: theme, accent color, font size, vibrant transparency.
public struct AppearanceSettingsView: View {
    @Environment(\.appearanceManager) private var appearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            // MARK: - Theme
            Section {
                Picker(selection: Binding(
                    get: { appearance.theme },
                    set: { newTheme in
                        withAnimation(reduceMotion ? .default : QuartzAnimation.standard) {
                            appearance.theme = newTheme
                        }
                    }
                )) {
                    ForEach(AppearanceManager.Theme.allCases, id: \.self) { theme in
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(themeFill(for: theme))
                                .frame(width: 24, height: 16)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .strokeBorder(.quaternary, lineWidth: 0.5)
                                }
                            Text(theme.displayName)
                        }
                        .tag(theme)
                    }
                } label: {
                    Text(String(localized: "Theme", bundle: .module))
                }
                .pickerStyle(.inline)
            } header: {
                Text(String(localized: "Theme", bundle: .module))
            }

            // MARK: - Accent Color
            Section {
                HStack(spacing: 10) {
                    ForEach(Array(Self.accentOptions.enumerated()), id: \.offset) { _, item in
                        Button {
                            withAnimation(reduceMotion ? .default : QuartzAnimation.soft) {
                                appearance.accentColorHex = item.0
                            }
                        } label: {
                            accentSwatch(color: Color(hex: item.0), isSelected: appearance.accentColorHex == item.0)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(item.1)
                        .accessibilityAddTraits(appearance.accentColorHex == item.0 ? .isSelected : [])
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            } header: {
                Text(String(localized: "Accent Color", bundle: .module))
            }

            // MARK: - Editor Font Size
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(String(localized: "Editor Font Size", bundle: .module))
                            .font(.subheadline)
                        Spacer()
                        Text("\(Int(appearance.editorFontSize))pt")
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
                            get: { appearance.editorFontSize },
                            set: { appearance.editorFontSize = $0 }
                        ),
                        in: 12...24,
                        step: 1
                    )
                    .tint(appearance.accentColor)

                    Text(String(localized: "The quick brown fox jumps over the lazy dog.", bundle: .module))
                        .font(.system(size: appearance.editorFontSize))
                        .foregroundStyle(.secondary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(.fill.quaternary)
                        )
                        .animation(.smooth(duration: 0.2), value: appearance.editorFontSize)
                }
            } header: {
                Text(String(localized: "Editor", bundle: .module))
            }

            // MARK: - Visual Effects
            Section {
                Toggle(isOn: Binding(
                    get: { appearance.vibrantTransparency },
                    set: { appearance.vibrantTransparency = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Vibrant Transparency", bundle: .module))
                        Text(String(localized: "Apply a translucent glass effect to sidebar and toolbars", bundle: .module))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(appearance.accentColor)

                Toggle(isOn: Binding(
                    get: { appearance.pureDarkMode },
                    set: { appearance.pureDarkMode = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Pure Dark Mode", bundle: .module))
                        Text(String(localized: "True black background for OLED displays", bundle: .module))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(appearance.accentColor)
                .disabled(appearance.theme == .light)
            } header: {
                Text(String(localized: "Visual Effects", bundle: .module))
            }

            #if os(macOS)
            // MARK: - Dashboard
            Section {
                Toggle(isOn: Binding(
                    get: { appearance.showDashboardOnLaunch },
                    set: { appearance.showDashboardOnLaunch = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Show Dashboard", bundle: .module))
                        Text(String(localized: "Display the command center when no note is selected", bundle: .module))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(appearance.accentColor)
            } header: {
                Text(String(localized: "Dashboard", bundle: .module))
            }
            #endif
        }
        .formStyle(.grouped)
        .navigationTitle(String(localized: "Appearance", bundle: .module))
    }

    // MARK: - Accent Swatch

    private func accentSwatch(color: Color, isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: 28, height: 28)

            if isSelected {
                Circle()
                    .strokeBorder(.white, lineWidth: 2)
                    .frame(width: 28, height: 28)

                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 34, height: 34)
        .background(
            Circle()
                .strokeBorder(isSelected ? color : .clear, lineWidth: 2.5)
        )
    }

    // MARK: - Theme Fill

    private func themeFill(for theme: AppearanceManager.Theme) -> some ShapeStyle {
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
