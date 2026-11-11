import SwiftUI

struct InputPicker: View {
    @Binding var assignment: KeyAssignment
    let preferences: Preferences
    var showsBehavior = false
    @State private var isPresented = false

    var body: some View {
        Button { isPresented = true } label: {
            HStack(spacing: 6) {
                if assignment.sourceModifiers.isEmpty, let code = assignment.sourceKeyCode,
                   let symbol = KeyCatalog.symbol(for: code) {
                    Image(systemName: symbol).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(assignment.sourceKeyCode == nil ? L10n.text("input.choose") : assignment.inputName)
                        .lineLimit(1)
                        .foregroundStyle(assignment.sourceKeyCode == nil ? .secondary : .primary)
                    if showsBehavior, assignment.sourceKeyCode != nil {
                        Text(assignment.behaviorName)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: showsBehavior ? 13 : 14))
            .padding(.horizontal, showsBehavior ? 10 : 12)
            .frame(height: showsBehavior ? 40 : 36)
            .background(Color(nsColor: .quaternaryLabelColor).opacity(0.25), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.primary.opacity(0.1)))
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help(inputHelp)
        .accessibilityLabel(L10n.text("input.key"))
        .accessibilityValue(assignment.inputName)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            InputPickerContent(assignment: assignment, preferences: preferences) { code, modifiers in
                assignment.sourceKeyCode = code
                assignment.sourceModifiers = modifiers
                if !assignment.supportsPressRelease { assignment.setSeparatesPressAndRelease(false) }
                isPresented = false
            }
        }
    }
    private var inputHelp: String {
        guard assignment.sourceKeyCode != nil else { return L10n.text("input.help") }
        if assignment.sourceKeyCode == 57 {
            return L10n.text("input.capsLockHelp")
        }
        return L10n.text("input.summary", assignment.inputName, assignment.behaviorName)
    }
}

private struct InputPickerContent: View {
    let assignment: KeyAssignment
    let preferences: Preferences
    let onSelect: (CGKeyCode?, ShortcutModifiers) -> Void
    @State private var showsShortcut: Bool

    init(assignment: KeyAssignment, preferences: Preferences,
         onSelect: @escaping (CGKeyCode?, ShortcutModifiers) -> Void) {
        self.assignment = assignment
        self.preferences = preferences
        self.onSelect = onSelect
        _showsShortcut = State(initialValue: !assignment.sourceModifiers.isEmpty)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker(L10n.text("input.type"), selection: $showsShortcut) {
                Text(L10n.text("input.single")).tag(false)
                Text(L10n.text("input.shortcut")).tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding([.horizontal, .top], 16)
            if showsShortcut {
                ShortcutPickerContent(shortcut: assignment.shortcut, preferences: preferences) {
                    onSelect($0.keyCode, $0.modifiers)
                }
            } else {
                KeyPickerContent(selection: assignment.sourceKeyCode, allowsModifiers: true, preferences: preferences) {
                    onSelect($0, [])
                }
            }
        }
        .frame(width: 340)
    }
}

private struct ShortcutPickerContent: View {
    let preferences: Preferences
    let onSelect: (KeyboardShortcut) -> Void
    @State private var modifiers: ShortcutModifiers
    @State private var keyCode: CGKeyCode?
    @StateObject private var recorder = ShortcutRecorder()

    init(shortcut: KeyboardShortcut?, preferences: Preferences, onSelect: @escaping (KeyboardShortcut) -> Void) {
        self.preferences = preferences
        self.onSelect = onSelect
        _modifiers = State(initialValue: shortcut?.modifiers ?? [])
        _keyCode = State(initialValue: shortcut?.keyCode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                if recorder.isRecording {
                    recorder.stop()
                } else {
                    recorder.start(preferences: preferences, onSelect: onSelect)
                }
            } label: {
                Label(recorder.isRecording ? L10n.text("record.cancel") : L10n.text("record.shortcut"),
                      systemImage: "keyboard")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            if let message = recorder.message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.text("input.modifiers")).font(.caption).foregroundStyle(.secondary)
                HStack {
                    ForEach(ShortcutModifiers.choices, id: \.value.rawValue) { choice in
                        Toggle(choice.symbol, isOn: Binding(
                            get: { modifiers.contains(choice.value) },
                            set: { enabled in
                                if enabled { modifiers.insert(choice.value) } else { modifiers.remove(choice.value) }
                            }
                        ))
                        .toggleStyle(.button)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(choice.name)
                        .help(choice.name)
                    }
                }
                KeyPicker(title: L10n.text("input.shortcutKey"), selection: $keyCode,
                          allowsModifiers: false, preferences: preferences, includesSystemKeys: true)
                Text(L10n.text("input.shortcutHelp"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(L10n.text("input.apply")) {
                    if let shortcut { onSelect(shortcut) }
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .disabled(shortcut?.isValid != true)
            }
            .disabled(recorder.isRecording)
        }
        .padding(16)
        .onDisappear { recorder.stop() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            recorder.stop()
        }
    }

    private var shortcut: KeyboardShortcut? {
        keyCode.map { KeyboardShortcut(keyCode: $0, modifiers: modifiers) }
    }
}
