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

struct NextChangeKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct PreviousChangeKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct ReviewAllChangesKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct ShowKeyboardShortcutsKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct GoToLineKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct RevealInTreeKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct MentionInTerminalKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct CloneRepositoryKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct NextReviewFileKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct PreviousReviewFileKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct NextHunkKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct PreviousHunkKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct StageFocusedHunkKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct UnstageFocusedHunkKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct DiscardFocusedHunkKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct ToggleFocusedFileReviewedKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct OpenFocusedFileKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct SplitTerminalHKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct SplitTerminalVKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct RequestFixKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct NextPreviewTabKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct PreviousPreviewTabKey: FocusedValueKey {
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

    var showKeyboardShortcuts: (() -> Void)? {
        get { self[ShowKeyboardShortcutsKey.self] }
        set { self[ShowKeyboardShortcutsKey.self] = newValue }
    }

    var goToLine: (() -> Void)? {
        get { self[GoToLineKey.self] }
        set { self[GoToLineKey.self] = newValue }
    }

    var revealInTree: (() -> Void)? {
        get { self[RevealInTreeKey.self] }
        set { self[RevealInTreeKey.self] = newValue }
    }

    var mentionInTerminal: (() -> Void)? {
        get { self[MentionInTerminalKey.self] }
        set { self[MentionInTerminalKey.self] = newValue }
    }

    var cloneRepository: (() -> Void)? {
        get { self[CloneRepositoryKey.self] }
        set { self[CloneRepositoryKey.self] = newValue }
    }

    var nextReviewFile: (() -> Void)? {
        get { self[NextReviewFileKey.self] }
        set { self[NextReviewFileKey.self] = newValue }
    }

    var previousReviewFile: (() -> Void)? {
        get { self[PreviousReviewFileKey.self] }
        set { self[PreviousReviewFileKey.self] = newValue }
    }

    var nextHunk: (() -> Void)? {
        get { self[NextHunkKey.self] }
        set { self[NextHunkKey.self] = newValue }
    }

    var previousHunk: (() -> Void)? {
        get { self[PreviousHunkKey.self] }
        set { self[PreviousHunkKey.self] = newValue }
    }

    var stageFocusedHunk: (() -> Void)? {
        get { self[StageFocusedHunkKey.self] }
        set { self[StageFocusedHunkKey.self] = newValue }
    }

    var unstageFocusedHunk: (() -> Void)? {
        get { self[UnstageFocusedHunkKey.self] }
        set { self[UnstageFocusedHunkKey.self] = newValue }
    }

    var discardFocusedHunk: (() -> Void)? {
        get { self[DiscardFocusedHunkKey.self] }
        set { self[DiscardFocusedHunkKey.self] = newValue }
    }

    var toggleFocusedFileReviewed: (() -> Void)? {
        get { self[ToggleFocusedFileReviewedKey.self] }
        set { self[ToggleFocusedFileReviewedKey.self] = newValue }
    }

    var openFocusedFile: (() -> Void)? {
        get { self[OpenFocusedFileKey.self] }
        set { self[OpenFocusedFileKey.self] = newValue }
    }

    var splitTerminalH: (() -> Void)? {
        get { self[SplitTerminalHKey.self] }
        set { self[SplitTerminalHKey.self] = newValue }
    }

    var splitTerminalV: (() -> Void)? {
        get { self[SplitTerminalVKey.self] }
        set { self[SplitTerminalVKey.self] = newValue }
    }

    var requestFix: (() -> Void)? {
        get { self[RequestFixKey.self] }
        set { self[RequestFixKey.self] = newValue }
    }

    var nextPreviewTab: (() -> Void)? {
        get { self[NextPreviewTabKey.self] }
        set { self[NextPreviewTabKey.self] = newValue }
    }

