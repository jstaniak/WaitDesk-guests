import SwiftUI

@main
struct WaitDesk_clipApp: App {
    @UIApplicationDelegateAdaptor(WaitDeskAppDelegate.self) var appDelegate
    @State private var clipPartyShortCode: String?

    var body: some Scene {
        WindowGroup {
            StatusView(partyShortCode: clipPartyShortCode)
                .task(id: clipPartyShortCode) {
                    await PushNotificationRegistrationManager.shared.prepareForStatusViewWithoutPrompt(
                        shortCode: clipPartyShortCode
                    )
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
                    updateShortCode(from: userActivity.webpageURL)
                }
                .onOpenURL { url in
                    updateShortCode(from: url)
                }
        }
    }

    private func updateShortCode(from url: URL?) {
        let shortCode = url?.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        clipPartyShortCode = (shortCode?.isEmpty == false) ? shortCode : nil
    }
}
