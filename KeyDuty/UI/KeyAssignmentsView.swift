import SwiftUI

struct KeyAssignmentsView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var keyboardDeviceManager: KeyboardDeviceManager = .shared
    @State private var showsHelp = false

    var body: some View {
        let warnings = preferences.configurationWarnings
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text(L10n.text("assignments.title"))
                    .font(.system(size: 20, weight: .semibold))
                Text(L10n.text("assignments.count", preferences.keyAssignments.count))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    preferences.keyAssignments.append(KeyAssignment())
                } label: {
                    Label(L10n.text("common.add"), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("addKeyAssignment")
            }

            if let error = preferences.actionError {
                HStack(alignment: .top) {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                    Spacer()
                    Button { preferences.actionError = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.text("assignments.dismissError"))
                }
            }

            VStack(spacing: 0) {
                columnHeaders
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        if preferences.keyAssignments.isEmpty {
                            emptyState
                        } else {
                            VStack(spacing: 0) {
                                ForEach($preferences.keyAssignments) { $assignment in
                                    VStack(spacing: 0) {
                                        KeyAssignmentRow(
                                            assignment: $assignment, preferences: preferences,
                                            keyboardDeviceManager: keyboardDeviceManager,
                                            hasDuplicateSource: preferences.hasDuplicateSource(assignment),
                                            conflicts: warnings.keyHoldConflicts.filter { $0.involves(assignment) }
                                        ) {
                                            let id = assignment.id
                                            preferences.keyAssignments.removeAll { $0.id == id }
                                        }
                                        Divider().padding(.horizontal, 10)
                                    }
                                    .id(assignment.id)
                                }
                            }
                        }
                    }
                    .onChange(of: preferences.keyAssignments.count) { oldCount, newCount in
                        guard newCount > oldCount, let last = preferences.keyAssignments.last else { return }
                        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.1)))

            HStack {
                Button { showsHelp.toggle() } label: {
                    Label(L10n.text("assignments.help"), systemImage: "questionmark.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .popover(isPresented: $showsHelp) { AssignmentHelpView() }
                Spacer()
                Text(L10n.text("assignments.saved"))
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .padding(20)
        .onAppear { preferences.rememberKeyboards(keyboardDeviceManager.devices) }
        .onChange(of: keyboardDeviceManager.devices) { _, devices in preferences.rememberKeyboards(devices) }
    }

    private var columnHeaders: some View {
        HStack(spacing: 12) {
            Text(L10n.text("common.input")).frame(width: 230, alignment: .leading)
            Color.clear.frame(width: 16)
            Text(L10n.text("common.destination")).frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: 36)
            Text(L10n.text("common.enabled")).frame(width: 38)
            Color.clear.frame(width: 24)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "keyboard")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text(L10n.text("assignments.empty")).font(.headline)
            Text(L10n.text("assignments.emptyHelp"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 42)
    }
}

private struct KeyAssignmentRow: View {
    @Binding var assignment: KeyAssignment
    let preferences: Preferences
    let keyboardDeviceManager: KeyboardDeviceManager
    let hasDuplicateSource: Bool
    let conflicts: [KeyHoldConflict]
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                InputPicker(assignment: $assignment, preferences: preferences, showsBehavior: true)
                    .frame(width: 230)
                Image(systemName: "arrow.right")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .frame(width: 16)
                    .accessibilityHidden(true)
                destinations
                    .frame(maxWidth: .infinity)
                AssignmentKeyboardPicker(
                    assignment: $assignment, preferences: preferences, keyboardDeviceManager: keyboardDeviceManager
                )
                .frame(width: 36)
                Toggle(L10n.text("assignments.enable", assignment.inputName), isOn: Binding(
                    get: { assignment.isEnabled && assignment.isValid },
                    set: { assignment.isEnabled = $0 }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(!assignment.isValid)
                .frame(width: 38)
                Menu {
                    Toggle(L10n.text("assignments.split"), isOn: Binding(
                        get: { assignment.separatesPressAndRelease },
                        set: { assignment.setSeparatesPressAndRelease($0) }
                    ))
                    .disabled(!assignment.supportsPressRelease && !assignment.separatesPressAndRelease)
                    .help(assignment.supportsPressRelease
                          ? L10n.text("assignments.splitHelp")
                          : L10n.text("assignments.capsLockSplitHelp"))
                    Divider()
                    Button(L10n.text("assignments.delete"), role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis").frame(width: 24, height: 28)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .frame(width: 24)
                .accessibilityLabel(L10n.text("assignments.menu", assignment.inputName))
            }
            .frame(minHeight: assignment.separatesPressAndRelease ? 66 : 54)

            if let message = validationMessage {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.bottom, 8)
            }
            ForEach(conflicts) { conflict in
                ConfigurationWarningView(message: conflict.message)
                    .padding(.bottom, 8)
            }
        }
        .padding(.horizontal, 10)
    }

    @ViewBuilder
    private var destinations: some View {
        if assignment.separatesPressAndRelease {
            HStack(alignment: .top, spacing: 8) {
                eventDestination(L10n.text("assignments.press"), selection: $assignment.pressReleaseActions.onPress)
                eventDestination(L10n.text("assignments.release"), selection: $assignment.pressReleaseActions.onRelease)
            }
        } else {
            ActionPicker(selection: $assignment.action, preferences: preferences, isCompact: true)
        }
    }

    private func eventDestination(_ title: String, selection: Binding<KeyAction>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            ActionPicker(selection: selection, preferences: preferences, isCompact: true, allowsNoAction: true,
                         accessibilityTitle: L10n.text("assignments.edgeDestination", assignment.inputName, title))
        }
        .frame(minWidth: 0, maxWidth: .infinity)
    }

    private var validationMessage: String? {
        if hasDuplicateSource { return L10n.text("validation.duplicate") }
        if assignment.separatesPressAndRelease {
            guard assignment.sourceKeyCode != nil else { return nil }
            if !assignment.supportsPressRelease { return L10n.text("validation.noSplit") }
            if assignment.pressReleaseActions.isEmpty {
                return L10n.text("validation.emptySplit")
            }
            return assignment.isValid ? nil : L10n.text("validation.combination")
        }
        guard let source = assignment.sourceKeyCode, assignment.action != .none else { return nil }
        if assignment.sourceModifiers.isEmpty && source == assignment.destinationKeyCode {
            return L10n.text("validation.sameKey")
        }
        return assignment.isValid ? nil : L10n.text("validation.combination")
    }
}

private struct AssignmentHelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.text("help.title")).font(.headline)
                Text(L10n.text("help.intro"))
                Divider()
                explanation(L10n.text("help.modifierTitle"),
                            L10n.text("help.modifier"))
                explanation(L10n.text("help.remapTitle"), L10n.text("help.remap"))
                explanation(L10n.text("help.shortcutTitle"), L10n.text("help.shortcut"))
                explanation(L10n.text("assignments.split"),
                            L10n.text("help.split"))
                Text(L10n.text("help.cancel"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                explanation(L10n.text("help.keyboardsTitle"), L10n.text("help.keyboards"))
                Text(L10n.text("help.capsLock"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
            .padding(20)
        }
        .frame(width: 360, height: 460)
    }

    private func explanation(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).fontWeight(.medium)
            Text(text).foregroundStyle(.secondary)
        }
    }
}
