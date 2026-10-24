import SwiftUI

@main
struct OBDMeterApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            Text("OBDMeter \(model.dashboards.count)")
        }
    }
}
