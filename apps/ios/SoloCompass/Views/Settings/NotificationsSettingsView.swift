import SwiftUI

/// P2.6 #264: nudge toggle sub-page carved out of SettingsView. Three
/// switches map 1:1 to `ProactiveNudgeScheduler.Toggle`.
public struct NotificationsSettingsView: View {

    @State private var lonelyOn: Bool = true
    @State private var omenOn: Bool = true
    @State private var capsuleOn: Bool = true

    public init() {}

    public var body: some View {
        List {
            Section {
                Toggle("Lonely-hour nudge (17–21)", isOn: $lonelyOn)
                    .onChange(of: lonelyOn) { _, v in
                        ProactiveNudgeScheduler.shared.setEnabled(.lonelyHours, v)
                    }
                Toggle("Morning city omen (7am)", isOn: $omenOn)
                    .onChange(of: omenOn) { _, v in
                        ProactiveNudgeScheduler.shared.setEnabled(.cityOmen, v)
                    }
                Toggle("Capsule arrival", isOn: $capsuleOn)
                    .onChange(of: capsuleOn) { _, v in
                        ProactiveNudgeScheduler.shared.setEnabled(.capsule, v)
                    }
            } header: {
                Text("Proactive nudges")
            } footer: {
                Text("You'll never get more than 3 nudges in a day, regardless of type.")
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            lonelyOn  = ProactiveNudgeScheduler.shared.isEnabled(.lonelyHours)
            omenOn    = ProactiveNudgeScheduler.shared.isEnabled(.cityOmen)
            capsuleOn = ProactiveNudgeScheduler.shared.isEnabled(.capsule)
        }
    }
}

#Preview {
    NavigationStack { NotificationsSettingsView() }
}
