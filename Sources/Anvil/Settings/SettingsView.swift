import SwiftUI

/// Anvil preferences window, accessible via ⌘, (standard macOS Settings scene).
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            TerminalSettingsTab()
                .tabItem {
                    Label("Terminal", systemImage: "terminal")
                }

            EditorSettingsTab()
                .tabItem {
                    Label("Editor", systemImage: "square.and.pencil")
                }

            NotificationsSettingsTab()
                .tabItem {
                    Label("Notifications", systemImage: "bell")
                }
        }
        .frame(width: 450, height: 420)
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @AppStorage("autoLaunchCopilot") private var autoLaunchCopilot = true
    @AppStorage("autoFollowChanges") private var autoFollow = true
    @AppStorage("autoBuildOnTaskComplete") private var autoBuildOnTaskComplete = true
    @AppStorage("branchGuardBehavior") private var branchGuardBehavior = "warn"

    var body: some View {
        Form {
            Toggle("Auto-launch Copilot CLI", isOn: $autoLaunchCopilot)
            Text("Run the `copilot` command automatically when a new terminal session starts.")
                .settingsDescription()

            Spacer().frame(height: 8)

            Toggle("Follow Agent", isOn: $autoFollow)
            Text("Auto-navigate the file tree and preview pane to files as the agent modifies them. Use ⌘⇧A to toggle.")
                .settingsDescription()

            Spacer().frame(height: 8)

            Toggle("Auto-build on task complete", isOn: $autoBuildOnTaskComplete)
            Text("Automatically run the project build when the agent goes idle, so the build badge updates without manual action. Disable for projects with slow builds.")
                .settingsDescription()

            Spacer().frame(height: 8)

            Picker("Branch guard", selection: $branchGuardBehavior) {
                Text("Warn me").tag("warn")
                Text("Auto-branch silently").tag("autoBranch")
                Text("Disabled").tag("disabled")
            }
            Text("What to do when the agent modifies files on the default branch (main/master): warn with a prompt to create a feature branch, auto-create one silently, or do nothing.")
                .settingsDescription()
        }
        .padding(20)
    }
}

// MARK: - Terminal

private struct TerminalSettingsTab: View {
    @AppStorage("terminalFontSize") private var fontSize: Double = EmbeddedTerminalView.defaultFontSize
    @AppStorage("terminalThemeID") private var themeID: String = TerminalTheme.defaultDark.id

    var body: some View {
        Form {
            Picker("Color theme", selection: $themeID) {
                ForEach(TerminalTheme.builtIn) { theme in
                    HStack(spacing: 8) {
                        ThemePreviewSwatch(theme: theme)
                        Text(theme.name)
                    }
                    .tag(theme.id as String)
                }
            }
            Text("Choose the color scheme for the terminal.")
                .settingsDescription()

            Spacer().frame(height: 8)

            LabeledContent("Font size") {
                HStack(spacing: 8) {
                    Slider(
                        value: $fontSize,
                        in: EmbeddedTerminalView.minFontSize...EmbeddedTerminalView.maxFontSize,
                        step: 1
                    )
                    .frame(width: 180)

                    Text("\(Int(fontSize)) pt")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 42, alignment: .trailing)
                }
            }
            Text("You can also use ⌘+ and ⌘- to adjust the terminal font size.")
                .settingsDescription()
        }
        .padding(20)
    }
}

/// A small swatch showing the theme's background, foreground, and a few ANSI colors.
private struct ThemePreviewSwatch: View {
    let theme: TerminalTheme

    var body: some View {
        HStack(spacing: 1) {
            Rectangle().fill(Color(nsColor: theme.background))
            Rectangle().fill(Color(nsColor: theme.ansiColors[1])) // red
            Rectangle().fill(Color(nsColor: theme.ansiColors[2])) // green
            Rectangle().fill(Color(nsColor: theme.ansiColors[4])) // blue
            Rectangle().fill(Color(nsColor: theme.ansiColors[5])) // magenta
        }
        .frame(width: 40, height: 14)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
        )
    }
}

// MARK: - Editor

private struct EditorSettingsTab: View {
    @AppStorage("preferredEditorID") private var preferredEditorID: String = ""
    private var installed: [ExternalEditor] { ExternalEditorManager.installedEditors }

    var body: some View {
        Form {
            if installed.isEmpty {
                Text("No supported editors detected.")
                    .foregroundStyle(.secondary)
                Text("Install VS Code, Cursor, Zed, or Sublime Text to enable \"Open in Editor\" from context menus. Files will open with the system default app in the meantime.")
                    .settingsDescription()
            } else {
                Picker("External editor", selection: $preferredEditorID) {
                    ForEach(installed) { editor in
                        Text(editor.name).tag(editor.id)
                    }
                }
                Text("The editor used when opening files from context menus and the preview toolbar.")
                    .settingsDescription()
            }
        }
        .padding(20)
        .onAppear {
            // Default to first installed editor if no preference set
            if preferredEditorID.isEmpty, let first = installed.first {
                preferredEditorID = first.id
            }
        }
    }
}

// MARK: - Notifications

private struct NotificationsSettingsTab: View {
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage(UserDefaultsKeys.playSoundOnAgentFinish) private var playSoundOnFinish = true
    @AppStorage(UserDefaultsKeys.agentFinishSoundName) private var selectedSoundName = AgentSoundOption.glass.rawValue

    var body: some View {
        Form {
            Toggle("Enable agent notifications", isOn: $notificationsEnabled)
            Text("Show macOS notifications when the agent commits or finishes modifying files while Anvil is in the background.")
                .settingsDescription()

            Spacer().frame(height: 8)

            Toggle("Play sound when agent finishes", isOn: $playSoundOnFinish)
            Text("Play a system sound when the agent transitions from active to idle.")
                .settingsDescription()

            Spacer().frame(height: 4)

            Picker("Sound", selection: $selectedSoundName) {
                ForEach(AgentSoundOption.allCases) { option in
                    Text(option.rawValue).tag(option.rawValue)
                }
            }
            .disabled(!playSoundOnFinish)

            Button("Preview") {
                NSSound(named: selectedSoundName)?.play()
            }
            .disabled(!playSoundOnFinish)
        }
        .padding(20)
    }
}

// MARK: - Helpers

private extension Text {
    func settingsDescription() -> some View {
        self
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
