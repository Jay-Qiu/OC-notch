import SwiftUI

@main
struct OCNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No visible window — the app uses a custom NSPanel overlay
        Settings {
            EmptyView()
        }
    }
}
