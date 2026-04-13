import SwiftUI
import ServiceManagement

struct SettingsView: View {
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
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings")
                .font(.headline)

            Toggle("Launch at Login", isOn: $launchAtLogin)
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
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(DatabaseManager.appSupportURL.path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Watched Folders")
                    .font(.subheadline)
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
                        if folder == NSHomeDirectory() + "/Downloads" {
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

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Shortcuts")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                shortcutRow("Full screen", "Cmd+Shift+3")
                shortcutRow("Region", "Cmd+Shift+4")
                shortcutRow("Clipboard panel", "Ctrl+Cmd+V")
                shortcutRow("Browse history", "Ctrl+Cmd+B")
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Publishing (Cloudflare R2)")
                    .font(.subheadline)
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

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Permissions")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                permissionRow(
                    "Screen Recording",
                    granted: CGPreflightScreenCaptureAccess(),
                    action: {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                )
                permissionRow(
                    "Accessibility",
                    granted: AXIsProcessTrusted(),
                    isOptional: true,
                    action: {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                )
            }

            Divider()

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
                .background(.quaternary.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    private func permissionRow(_ label: String, granted: Bool, isOptional: Bool = false, action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .font(.caption)
                .foregroundStyle(granted ? Color.green : Color.gray)

            Text(label)
                .font(.caption)

            if isOptional {
                Text("optional")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if !granted {
                Button("Open Settings", action: action)
                    .font(.caption2)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
            }
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
