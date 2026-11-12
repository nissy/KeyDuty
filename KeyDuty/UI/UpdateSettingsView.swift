import Sparkle
import SwiftUI

struct UpdateSettingsView: View {
    let updater: SPUUpdater
    @State private var automaticallyChecksForUpdates: Bool
    @State private var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        self.updater = updater
        _automaticallyChecksForUpdates = State(initialValue: updater.automaticallyChecksForUpdates)
    }

    var body: some View {
        Section(L10n.text("updates.section")) {
            Toggle(L10n.text("updates.automaticallyCheck"), isOn: $automaticallyChecksForUpdates)
                .onChange(of: automaticallyChecksForUpdates) { _, enabled in
                    updater.automaticallyChecksForUpdates = enabled
                }

            Button(L10n.text("updates.check")) {
                updater.checkForUpdates()
            }
            .buttonStyle(.bordered)
            .disabled(!canCheckForUpdates)
            .onReceive(updater.publisher(for: \.canCheckForUpdates)) { canCheckForUpdates = $0 }
        }
    }
}
