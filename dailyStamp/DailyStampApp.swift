import SwiftUI

@main
struct DailyStampApp: App {
    var body: some Scene {
        MenuBarExtra {
            ContentView()
        } label: {
            Label("DS", systemImage: "checkmark.circle.fill")
        }
        .menuBarExtraStyle(.window)
    }
}
