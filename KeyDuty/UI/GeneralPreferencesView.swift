import AppKit
import Sparkle
import SwiftUI

struct GeneralPreferencesView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var permissionManager: PermissionManager
    @ObservedObject var launchAtLoginManager: LaunchAtLoginManager
    @ObservedObject var keyboardDeviceManager: KeyboardDeviceManager
    var updater: SPUUpdater?
    @ObservedObject var languageSettings: LanguageSettings = .shared
    @State private var permissionFeedbackMessage: String?
    @State private var permissionFeedbackRevision = 0

    var body: some View {
        Form {
            Section(L10n.text("language.section")) {
                Picker(L10n.text("language.label"), selection: $languageSettings.selection) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .accessibilityIdentifier("appLanguagePicker")

            }

            TypingSoundSettingsView(preferences: preferences)

            Section(L10n.text("general.startup")) {
                Toggle(
                    L10n.text("general.login"),
                    isOn: Binding(
                        get: { launchAtLoginManager.isEnabled },
                        set: { launchAtLoginManager.setEnabled($0) }
                    )
                )

                if launchAtLoginManager.requiresApproval {
                    Text(L10n.text("general.approval"))
                        .foregroundStyle(.orange)
                }
                if let errorMessage = launchAtLoginManager.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            if let updater {
                UpdateSettingsView(updater: updater)
            }

            Section(L10n.text("permissions.title")) {
                PermissionStatusRow(title: L10n.text("permissions.listen"), granted: permissionManager.canListen)
                PermissionStatusRow(title: L10n.text("permissions.post"), granted: permissionManager.canPost)

                HStack {
                    Button(L10n.text("permissions.check")) { checkPermissions() }
                    if let missingPermissionName {
                        Button(L10n.text("permissions.allow", missingPermissionName)) { requestMissingPermission() }
                    }
                }
                .buttonStyle(.bordered)

                if let permissionFeedbackMessage {
                    Label(permissionFeedbackMessage, systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .task(id: permissionFeedbackRevision) {
                            try? await Task.sleep(for: .seconds(3))
                            guard !Task.isCancelled else { return }
                            self.permissionFeedbackMessage = nil
                        }
                }
            }
        }
        .formStyle(.grouped)
        .padding(8)
        .onDisappear {
            permissionFeedbackMessage = nil
        }
    }

    private var missingPermissionName: String? {
        if !permissionManager.canListen {
            return L10n.text("permissions.listen")
        }
        if !permissionManager.canPost {
            return L10n.text("permissions.post")
        }
        return nil
    }

    private func checkPermissions() {
        defer { showPermissionFeedback(L10n.text("permissions.checked")) }
        guard let appDelegate = NSApp.delegate as? MenuBarApp else {
            permissionManager.refresh()
            keyboardDeviceManager.start()
            return
        }
        appDelegate.checkPermissions()
        keyboardDeviceManager.start()
    }

    private func requestMissingPermission() {
        guard let missingPermissionName else { return }
        permissionManager.requestMissingAccess()
        showPermissionFeedback(L10n.text("permissions.requested", missingPermissionName))
    }

    private func showPermissionFeedback(_ message: String) {
        permissionFeedbackMessage = message
        permissionFeedbackRevision += 1
    }
}

private struct PermissionStatusRow: View {
    let title: String
    let granted: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Label(granted ? L10n.text("permissions.granted") : L10n.text("permissions.missing"),
                  systemImage: granted ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(granted ? .green : .secondary)
        }
    }
}
