import SwiftUI

@main struct TraceGlassApp:App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var settings=AppSettings()
    private let storage:ProjectStorage = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            let root=FileManager.default.temporaryDirectory.appendingPathComponent("TraceGlassUITests")
            try? FileManager.default.removeItem(at:root)
            return ProjectStorage(root:root)
        }
        #endif
        return ProjectStorage()
    }()
    var body:some Scene {
        WindowGroup {
            HomeView(settings:settings,storage:storage)
                .tint(TraceDesign.accent)
                .preferredColorScheme(settings.value.followSystemTheme ? nil:.dark)
        }
    }
}