    var previousPreviewTab: (() -> Void)? {
        get { self[PreviousPreviewTabKey.self] }
        set { self[PreviousPreviewTabKey.self] = newValue }
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
    @FocusedValue(\.revealInTree) var revealInTree
    @FocusedValue(\.mentionInTerminal) var mentionInTerminal
    @FocusedValue(\.nextChange) var nextChange
    @FocusedValue(\.previousChange) var previousChange
    @FocusedValue(\.reviewAllChanges) var reviewAllChanges
    @FocusedValue(\.goToLine) var goToLine
    @FocusedValue(\.nextReviewFile) var nextReviewFile
    @FocusedValue(\.previousReviewFile) var previousReviewFile
    @FocusedValue(\.nextHunk) var nextHunk
    @FocusedValue(\.previousHunk) var previousHunk
    @FocusedValue(\.stageFocusedHunk) var stageFocusedHunk
    @FocusedValue(\.unstageFocusedHunk) var unstageFocusedHunk
    @FocusedValue(\.discardFocusedHunk) var discardFocusedHunk
    @FocusedValue(\.toggleFocusedFileReviewed) var toggleFocusedFileReviewed
    @FocusedValue(\.openFocusedFile) var openFocusedFile
    @FocusedValue(\.requestFix) var requestFix
    @FocusedValue(\.nextPreviewTab) var nextPreviewTab
    @FocusedValue(\.previousPreviewTab) var previousPreviewTab
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

            Button("Go to Line…") {
                goToLine?()
            }
            .keyboardShortcut("l", modifiers: .command)
            .disabled(goToLine == nil)

            Button("Reveal in File Tree") {
                revealInTree?()
            }
            .keyboardShortcut("j", modifiers: [.command, .shift])
            .disabled(revealInTree == nil)

            Button("Mention File in Terminal…") {
                mentionInTerminal?()
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .disabled(mentionInTerminal == nil)

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

            Button("Select Next Tab") {
                nextPreviewTab?()
            }
            .keyboardShortcut(KeyEquivalent("\t"), modifiers: .control)
            .disabled(nextPreviewTab == nil)

            Button("Select Previous Tab") {
                previousPreviewTab?()
            }
            .keyboardShortcut(KeyEquivalent("\t"), modifiers: [.control, .shift])
            .disabled(previousPreviewTab == nil)

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

            Button("Next File in Review") {
                nextReviewFile?()
            }
            .keyboardShortcut("]", modifiers: [])
            .disabled(nextReviewFile == nil)

            Button("Previous File in Review") {
                previousReviewFile?()
            }
            .keyboardShortcut("[", modifiers: [])
            .disabled(previousReviewFile == nil)

            Button("Next Hunk") {
                nextHunk?()
            }
            .keyboardShortcut("j", modifiers: [])
            .disabled(nextHunk == nil)

            Button("Previous Hunk") {
                previousHunk?()
            }
            .keyboardShortcut("k", modifiers: [])
            .disabled(previousHunk == nil)

            Button("Stage Focused Hunk") {
                stageFocusedHunk?()
            }
            .keyboardShortcut("s", modifiers: [])
            .disabled(stageFocusedHunk == nil)

            Button("Unstage Focused Hunk") {
                unstageFocusedHunk?()
            }
            .keyboardShortcut("u", modifiers: [])
            .disabled(unstageFocusedHunk == nil)

            Button("Discard Focused Hunk") {
                discardFocusedHunk?()
            }
            .keyboardShortcut("d", modifiers: [])
            .disabled(discardFocusedHunk == nil)

            Button("Toggle File Reviewed") {
                toggleFocusedFileReviewed?()
            }
            .keyboardShortcut("r", modifiers: [])
            .disabled(toggleFocusedFileReviewed == nil)

            Button("Open File in Preview") {
                openFocusedFile?()
            }
            .keyboardShortcut(.return, modifiers: [])
            .disabled(openFocusedFile == nil)

            Button("Request Fix…") {
                requestFix?()
            }
            .keyboardShortcut("f", modifiers: [])
            .disabled(requestFix == nil)

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
