import SwiftUI

@main
struct BetterWisprApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .task { await model.load() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await model.synchronize() } }
                    if phase == .background {
                        if model.phase == .recording { model.finish() }
                        else if model.phase == .preparing { model.cancel() }
                    }
                }
        }
    }
}
