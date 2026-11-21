import SwiftUI

@main
struct ShortlistApp: App {
    init() {
        LaunchLog.recordLaunch()
    }

    var body: some Scene {
        WindowGroup {
            StatusView()
        }
    }
}
