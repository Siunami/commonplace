import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject private var perms = PermissionsMonitor.shared
    @State private var launchAtLogin = false
    @State private var watchedFolders: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(.title3)
                .fontWeight(.semibold)

            // Panels below group interactive controls — toggles, buttons,
            // list editors. Read-only reference (database path, shortcut
            // table) renders below as flat sections without the fill, so
            // the eye is drawn to the things a user can actually change.

            // General — interactive (toggle)
            settingsSection {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .font(.callout)
                    .onChange(of: launchAtLogin) { _, enabled in
                        if enabled {
                            try? SMAppService.mainApp.register()
                        } else {
                            try? SMAppService.mainApp.unregister()
                        }
                    }
            }

            // Watched Folders — interactive (add/remove)
            settingsSection {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Watched Folders")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("New files in these folders are automatically captured")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    ForEach(watchedFolders, id: \.self) { folder in
                        HStack(spacing: 6) {
                            Image(systemName: "folder")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(folder.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            if folder == NSHomeDirectory() + "/Downloads" || folder == NSHomeDirectory() + "/Desktop" {
                                Text("Default")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Button(action: { removeFolder(folder) }) {
                                Image(systemName: "minus.circle")
                                    .font(.caption)
                                    .foregroundStyle(.red.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button(action: addFolder) {
                        Label("Add Folder...", systemImage: "plus")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Permissions — interactive (grant/manage)
            settingsSection {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Permissions")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    permissionRow(
                        "Screen Recording",
                        description: "Capture screenshots and recordings",
                        granted: perms.screenRecordingGranted,
                        action: {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    )
                    permissionRow(
                        "Accessibility",
                        description: "Intercept ⌘⇧3 / ⌘⇧4 shortcuts",
                        granted: perms.accessibilityGranted,
                        action: {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    )
                }
            }

            // Shortcuts — reference only, no panel fill.
            infoSection(title: "Shortcuts") {
                VStack(alignment: .leading, spacing: 4) {
                    shortcutRow("Full screen", "⌘⇧3")
                    shortcutRow("Region", "⌘⇧4")
                    shortcutRow("Archive", "⌃⌘A")
                }
            }

            // Database path — reference only, no panel fill.
            infoSection(title: "Database") {
                Text(DatabaseManager.appSupportURL.path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            // Footer
            HStack {
                Text("Commonplace v1.0")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
            }
        }
        .padding()
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            watchedFolders = FileMonitor.shared.watchedFolders
        }
    }

    // MARK: - Section wrappers

    /// Boxed container for interactive controls. The fill draws the eye to
    /// things the user can act on.
    private func settingsSection<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// Flat section for read-only reference material — no panel fill, just
    /// a small caption label over the content. Keeps reference entries
    /// present but visually secondary to the interactive panels above.
    private func infoSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helpers

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a folder to monitor for new files"
        if panel.runModal() == .OK, let url = panel.url {
            FileMonitor.shared.addFolder(url.path)
            watchedFolders = FileMonitor.shared.watchedFolders
        }
    }

    private func removeFolder(_ path: String) {
        FileMonitor.shared.removeFolder(path)
        watchedFolders = FileMonitor.shared.watchedFolders
    }

    private func permissionRow(_ label: String, description: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(granted ? Color.green.opacity(0.2) : Color.orange.opacity(0.15))
                    .frame(width: 22, height: 22)
                Image(systemName: granted ? "checkmark" : "exclamationmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(granted ? Color.green : Color.orange)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                Text(description)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button(action: action) {
                Text(granted ? "Manage" : "Grant")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(granted ? Color.primary.opacity(0.08) : Color.accentColor)
                    .foregroundStyle(granted ? Color.primary : Color.white)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private func shortcutRow(_ label: String, _ shortcut: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(shortcut)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }
}
