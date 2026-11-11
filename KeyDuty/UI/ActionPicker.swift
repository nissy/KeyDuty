import SwiftUI

struct ActionPicker: View {
    @Binding var selection: KeyAction
    let preferences: Preferences
    var isCompact = false
    var allowsNoAction = false
    var accessibilityTitle = L10n.text("common.destination")
    @State private var isPresented = false

    private var name: String {
        switch selection {
        case .none: L10n.text(allowsNoAction ? "common.doNothing" : "action.choose")
        case let .sendKey(code): KeyCatalog.name(for: code)
        case let .system(action): action.displayName
        }
    }

    private var label: String {
        guard allowsNoAction, let action = selection.systemAction else { return name }
        switch action {
        case .displayOff: return L10n.text("action.short.displayOff")
        case .lockScreen: return L10n.text("action.short.lock")
        case .sleep: return L10n.text("action.short.sleep")
        case .startScreensaver: return L10n.text("action.short.screensaver")
        case .mediaPlay: return L10n.text("action.short.play")
        case .mediaPause: return L10n.text("action.short.pause")
        }
    }

    var body: some View {
        Button { isPresented = true } label: {
            HStack(spacing: 6) {
                if let action = selection.systemAction {
                    Image(systemName: action.symbol).accessibilityHidden(true)
                }
                Text(label)
                    .lineLimit(1)
                    .foregroundStyle(selection == .none ? .secondary : .primary)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: isCompact ? 13 : 14))
            .padding(.horizontal, isCompact ? 10 : 12)
            .frame(height: allowsNoAction && isCompact ? 30 : 36)
            .background(Color(nsColor: .quaternaryLabelColor).opacity(0.25), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.primary.opacity(0.1)))
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityValue(name)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            ActionPickerContent(selection: selection, preferences: preferences, allowsNoAction: allowsNoAction) {
                selection = $0
                isPresented = false
            }
        }
    }
}

private struct ActionPickerContent: View {
    let selection: KeyAction
    let preferences: Preferences
    let allowsNoAction: Bool
    let onSelect: (KeyAction) -> Void
    @State private var showsActions: Bool

    init(selection: KeyAction, preferences: Preferences, allowsNoAction: Bool,
         onSelect: @escaping (KeyAction) -> Void) {
        self.selection = selection
        self.preferences = preferences
        self.allowsNoAction = allowsNoAction
        self.onSelect = onSelect
        _showsActions = State(initialValue: selection.systemAction != nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker(L10n.text("action.type"), selection: $showsActions) {
                Text(L10n.text("common.key")).tag(false)
                Text(L10n.text("common.action")).tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding([.horizontal, .top], 16)

            if allowsNoAction {
                Button { onSelect(.none) } label: {
                    HStack {
                        Text(L10n.text("common.doNothing"))
                        Spacer()
                        if selection == .none { Image(systemName: "checkmark") }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.top, 12)
                Divider().padding(.horizontal, 16).padding(.top, 10)
            }

            if showsActions {
                actions
            } else {
                KeyPickerContent(
                    selection: selectedKeyCode, allowsModifiers: false, preferences: preferences,
                    showsEmptySelection: !allowsNoAction
                ) { code in
                    onSelect(code.map { .sendKey(keyCode: $0) } ?? .none)
                }
            }
        }
        .frame(width: 320)
    }

    private var selectedKeyCode: CGKeyCode? {
        if case let .sendKey(code) = selection { return code }
        return nil
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(SystemAction.allCases) { action in
                Button { onSelect(.system(action)) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: action.symbol)
                            .frame(width: 20)
                            .accessibilityHidden(true)
                        Text(action.displayName)
                        Spacer(minLength: 0)
                        if selection == .system(action) { Image(systemName: "checkmark") }
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 38)
                    .contentShape(Rectangle())
                    .background(
                        selection == .system(action) ? Color.accentColor.opacity(0.12) : .clear,
                        in: RoundedRectangle(cornerRadius: 5)
                    )
                }
                .buttonStyle(.plain)
            }
            Divider().padding(.vertical, 8)
            Text(L10n.text("action.mediaHelp"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
    }
}
