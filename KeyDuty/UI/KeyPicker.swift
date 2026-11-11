import AppKit
import SwiftUI

struct KeyPicker: View {
    let title: String
    @Binding var selection: CGKeyCode?
    let allowsModifiers: Bool
    let preferences: Preferences
    var includesSystemKeys = false
    @State private var isPresented = false

    var body: some View {
        Button { isPresented = true } label: {
            HStack(spacing: 6) {
                if let selection, let symbol = KeyCatalog.symbol(for: selection) {
                    Image(systemName: symbol)
                        .accessibilityHidden(true)
                }
                Text(selection.map(KeyCatalog.name(for:)) ?? L10n.text("keyPicker.choose"))
                    .lineLimit(1)
                    .foregroundStyle(selection == nil ? .secondary : .primary)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Color(nsColor: .quaternaryLabelColor).opacity(0.25), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.primary.opacity(0.1)))
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(selection.map(KeyCatalog.name(for:)) ?? L10n.text("common.noSelection"))
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            KeyPickerContent(selection: selection, allowsModifiers: allowsModifiers, preferences: preferences,
                             includesSystemKeys: includesSystemKeys) { code in
                selection = code
                isPresented = false
            }
        }
    }
}

struct KeyPickerContent: View {
    let selection: CGKeyCode?
    let allowsModifiers: Bool
    let preferences: Preferences
    var includesSystemKeys = false
    var showsEmptySelection = true
    let onSelect: (CGKeyCode?) -> Void
    @State private var search = ""
    @StateObject private var recorder = KeyRecorder()
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            TextField(L10n.text("keyPicker.search"), text: $search)
                .textFieldStyle(.roundedBorder)
                .focused($isSearchFocused)
                .disabled(recorder.isRecording)

            Button {
                if recorder.isRecording {
                    recorder.stop()
                } else {
                    recorder.start(preferences: preferences, allowsModifiers: allowsModifiers,
                                   includesSystemKeys: includesSystemKeys || allowsModifiers) { onSelect($0) }
                }
            } label: {
                Label(recorder.isRecording ? L10n.text("record.cancel") : L10n.text("record.key"),
                      systemImage: "keyboard")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)

            if let message = recorder.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if search.isEmpty && showsEmptySelection {
                        Button(L10n.text("keyPicker.clear")) { onSelect(nil) }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .padding(8)
                    }
                    ForEach(filteredGroups) { group in
                        Text(group.name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.top, 8)
                        ForEach(group.keys) { key in
                            Button { onSelect(key.id) } label: {
                                HStack {
                                    Text(key.name)
                                    Spacer()
                                    if selection == key.id { Image(systemName: "checkmark") }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 7)
                                .contentShape(Rectangle())
                                .background(
                                    selection == key.id ? Color.accentColor.opacity(0.12) : .clear,
                                    in: RoundedRectangle(cornerRadius: 5)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if filteredGroups.isEmpty {
                        Text(L10n.text("keyPicker.empty"))
                            .foregroundStyle(.secondary)
                            .padding(8)
                    }
                }
            }
            .frame(height: 270)
            .disabled(recorder.isRecording)
            Text(allowsModifiers || includesSystemKeys
                 ? L10n.text("keyPicker.inputHelp")
                 : L10n.text("keyPicker.outputHelp"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 300)
        .onAppear { isSearchFocused = true }
        .onDisappear { recorder.stop() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            recorder.stop()
        }
    }

    private var filteredGroups: [KeyCatalog.Group] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        var groups = allowsModifiers ? KeyCatalog.inputGroups : KeyCatalog.groups
        if !allowsModifiers && includesSystemKeys { groups.append(KeyCatalog.systemKeyGroup) }
        if let selection, !groups.flatMap(\.keys).contains(where: { $0.id == selection }) {
            groups.insert(
                KeyCatalog.Group(id: "group.current", keys: [.init(selection, KeyCatalog.name(for: selection))]), at: 0
            )
        }
        guard !query.isEmpty else { return groups }
        return groups.compactMap { group in
            let keys = group.keys.filter { $0.matches(query) }
            return keys.isEmpty ? nil : KeyCatalog.Group(id: group.id, keys: keys)
        }
    }
}
