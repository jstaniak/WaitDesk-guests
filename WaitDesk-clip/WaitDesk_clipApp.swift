import SwiftUI

@main
struct WaitDesk_clipApp: App {
    @UIApplicationDelegateAdaptor(WaitDeskAppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            StatusView()
        }
    }
}
