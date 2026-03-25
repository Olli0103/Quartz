import SwiftUI

/// Dropdown menu for quickly selecting heading levels (H1-H6) or converting to paragraph.
/// Provides keyboard shortcuts Cmd+1 through Cmd+6 for direct heading selection.
struct HeadingDropdown: View {
    let onHeading: (FormattingAction) -> Void

    var body: some View {
        Menu {
            Button {
                onHeading(.paragraph)
            } label: {
                Label(FormattingAction.paragraph.label, systemImage: FormattingAction.paragraph.icon)
            }
            .keyboardShortcut("0", modifiers: .command)

            Divider()

            ForEach(1...6, id: \.self) { level in
                let action = headingAction(for: level)
                Button {
                    onHeading(action)
                } label: {
                    headingLabel(level: level)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(level)")), modifiers: .command)
            }
        } label: {
            Image(systemName: "textformat.size.larger")
                .font(.system(size: iconSize, weight: iconWeight))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary)
                .frame(minWidth: 44, minHeight: 44)
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel(String(localized: "Heading level", bundle: .module))
        .help(String(localized: "Change heading level (⌘1-6)", bundle: .module))
    }

    private func headingAction(for level: Int) -> FormattingAction {
        switch level {
        case 1: .heading1
        case 2: .heading2
        case 3: .heading3
        case 4: .heading4
        case 5: .heading5
        case 6: .heading6
        default: .heading1
        }
    }

    @ViewBuilder
    private func headingLabel(level: Int) -> some View {
        let action = headingAction(for: level)
        HStack {
            Text(action.label)
            Spacer()
            Text(String(repeating: "#", count: level))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private var iconSize: CGFloat {
        #if os(macOS)
        17
        #else
        14
        #endif
    }

    private var iconWeight: Font.Weight {
        #if os(macOS)
        .semibold
        #else
        .medium
        #endif
    }
}

#if DEBUG
#Preview {
    HeadingDropdown { action in
        print("Selected: \(action)")
    }
    .padding()
}
#endif
