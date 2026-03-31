import UIKit
import FirebaseCore
import FirebaseMessaging
import Supabase

class WaitDeskAppDelegate: NSObject, UIApplicationDelegate, MessagingDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        Messaging.messaging().delegate = self
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        Task {
            await sendTokenToBackend(fcmToken)
        }
    }

    private func sendTokenToBackend(_ fcmToken: String) async {
        do {
            try await supabase.functions.invoke(
                "register-device-token",
                options: .init(body: ["fcmToken": fcmToken])
            )
        } catch {
            print("FCM token registration failed: \(error.localizedDescription)")
        }
    }
}
