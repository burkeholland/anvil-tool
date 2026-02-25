import SwiftUI

// MARK: - Focused Values

/// Keys for communicating state between ContentView and menu Commands.
struct SidebarVisibleKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

struct SidebarTabKey: FocusedValueKey {
    typealias Value = Binding<SidebarTab>
}

struct PreviewOpenKey: FocusedValueKey {
    typealias Value = Bool
}

struct ClosePreviewKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct OpenDirectoryKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct RefreshKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct QuickOpenKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct AutoFollowKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

struct FindInProjectKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct CloseProjectKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct IncreaseFontSizeKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct DecreaseFontSizeKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct ResetFontSizeKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct NewTerminalTabKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct FindInTerminalKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct ShowCommandPaletteKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct NextChangeKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct PreviousChangeKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct ReviewAllChangesKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var sidebarVisible: Binding<Bool>? {
        get { self[SidebarVisibleKey.self] }
        set { self[SidebarVisibleKey.self] = newValue }
    }

    var sidebarTab: Binding<SidebarTab>? {
        get { self[SidebarTabKey.self] }
        set { self[SidebarTabKey.self] = newValue }
    }

    var previewOpen: Bool? {
        get { self[PreviewOpenKey.self] }
        set { self[PreviewOpenKey.self] = newValue }
    }

    var closePreview: (() -> Void)? {
        get { self[ClosePreviewKey.self] }
        set { self[ClosePreviewKey.self] = newValue }
    }

    var openDirectory: (() -> Void)? {
        get { self[OpenDirectoryKey.self] }
        set { self[OpenDirectoryKey.self] = newValue }
    }

    var refresh: (() -> Void)? {
        get { self[RefreshKey.self] }
        set { self[RefreshKey.self] = newValue }
    }

    var quickOpen: (() -> Void)? {
        get { self[QuickOpenKey.self] }
        set { self[QuickOpenKey.self] = newValue }
    }

    var autoFollow: Binding<Bool>? {
        get { self[AutoFollowKey.self] }
        set { self[AutoFollowKey.self] = newValue }
    }

    var findInProject: (() -> Void)? {
        get { self[FindInProjectKey.self] }
        set { self[FindInProjectKey.self] = newValue }
    }

    var closeProject: (() -> Void)? {
        get { self[CloseProjectKey.self] }
        set { self[CloseProjectKey.self] = newValue }
    }

    var increaseFontSize: (() -> Void)? {
        get { self[IncreaseFontSizeKey.self] }
        set { self[IncreaseFontSizeKey.self] = newValue }
    }

    var decreaseFontSize: (() -> Void)? {
        get { self[DecreaseFontSizeKey.self] }
        set { self[DecreaseFontSizeKey.self] = newValue }
    }

    var resetFontSize: (() -> Void)? {
        get { self[ResetFontSizeKey.self] }
        set { self[ResetFontSizeKey.self] = newValue }
    }

    var newTerminalTab: (() -> Void)? {
        get { self[NewTerminalTabKey.self] }
        set { self[NewTerminalTabKey.self] = newValue }
    }

    var findInTerminal: (() -> Void)? {
        get { self[FindInTerminalKey.self] }
        set { self[FindInTerminalKey.self] = newValue }
    }

    var showCommandPalette: (() -> Void)? {
        get { self[ShowCommandPaletteKey.self] }
        set { self[ShowCommandPaletteKey.self] = newValue }
    }

    var nextChange: (() -> Void)? {
        get { self[NextChangeKey.self] }
        set { self[NextChangeKey.self] = newValue }
    }

    var previousChange: (() -> Void)? {
        get { self[PreviousChangeKey.self] }
        set { self[PreviousChangeKey.self] = newValue }
    }

    var reviewAllChanges: (() -> Void)? {
        get { self[ReviewAllChangesKey.self] }
        set { self[ReviewAllChangesKey.self] = newValue }
    }
}

// MARK: - View Menu Commands

