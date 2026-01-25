import SwiftUI

@main
struct TodoApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
        #if os(macOS)
            Settings {
                SettingsView()
            }
        #endif
    }
}
