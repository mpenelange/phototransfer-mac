import SwiftUI

@main
struct PhotoTransferApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
        .defaultSize(width: 1_420, height: 820)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView(model: model)
                .frame(width: 480)
                .padding()
        }
    }
}
