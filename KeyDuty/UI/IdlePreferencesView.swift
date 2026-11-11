import CoreGraphics
import SwiftUI

struct IdlePreferencesView: View {
    @ObservedObject var preferences: Preferences

    var body: some View {
        let warnings = preferences.configurationWarnings
        Form {
            Section {
                Toggle(L10n.text("idle.enable"), isOn: $preferences.idleEnabled)
                HStack {
                    Text(L10n.text("idle.delay"))
                    Spacer()
                    Text(preferences.idleTimeoutSeconds, format: .number.precision(.fractionLength(0)))
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                    Text(L10n.text("idle.seconds"))
                    AcceleratingStepper(value: $preferences.idleTimeoutSeconds, in: 5 ... 300)
                        .help(L10n.text("idle.stepperHelp"))
                }
                HStack {
                    Text(L10n.text("idle.key"))
                    Spacer()
                    KeyPicker(
                        title: L10n.text("idle.picker"), selection: idleKeyCode,
                        allowsModifiers: false, preferences: preferences
                    )
                    .frame(width: 240)
                }
            } footer: {
                Text(L10n.text("idle.description"))
            }
            if let message = warnings.idleHoldMessage {
                Section {
                    ConfigurationWarningView(message: message)
                    ForEach(warnings.keyHoldConflicts.filter(\.includesIdle)) { conflict in
                        ConfigurationWarningView(message: conflict.message)
                    }
                } header: {
                    Text(L10n.text("warnings.title"))
                }
            }
        }
        .formStyle(.grouped)
        .padding(8)
    }

    private var idleKeyCode: Binding<CGKeyCode?> {
        Binding(
            get: {
                if case let .sendKey(code) = preferences.idleAction { return code }
                return nil
            },
            set: { preferences.idleAction = $0.map { .sendKey(keyCode: $0) } ?? .none }
        )
    }
}
