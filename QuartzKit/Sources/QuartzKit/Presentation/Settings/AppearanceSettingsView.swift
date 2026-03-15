import SwiftUI

/// Einstellungen für Erscheinungsbild: Theme, Schriftgröße.
/// Cleanes Apple-Design mit visuellen Theme-Karten.
public struct AppearanceSettingsView: View {
    @Environment(\.appearanceManager) private var appearance

    public init() {}

    public var body: some View {
        Form {
            // Theme Picker
            Section {
                HStack(spacing: 12) {
                    ForEach(AppearanceManager.Theme.allCases, id: \.self) { theme in
                        ThemeCard(
                            theme: theme,
                            isSelected: appearance.theme == theme
                        ) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                appearance.theme = theme
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            } header: {
                QuartzSectionHeader("Theme", icon: "paintbrush")
            }

            // Editor Font Size
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(String(localized: "Editor Font Size", bundle: .module))
                            .font(.subheadline)
                        Spacer()
                        Text("\(Int(appearance.editorFontScale * 100))%")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(.fill.tertiary)
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
                    .tint(Color(hex: 0xF2994A))

                    Text("The quick brown fox jumps over the lazy dog.")
                        .font(.system(size: 16 * appearance.editorFontScale))
                        .foregroundStyle(.secondary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(.fill.quaternary)
                        )
                        .animation(.spring(response: 0.3), value: appearance.editorFontScale)
                }
            } header: {
                QuartzSectionHeader("Editor", icon: "textformat.size")
            }
        }
        .navigationTitle(String(localized: "Appearance", bundle: .module))
    }
}

// MARK: - Theme Card

private struct ThemeCard: View {
    let theme: AppearanceManager.Theme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                // Mini preview
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(previewFill)
                    .frame(height: 48)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                isSelected ? Color.accentColor : .clear,
                                lineWidth: 2.5
                            )
                    }
                    .shadow(color: .black.opacity(0.06), radius: 4, y: 2)

                // Selected indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                        .transition(.scale.combined(with: .opacity))
                }

                Text(theme.displayName)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .scaleEffect(isSelected ? 1.05 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
        }
        .buttonStyle(QuartzCardButtonStyle())
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