struct ViewCommands: Commands {
    @FocusedValue(\.sidebarVisible) var sidebarVisible
    @FocusedValue(\.sidebarTab) var sidebarTab
    @FocusedValue(\.previewOpen) var previewOpen
    @FocusedValue(\.closePreview) var closePreview
    @FocusedValue(\.refresh) var refresh
    @FocusedValue(\.quickOpen) var quickOpen
    @FocusedValue(\.autoFollow) var autoFollow
    @FocusedValue(\.findInProject) var findInProject
    @FocusedValue(\.findInTerminal) var findInTerminal
    @FocusedValue(\.increaseFontSize) var increaseFontSize
    @FocusedValue(\.decreaseFontSize) var decreaseFontSize
    @FocusedValue(\.resetFontSize) var resetFontSize
    @FocusedValue(\.newTerminalTab) var newTerminalTab
    @FocusedValue(\.showCommandPalette) var showCommandPalette
    @FocusedValue(\.nextChange) var nextChange
    @FocusedValue(\.previousChange) var previousChange
    @FocusedValue(\.reviewAllChanges) var reviewAllChanges
    @AppStorage("autoLaunchCopilot") private var autoLaunchCopilot = true
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button("Command Palette…") {
                showCommandPalette?()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(showCommandPalette == nil)

            Divider()

            Button("Quick Open…") {
                quickOpen?()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            .disabled(quickOpen == nil)

            Button("Find in Project…") {
                findInProject?()
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(findInProject == nil)

            Button("Find in Terminal…") {
                findInTerminal?()
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(findInTerminal == nil)

            Divider()

            Toggle("Auto-Launch Copilot", isOn: $autoLaunchCopilot)

            Toggle("Agent Notifications", isOn: $notificationsEnabled)

            if let autoFollow = autoFollow {
                Toggle("Auto-Follow Changes", isOn: autoFollow)
            }

            Divider()

            Button("Toggle Sidebar") {
                sidebarVisible?.wrappedValue.toggle()
            }
            .keyboardShortcut("b", modifiers: .command)
            .disabled(sidebarVisible == nil)

            Divider()

            Button("Files") {
                sidebarVisible?.wrappedValue = true
                sidebarTab?.wrappedValue = .files
            }
            .keyboardShortcut("1", modifiers: .command)
            .disabled(sidebarTab == nil)

            Button("Changes") {
                sidebarVisible?.wrappedValue = true
                sidebarTab?.wrappedValue = .changes
            }
            .keyboardShortcut("2", modifiers: .command)
            .disabled(sidebarTab == nil)

            Button("Activity") {
                sidebarVisible?.wrappedValue = true
                sidebarTab?.wrappedValue = .activity
            }
            .keyboardShortcut("3", modifiers: .command)
            .disabled(sidebarTab == nil)

            Button("Search") {
                sidebarVisible?.wrappedValue = true
                sidebarTab?.wrappedValue = .search
            }
            .keyboardShortcut("4", modifiers: .command)
            .disabled(sidebarTab == nil)

            Divider()

            Button("Close Tab") {
                closePreview?()
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(previewOpen != true)

            Divider()

            Button("Refresh") {
                refresh?()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(refresh == nil)

            Divider()

            Button("Next Changed File") {
                nextChange?()
            }
            .keyboardShortcut(.downArrow, modifiers: [.command, .control])
            .disabled(nextChange == nil)

            Button("Previous Changed File") {
                previousChange?()
            }
            .keyboardShortcut(.upArrow, modifiers: [.command, .control])
            .disabled(previousChange == nil)

            Button("Review All Changes") {
                reviewAllChanges?()
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            .disabled(reviewAllChanges == nil)

            Divider()

            Button("Increase Font Size") {
                increaseFontSize?()
            }
            .keyboardShortcut("+", modifiers: .command)
            .disabled(increaseFontSize == nil)

            Button("Decrease Font Size") {
                decreaseFontSize?()
            }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(decreaseFontSize == nil)

            Button("Reset Font Size") {
                resetFontSize?()
            }
            .keyboardShortcut("0", modifiers: .command)
            .disabled(resetFontSize == nil)

            Divider()

            Button("New Terminal Tab") {
                newTerminalTab?()
            }
            .keyboardShortcut("t", modifiers: .command)
            .disabled(newTerminalTab == nil)
        }
    }
}

// MARK: - File Menu Commands

struct FileCommands: Commands {
    @FocusedValue(\.openDirectory) var openDirectory
    @FocusedValue(\.closeProject) var closeProject

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open Directory…") {
                openDirectory?()
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(openDirectory == nil)

            Button("Close Project") {
                closeProject?()
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])
            .disabled(closeProject == nil)
        }
    }
}
