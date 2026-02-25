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
}

// MARK: - View Menu Commands

struct ViewCommands: Commands {
    @FocusedValue(\.sidebarVisible) var sidebarVisible
    @FocusedValue(\.sidebarTab) var sidebarTab
    @FocusedValue(\.previewOpen) var previewOpen
    @FocusedValue(\.closePreview) var closePreview
    @FocusedValue(\.refresh) var refresh
    @FocusedValue(\.quickOpen) var quickOpen
    @AppStorage("autoLaunchCopilot") private var autoLaunchCopilot = true

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button("Quick Open…") {
                quickOpen?()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            .disabled(quickOpen == nil)

            Divider()

            Toggle("Auto-Launch Copilot", isOn: $autoLaunchCopilot)

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

            Divider()

            Button("Close Preview") {
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
        }
    }
}

// MARK: - File Menu Commands

struct FileCommands: Commands {
    @FocusedValue(\.openDirectory) var openDirectory

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open Directory…") {
                openDirectory?()
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(openDirectory == nil)
        }
    }
}
