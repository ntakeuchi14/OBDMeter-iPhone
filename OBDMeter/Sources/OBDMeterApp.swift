import SwiftUI

@main
struct OBDMeterApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environment(model)
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: model.setForeground(true)
            case .background: model.setForeground(false)
            default: break
            }
        }
    }
}
