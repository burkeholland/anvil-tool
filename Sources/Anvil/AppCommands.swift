import SwiftUI

// MARK: - Focused Values

/// Keys for communicating state between ContentView and menu Commands.
struct SidebarVisibleKey: FocusedValueKey {
    typealias Value = Binding<Bool>
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

struct NewCopilotTabKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct FindInTerminalKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct FindTerminalNextKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct FindTerminalPreviousKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct ShowCommandPaletteKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct ShowKeyboardShortcutsKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct CloneRepositoryKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct SplitTerminalHKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct SplitTerminalVKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct ShowPromptHistoryKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct ExportSessionKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct OpenRecentProjectKey: FocusedValueKey {
    typealias Value = (URL) -> Void
}

extension FocusedValues {
    var sidebarVisible: Binding<Bool>? {
        get { self[SidebarVisibleKey.self] }
        set { self[SidebarVisibleKey.self] = newValue }
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

    var newCopilotTab: (() -> Void)? {
        get { self[NewCopilotTabKey.self] }
        set { self[NewCopilotTabKey.self] = newValue }
    }

    var findInTerminal: (() -> Void)? {
        get { self[FindInTerminalKey.self] }
        set { self[FindInTerminalKey.self] = newValue }
    }

    var findTerminalNext: (() -> Void)? {
        get { self[FindTerminalNextKey.self] }
        set { self[FindTerminalNextKey.self] = newValue }
    }

    var findTerminalPrevious: (() -> Void)? {
        get { self[FindTerminalPreviousKey.self] }
        set { self[FindTerminalPreviousKey.self] = newValue }
    }

    var showCommandPalette: (() -> Void)? {
        get { self[ShowCommandPaletteKey.self] }
        set { self[ShowCommandPaletteKey.self] = newValue }
    }

    var showKeyboardShortcuts: (() -> Void)? {
        get { self[ShowKeyboardShortcutsKey.self] }
        set { self[ShowKeyboardShortcutsKey.self] = newValue }
    }

    var cloneRepository: (() -> Void)? {
        get { self[CloneRepositoryKey.self] }
        set { self[CloneRepositoryKey.self] = newValue }
    }

    var splitTerminalH: (() -> Void)? {
        get { self[SplitTerminalHKey.self] }
        set { self[SplitTerminalHKey.self] = newValue }
    }

    var splitTerminalV: (() -> Void)? {
        get { self[SplitTerminalVKey.self] }
        set { self[SplitTerminalVKey.self] = newValue }
    }

    var showPromptHistory: (() -> Void)? {
        get { self[ShowPromptHistoryKey.self] }
        set { self[ShowPromptHistoryKey.self] = newValue }
    }

    var exportSession: (() -> Void)? {
        get { self[ExportSessionKey.self] }
        set { self[ExportSessionKey.self] = newValue }
    }

    var openRecentProject: ((URL) -> Void)? {
        get { self[OpenRecentProjectKey.self] }
        set { self[OpenRecentProjectKey.self] = newValue }
    }
}

// MARK: - View Menu Commands

struct ViewCommands: Commands {
    @FocusedValue(\.sidebarVisible) var sidebarVisible
    @FocusedValue(\.refresh) var refresh
    @FocusedValue(\.quickOpen) var quickOpen
    @FocusedValue(\.autoFollow) var autoFollow
    @FocusedValue(\.findInProject) var findInProject
    @FocusedValue(\.findInTerminal) var findInTerminal
    @FocusedValue(\.findTerminalNext) var findTerminalNext
    @FocusedValue(\.findTerminalPrevious) var findTerminalPrevious
    @FocusedValue(\.increaseFontSize) var increaseFontSize
    @FocusedValue(\.decreaseFontSize) var decreaseFontSize
    @FocusedValue(\.resetFontSize) var resetFontSize
    @FocusedValue(\.newTerminalTab) var newTerminalTab
    @FocusedValue(\.newCopilotTab) var newCopilotTab
    @FocusedValue(\.splitTerminalH) var splitTerminalH
    @FocusedValue(\.splitTerminalV) var splitTerminalV
    @FocusedValue(\.showCommandPalette) var showCommandPalette
    @FocusedValue(\.showPromptHistory) var showPromptHistory
    @FocusedValue(\.exportSession) var exportSession
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

            Button("Find Next in Terminal") {
                findTerminalNext?()
            }
            .keyboardShortcut("g", modifiers: .command)
            .disabled(findTerminalNext == nil)

            Button("Find Previous in Terminal") {
                findTerminalPrevious?()
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .disabled(findTerminalPrevious == nil)

            Button("Prompt History…") {
                showPromptHistory?()
            }
            .keyboardShortcut("y", modifiers: .command)
            .disabled(showPromptHistory == nil)

            Button("Export Session as Markdown") {
                exportSession?()
            }
            .disabled(exportSession == nil)

            Divider()

            Toggle("Auto-Launch Copilot", isOn: $autoLaunchCopilot)

            Toggle("Agent Notifications", isOn: $notificationsEnabled)

            if let autoFollow = autoFollow {
                Toggle("Follow Agent", isOn: autoFollow)
                    .keyboardShortcut("a", modifiers: [.command, .shift])
            }

            Divider()

            Button("Toggle Sidebar") {
                sidebarVisible?.wrappedValue.toggle()
            }
            .keyboardShortcut("b", modifiers: .command)
            .disabled(sidebarVisible == nil)

            Divider()

            Button("Refresh") {
                refresh?()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(refresh == nil)

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

            Button("New Copilot Tab") {
                newCopilotTab?()
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(newCopilotTab == nil)

            Divider()

            Button("Split Terminal Right") {
                splitTerminalH?()
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(splitTerminalH == nil)

            Button("Split Terminal Down") {
                splitTerminalV?()
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            .disabled(splitTerminalV == nil)
        }
    }
}

// MARK: - File Menu Commands

struct FileCommands: Commands {
    @FocusedValue(\.openDirectory) var openDirectory
    @FocusedValue(\.closeProject) var closeProject
    @FocusedValue(\.cloneRepository) var cloneRepository
    @FocusedValue(\.openRecentProject) var openRecentProject
    @FocusedObject var recentProjects: RecentProjectsModel?

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open Directory…") {
                openDirectory?()
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(openDirectory == nil)

            Button("Clone Repository…") {
                cloneRepository?()
            }
            .disabled(cloneRepository == nil)

            Menu("Open Recent") {
                if let projects = recentProjects?.recentProjects, !projects.isEmpty {
                    ForEach(projects) { project in
                        Button(project.name) {
                            openRecentProject?(project.url)
                        }
                        .help(project.path)
                        .disabled(!project.exists)
                    }
                    Divider()
                    Button("Clear Recent Projects") {
                        recentProjects?.clearAll()
                    }
                } else {
                    Text("No Recent Projects")
                }
            }

            Divider()

            Button("Close Project") {
                closeProject?()
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])
            .disabled(closeProject == nil)
        }
    }
}

// MARK: - Help Menu Commands

struct HelpCommands: Commands {
    @FocusedValue(\.showKeyboardShortcuts) var showKeyboardShortcuts

    var body: some Commands {
        CommandGroup(after: .help) {
            Button("Keyboard Shortcuts") {
                showKeyboardShortcuts?()
            }
            .keyboardShortcut("/", modifiers: .command)
        }
    }
}
