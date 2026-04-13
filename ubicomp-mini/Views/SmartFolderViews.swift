import SwiftUI

// MARK: - Smart Folder List (sidebar or sheet)

struct SmartFolderList: View {
    let folders: [SavedFilter]
    let counts: [String: Int]
    @Binding var selectedFolder: SavedFilter?
    let onDelete: (SavedFilter) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Smart Folders")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            Divider()

            if folders.isEmpty {
                VStack(spacing: 6) {
                    Spacer()
                    Image(systemName: "folder.badge.gearshape")
                        .font(.title2)
                        .foregroundStyle(.quaternary)
                    Text("No smart folders yet")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(folders) { folder in
                            Button(action: { selectedFolder = folder }) {
                                HStack(spacing: 8) {
                                    Image(systemName: folder.icon)
                                        .font(.callout)
                                        .frame(width: 20)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(folder.name)
                                            .font(.callout)
                                            .lineLimit(1)
                                        Text(folderDescription(folder))
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Text("\(counts[folder.id] ?? 0)")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(selectedFolder?.id == folder.id ? Color.accentColor.opacity(0.1) : Color.clear)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(selectedFolder?.id == folder.id ? .primary : .secondary)
                            .contextMenu {
                                Button(role: .destructive, action: { onDelete(folder) }) {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func folderDescription(_ folder: SavedFilter) -> String {
        folder.predicates.map { pred in
            if pred.op.needsValue {
                return "\(pred.field.displayName_) \(pred.op.displayName) \"\(pred.value)\""
            }
            return "\(pred.field.displayName_) \(pred.op.displayName)"
        }.joined(separator: " & ")
    }
}

// MARK: - Smart Folder Creator

struct SmartFolderCreator: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (SavedFilter) -> Void

    @State private var name = ""
    @State private var icon = "folder"
    @State private var predicates: [FilterPredicate] = [
        FilterPredicate(field: .sourceApp, op: .equals, value: "")
    ]

    private let iconOptions = ["folder", "tray.full", "bookmark", "star", "flag", "tag", "archivebox", "globe", "desktopcomputer", "text.cursor"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Smart Folder")
                .font(.headline)

            // Name + icon
            HStack(spacing: 8) {
                Picker("", selection: $icon) {
                    ForEach(iconOptions, id: \.self) { ic in
                        Image(systemName: ic).tag(ic)
                    }
                }
                .labelsHidden()
                .frame(width: 60)

                TextField("Folder name", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            Divider()

            // Predicates
            Text("Conditions")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            ForEach($predicates) { $pred in
                PredicateRow(predicate: $pred, onRemove: {
                    predicates.removeAll { $0.id == pred.id }
                })
            }

            Button(action: {
                predicates.append(FilterPredicate(field: .sourceApp, op: .equals, value: ""))
            }) {
                Label("Add condition", systemImage: "plus.circle")
                    .font(.callout)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)

            Spacer()

            // Save / Cancel
            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Save") {
                    let filter = SavedFilter(
                        id: UUID().uuidString,
                        name: name.isEmpty ? "Untitled" : name,
                        predicateJSON: SavedFilter.encode(predicates: predicates),
                        createdAt: Date().timeIntervalSince1970,
                        icon: icon
                    )
                    onSave(filter)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(predicates.isEmpty)
            }
        }
        .padding()
        .frame(width: 420, height: 400)
    }
}

// MARK: - Predicate Row

private struct PredicateRow: View {
    @Binding var predicate: FilterPredicate
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Picker("", selection: $predicate.field) {
                ForEach(FilterField.allCases, id: \.self) { field in
                    Text(field.displayName_).tag(field)
                }
            }
            .labelsHidden()
            .frame(width: 120)

            Picker("", selection: $predicate.op) {
                ForEach(FilterOperator.allCases, id: \.self) { op in
                    Text(op.displayName).tag(op)
                }
            }
            .labelsHidden()
            .frame(width: 100)

            if predicate.op.needsValue {
                TextField("value", text: $predicate.value)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 80)
            }

            Button(action: onRemove) {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
    }
}
