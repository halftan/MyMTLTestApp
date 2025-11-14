import SwiftUI
import AVFoundation

struct SettingsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(Settings.self) private var settings

    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    var body: some View {
        VStack {
            @Bindable var settings = settings

            Button("Set to default translation") {
                settings.resetTranslations()
            }
            .glassBackgroundEffect()
            Slider(value: $settings.translateX, in: -10...10) {
                Text("Translate X")
            }
            .glassBackgroundEffect()
            Slider(value: $settings.translateY, in: -10...10) {
                Text("Translate Y")
            }
            .glassBackgroundEffect()
            Slider(value: $settings.translateZ, in: -10...10) {
                Text("Translate Z")
            }
            .glassBackgroundEffect()

            Toggle("Turn on 3D", isOn: $settings.stereoOn)

            HStack {
                Button("", systemImage: "stop") {
                    settings.paused = true
                    appModel.videoModel.player?.pause()
                    Task {
                        appModel.videoModel.cleanup()
                        await dismissImmersiveSpace()
                    }
                }
                Button("", systemImage: "play") {
                    settings.paused = false
                    appModel.videoModel.player?.play()
                }
                Button("", systemImage: "pause") {
                    settings.paused = true
                    appModel.videoModel.player?.pause()
                }
            }
        }
        .frame(width: 260)
        .padding()
    }
}
