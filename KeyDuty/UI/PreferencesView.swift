import Sparkle
import SwiftUI

struct PreferencesView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var permissionManager: PermissionManager
    @ObservedObject var launchAtLoginManager: LaunchAtLoginManager
    @ObservedObject var keyboardDeviceManager: KeyboardDeviceManager
    var updater: SPUUpdater?
    @ObservedObject var languageSettings: LanguageSettings = .shared
    @State private var selectedTab = SettingsTab.keys

    private enum SettingsTab: String, CaseIterable {
        case keys = "tab.keys"
        case idle = "tab.idle"
        case general = "tab.general"
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker(L10n.text("settings.category"), selection: $selectedTab) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Text(L10n.text(tab.rawValue)).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .id(languageSettings.selection)
            .labelsHidden()
            .frame(width: 320)
            .padding(.vertical, 10)
            Divider()
            Group {
                switch selectedTab {
                case .keys:
                    KeyAssignmentsView(preferences: preferences, keyboardDeviceManager: keyboardDeviceManager)
                case .idle:
                    IdlePreferencesView(preferences: preferences)
                case .general:
                    GeneralPreferencesView(
                        preferences: preferences,
                        permissionManager: permissionManager,
                        launchAtLoginManager: launchAtLoginManager,
                        keyboardDeviceManager: keyboardDeviceManager,
                        updater: updater,
                        languageSettings: languageSettings
                    )
                }
            }
            .id(languageSettings.selection)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .environment(\.locale, languageSettings.selection.locale)
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(width: 820, height: 520)
        .onAppear {
            keyboardDeviceManager.start()
            if !permissionManager.isReady { selectedTab = .general }
        }
    }
}
