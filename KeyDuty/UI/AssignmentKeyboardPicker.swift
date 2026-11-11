import SwiftUI

struct AssignmentKeyboardPicker: View {
    @Binding var assignment: KeyAssignment
    @ObservedObject var preferences: Preferences
    @ObservedObject var keyboardDeviceManager: KeyboardDeviceManager
    @State private var isPresented = false

    private var hasExclusions: Bool { !assignment.ignoredKeyboardIDs.isEmpty }
    private var summary: String {
        hasExclusions ? L10n.text("keyboards.count", assignment.ignoredKeyboardIDs.count) : L10n.text("common.all")
    }

    private var destinationName: String {
        if assignment.separatesPressAndRelease {
            return L10n.text(
                "keyboards.splitSummary", actionName(assignment.pressReleaseActions.onPress),
                actionName(assignment.pressReleaseActions.onRelease)
            )
        }
        return assignment.action == .none ? L10n.text("common.unset") : actionName(assignment.action)
    }

    private func actionName(_ action: KeyAction) -> String {
        switch action {
        case .none: L10n.text("common.doNothing")
        case let .sendKey(code): KeyCatalog.name(for: code)
        case let .system(action): action.displayName
        }
    }

    var body: some View {
        Button { isPresented.toggle() } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "keyboard")
                    .font(.system(size: 15))
                    .frame(width: 32, height: 30)
                if hasExclusions {
                    Text("\(assignment.ignoredKeyboardIDs.count)")
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 3)
                        .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
                        .offset(x: 2, y: -2)
                }
            }
            .foregroundStyle(hasExclusions ? Color.accentColor : .secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.text("keyboards.accessibility", assignment.inputName, summary))
        .help(L10n.text("keyboards.help", summary))
        .popover(isPresented: $isPresented, arrowEdge: .bottom) { popover }
    }

    private var popover: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.text("keyboards.exclude"))
                    .font(.headline)
                Text("\(assignment.inputName) → \(destinationName)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(L10n.text("keyboards.description"))
                    .font(.callout)
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if keyboardDeviceManager.devices.isEmpty {
                        Text(L10n.text("keyboards.empty"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(L10n.text("keyboards.connected")).font(.caption).foregroundStyle(.secondary)
                        ForEach(keyboardDeviceManager.devices) { device in
                            keyboardToggle(
                                id: device.id, name: device.name,
                                detail: device.transport.isEmpty ? L10n.text("keyboards.connected") : device.transport
                            )
                            .help(device.detail)
                        }
                    }
                    if !disconnectedIDs.isEmpty {
                        Divider()
                        Text(L10n.text("keyboards.saved")).font(.caption).foregroundStyle(.secondary)
                        ForEach(disconnectedIDs, id: \.self) { id in
                            keyboardToggle(
                                id: id, name: preferences.keyboardNames[id] ?? L10n.text("keyboards.fallback", id),
                                detail: L10n.text("keyboards.reconnect")
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 250)
            .fixedSize(horizontal: false, vertical: true)

            if let error = keyboardDeviceManager.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.text("keyboards.modelHelp"))
                if hasExclusions {
                    Text(L10n.text("keyboards.unknownHelp"))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Divider()
            HStack {
                Button(L10n.text("keyboards.refresh")) { keyboardDeviceManager.start() }
                Button(L10n.text("keyboards.clear")) { assignment.ignoredKeyboardIDs.removeAll() }
                    .disabled(!hasExclusions)
                Spacer()
                Button(L10n.text("common.done")) { isPresented = false }
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.regular)
        }
        .padding(20)
        .frame(width: 360)
    }

    private var disconnectedIDs: [String] {
        let connectedIDs = Set(keyboardDeviceManager.devices.map(\.id))
        return assignment.ignoredKeyboardIDs.subtracting(connectedIDs).sorted()
    }

    private func keyboardToggle(id: String, name: String, detail: String) -> some View {
        Toggle(isOn: Binding(
            get: { assignment.ignoredKeyboardIDs.contains(id) },
            set: { excluded in
                if excluded {
                    assignment.ignoredKeyboardIDs.insert(id)
                } else {
                    assignment.ignoredKeyboardIDs.remove(id)
                }
            }
        )) {
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.system(size: 13, weight: .medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.checkbox)
        .accessibilityLabel(L10n.text("keyboards.excludeNamed", name))
    }
}
