# Research: SwiftUI List Selection Patterns

**Date**: 2024-03-24
**Topic**: NavigationSplitView, List(selection:), hierarchical data
**Platforms**: iOS 18+, macOS 15+

---

## Official Documentation

- [NavigationSplitView](https://developer.apple.com/documentation/SwiftUI/NavigationSplitView)
- [List](https://developer.apple.com/documentation/swiftui/list)
- [OutlineGroup](https://developer.apple.com/documentation/swiftui/outlinegroup)
- [Migrating to New Navigation Types](https://developer.apple.com/documentation/SwiftUI/Migrating-to-New-Navigation-Types)

## Key WWDC Sessions

- **WWDC 2022 - "The SwiftUI Cookbook for Navigation"** (10054) - Definitive guide
- **WWDC 2024 - "What's new in SwiftUI"** (10144)
- **WWDC 2024 - "Demystify SwiftUI containers"** (10146)
- **WWDC 2025 - "What's new in SwiftUI"** (256) - Enhanced drag container APIs

---

## Apple's Recommended Pattern

### List with Selection Binding

```swift
struct SidebarView: View {
    @Binding var selectedItem: Item.ID?

    var body: some View {
        List(selection: $selectedItem) {
            ForEach(items) { item in
                NavigationLink(value: item) {
                    ItemRow(item: item)
                }
            }
        }
    }
}
```

**Key points:**
1. `List(selection:)` binding type must match item ID type
2. Use `NavigationLink(value:)` inside the List - it automatically updates selection
3. SwiftUI handles selection highlighting, accessibility, keyboard navigation
4. On compact layouts, SwiftUI translates selection to stack navigation

### Hierarchical Data

For tree structures, use **OutlineGroup** or **List with children parameter**:

```swift
// Option 1: OutlineGroup
List(selection: $selectedURL) {
    OutlineGroup(fileTree, children: \.children) { node in
        NavigationLink(value: node.url) {
            FileNodeRow(node: node)
        }
    }
}

// Option 2: List with children parameter
List(fileTree, children: \.children, selection: $selectedURL) { node in
    NavigationLink(value: node.url) {
        FileNodeRow(node: node)
    }
}
```

**Do NOT use DisclosureGroup** for selectable hierarchical data - it doesn't integrate with List selection.

---

## What Breaks Selection

### 1. Manual Tap Gestures (CRITICAL)

```swift
// ❌ WRONG - Breaks native selection
.onTapGesture {
    selectedItem = item
}

// ❌ WRONG - Also breaks selection
.gesture(TapGesture().onEnded { ... })
```

**Why it breaks:**
- Manual gestures intercept touch before List's selection handling
- Bypasses edit mode requirement on iOS
- Loses VoiceOver announcements ("selected")
- Loses keyboard navigation support
- Loses native highlight appearance

### 2. DisclosureGroup for Trees

```swift
// ❌ WRONG - DisclosureGroup doesn't participate in List selection
DisclosureGroup {
    ForEach(children) { child in
        // Children can't be selected via List(selection:)
    }
} label: {
    Text(folder.name)
}
```

### 3. Missing NavigationLink

```swift
// ❌ WRONG - No NavigationLink means no selection coordination
List(selection: $selected) {
    ForEach(items) { item in
        Text(item.name)  // Won't update selection binding
    }
}

// ✅ CORRECT
List(selection: $selected) {
    ForEach(items) { item in
        NavigationLink(value: item.id) {
            Text(item.name)
        }
    }
}
```

---

## Drag and Drop with Selection

### WWDC 2025 Pattern

```swift
List(selection: $selectedItems) {
    ForEach(items) { item in
        ItemRow(item: item)
            .draggable(item)
    }
}
.dropDestination(for: Item.self) { items, location in
    // Handle drop
}
```

For multi-selection drag:

```swift
.dragContainer(for: Item.self, selection: $selectedItems) { draggedIDs in
    items.filter { draggedIDs.contains($0.id) }
}
```

**Key insight**: Drag and selection work together when using proper List patterns.

---

## Platform Differences

| Behavior | iOS | macOS |
|----------|-----|-------|
| Selection without edit mode | Requires NavigationLink | Works directly |
| Multi-selection | Requires EditButton + edit mode | Works with ⌘-click |
| Keyboard navigation | Limited | Full arrow key support |
| Selection highlight | System blue tint | System accent color |

---

## Correct Implementation for Quartz (IMPLEMENTED)

The sidebar was refactored to use Apple's documented patterns:

```swift
public struct SidebarView: View {
    @Binding var selectedNoteURL: URL?
    @Bindable var viewModel: SidebarViewModel

    var body: some View {
        // Native List with selection binding
        List(selection: $selectedNoteURL) {
            // Non-selectable sections (Quick Access, Tags)
            Section("Quick Access") {
                // Use Button, not tagged content
            }

            // File tree with OutlineGroup
            Section("Folders") {
                OutlineGroup(viewModel.filteredTree, children: \.children) { node in
                    if node.isNote {
                        FileNodeRow(node: node)
                            .tag(node.url)  // Makes row selectable
                            .draggable(...)
                            .contextMenu { ... }
                    } else {
                        FileNodeRow(node: node)
                            .draggable(...)
                            .dropDestination(...)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}
```

**Key changes made:**
1. Added `List(selection: $selectedNoteURL)` binding
2. Replaced `DisclosureGroup` with `OutlineGroup` for native hierarchy
3. Used `.tag(node.url)` on note rows for selection participation
4. Removed all manual `onTapGesture` and `TapGesture` handlers
5. Removed `NavigationLink` (not needed when manually managing detail column)
6. Double-click on macOS → use context menu "Open in New Window"

---

## References

- WWDC 2022 Session 10054: https://developer.apple.com/videos/play/wwdc2022/10054/
- WWDC 2025 Session 256: https://developer.apple.com/videos/play/wwdc2025/256/
- Apple Sample Code: https://developer.apple.com/documentation/swiftui/bringing_robust_navigation_structure_to_your_swiftui_app
