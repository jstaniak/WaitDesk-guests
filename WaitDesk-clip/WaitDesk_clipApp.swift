import SwiftUI

private let clipPartyShortCode = "7y675ykaw1"

@main
struct WaitDesk_clipApp: App {
    @UIApplicationDelegateAdaptor(WaitDeskAppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            StatusView(partyShortCode: clipPartyShortCode)
                .task(id: clipPartyShortCode) {
                    await PushNotificationRegistrationManager.shared.prepareForStatusViewWithoutPrompt(
                        shortCode: clipPartyShortCode
                    )
                }
        }
    }
}
