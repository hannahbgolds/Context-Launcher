import SwiftUI

@main
@MainActor
struct ContextLauncherApplication: App {
    @StateObject private var model: AppModel

    init() {
        _model = StateObject(wrappedValue: AppModel())
    }

    var body: some Scene {
        WindowGroup("Context Launcher") {
            ContextListView()
                .environmentObject(model)
                .frame(minWidth: 920, minHeight: 640)
                .onOpenURL { model.handle(url: $0) }
        }
        .defaultSize(width: 1080, height: 720)
    }
}
