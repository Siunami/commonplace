import SwiftUI

struct ClipboardHistoryView: View {
    @ObservedObject var monitor = ClipboardMonitor.shared
    @State private var searchText = ""

    var filtered: [ClipboardEntry] {
        if searchText.isEmpty { return monitor.history }
        return monitor.history.filter { $0.content.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                TextField("Search clipboard...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.caption)
            }
            .padding(8)
            .background(.quaternary.opacity(0.5))

            Divider()

            if filtered.isEmpty {
                VStack {
                    Spacer()
                    Text(monitor.history.isEmpty ? "Nothing copied yet" : "No matches")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filtered) { entry in
                            ClipboardEntryRow(entry: entry)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

struct ClipboardEntryRow: View {
    let entry: ClipboardEntry
    @State private var copied = false

    var body: some View {
        Button(action: {
            ClipboardMonitor.shared.copyToClipboard(entry)
            withAnimation { copied = true }
            Task {
                try? await Task.sleep(for: .seconds(1))
                withAnimation { copied = false }
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: isURL ? "link" : "doc.on.clipboard")
                    .frame(width: 16)
                    .foregroundStyle(.secondary)
                    .font(.caption)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.content.prefix(120))
                        .font(.caption)
                        .lineLimit(2)
                        .truncationMode(.tail)

                    HStack(spacing: 4) {
                        Text(entry.date, style: .time)
                        if let app = entry.sourceApp {
                            Text("·")
                            Text(app)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }

                Spacer()

                if copied {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.primary.opacity(0.001)) // hit area
    }

    private var isURL: Bool {
        let t = entry.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.hasPrefix("http://") || t.hasPrefix("https://")
    }
}
