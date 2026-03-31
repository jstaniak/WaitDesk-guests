import SwiftUI

@main
struct WaitDesk_guestsApp: App {
    @UIApplicationDelegateAdaptor(WaitDeskAppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
