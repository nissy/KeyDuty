import SwiftUI

struct TypingSoundSettingsView: View {
    @ObservedObject var preferences: Preferences

    var body: some View {
        Section(L10n.text("typingSound.section")) {
            Toggle(L10n.text("typingSound.enabled"), isOn: $preferences.typingSoundEnabled)
                .onChange(of: preferences.typingSoundEnabled) { _, enabled in
                    if enabled { TypingSoundPlayer.shared.prepare(preferences.typingSound) }
                }

            Picker(L10n.text("typingSound.selection"), selection: $preferences.typingSound) {
                ForEach(TypingSound.allCases) { sound in
                    Text(sound.displayName).tag(sound)
                }
            }
            .onChange(of: preferences.typingSound) { _, sound in
                if preferences.typingSoundEnabled { TypingSoundPlayer.shared.prepare(sound) }
            }

            HStack {
                Slider(value: $preferences.typingSoundVolume, in: 0...1, step: 0.05) {
                    Text(L10n.text("typingSound.volume"))
                }
                Text(preferences.typingSoundVolume, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, alignment: .trailing)
                    .accessibilityHidden(true)
            }

            Button(L10n.text("typingSound.preview")) {
                TypingSoundPlayer.shared.play(preferences.typingSound, volume: preferences.typingSoundVolume)
            }
            .buttonStyle(.bordered)
        }
    }
}
