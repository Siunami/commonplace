import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject private var perms = PermissionsMonitor.shared
    @State private var launchAtLogin = false
    @State private var watchedFolders: [String] = []
    @State private var r2Endpoint = CollectionPublisher.shared.endpoint
    @State private var r2AccessKey = CollectionPublisher.shared.accessKeyId
    @State private var r2SecretKey = CollectionPublisher.shared.secretKey
    @State private var r2Bucket = CollectionPublisher.shared.bucket
    @State private var r2PublicUrl = CollectionPublisher.shared.publicUrl
    @State private var r2TestResult: Bool?
    @State private var r2Testing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(.title3)
                .fontWeight(.semibold)

            // General
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

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Database")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(DatabaseManager.appSupportURL.path)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
            }

            // Watched Folders
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

            // Shortcuts
            settingsSection {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Shortcuts")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    shortcutRow("Full screen", "Cmd+Shift+3")
                    shortcutRow("Region", "Cmd+Shift+4")
                    shortcutRow("Archive", "Ctrl+Cmd+A")
                }
            }

            // Publishing
            settingsSection {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Publishing (Cloudflare R2)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Group {
                        settingsField("Endpoint", text: $r2Endpoint, placeholder: "https://xxx.r2.cloudflarestorage.com")
                        settingsField("Bucket", text: $r2Bucket, placeholder: "my-captures")
                        settingsField("Access Key ID", text: $r2AccessKey, placeholder: "")
                        SecureField("Secret Access Key", text: $r2SecretKey)
                            .textFieldStyle(.plain)
                            .font(.caption)
                            .padding(4)
                            .background(.quaternary.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        settingsField("Public URL", text: $r2PublicUrl, placeholder: "https://pub-xxx.r2.dev (optional)")
                    }
                    .onChange(of: r2Endpoint) { _, v in CollectionPublisher.shared.endpoint = v }
                    .onChange(of: r2AccessKey) { _, v in CollectionPublisher.shared.accessKeyId = v }
                    .onChange(of: r2SecretKey) { _, v in CollectionPublisher.shared.secretKey = v }
                    .onChange(of: r2Bucket) { _, v in CollectionPublisher.shared.bucket = v }
                    .onChange(of: r2PublicUrl) { _, v in CollectionPublisher.shared.publicUrl = v }

                    HStack(spacing: 8) {
                        Button(action: testR2) {
                            if r2Testing {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("Test Connection")
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .disabled(r2Testing)

                        if let result = r2TestResult {
                            Image(systemName: result ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(result ? .green : .red)
                                .font(.caption)
                        }
                    }
                }
            }

            // Permissions
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

    // MARK: - Section wrapper

    private func settingsSection<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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

    private func testR2() {
        r2Testing = true
        r2TestResult = nil
        Task {
            let result = await CollectionPublisher.shared.testConnection()
            await MainActor.run {
                r2TestResult = result
                r2Testing = false
            }
        }
    }

    private func settingsField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.caption)
                .padding(4)
                .background(.quaternary.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
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
            Spacer()
            Text(shortcut)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}
