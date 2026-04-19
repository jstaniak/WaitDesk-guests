import UIKit
import FirebaseCore
import FirebaseMessaging
import UserNotifications

enum PushNotificationRegistrationError: LocalizedError {
    case missingFCMToken

    var errorDescription: String? {
        switch self {
        case .missingFCMToken:
            return "Firebase did not return a registration token."
        }
    }
}

@MainActor
final class PushNotificationRegistrationManager {
    static let shared = PushNotificationRegistrationManager()

    private let notificationCenter = UNUserNotificationCenter.current()

    private var activeShortCode: String?
    private var currentFCMToken: String?
    private var hasRegisteredAPNSToken = false

    private init() {}

    func prepareForStatusView(shortCode: String?) async {
        await prepareForStatusView(shortCode: shortCode, shouldPromptForAuthorization: true)
    }

    func prepareForStatusViewWithoutPrompt(shortCode: String?) async {
        await prepareForStatusView(shortCode: shortCode, shouldPromptForAuthorization: false)
    }

    private func prepareForStatusView(shortCode: String?, shouldPromptForAuthorization: Bool) async {
        let trimmedShortCode = shortCode?.trimmingCharacters(in: .whitespacesAndNewlines)
        activeShortCode = (trimmedShortCode?.isEmpty == false) ? trimmedShortCode : nil

        guard let activeShortCode else { return }

        let settings = await notificationCenter.notificationSettings()
        let canRegisterForRemoteNotifications: Bool

        if shouldPromptForAuthorization {
            canRegisterForRemoteNotifications = await requestNotificationAuthorizationIfNeeded(using: settings)
        } else {
            canRegisterForRemoteNotifications = settings.authorizationStatus == .ephemeral
        }

        guard canRegisterForRemoteNotifications else { return }

        await registerFCMToken(for: activeShortCode)
    }

    private func requestNotificationAuthorizationIfNeeded(
        using settings: UNNotificationSettings
    ) async -> Bool {
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            do {
                return try await notificationCenter.requestAuthorization(
                    options: [.alert, .badge, .sound]
                )
            } catch {
                print("Notification authorization failed: \(error.localizedDescription)")
                return false
            }
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    private func registerFCMToken(for shortCode: String) async {
        UIApplication.shared.registerForRemoteNotifications()

        guard hasRegisteredAPNSToken || UIApplication.shared.isRegisteredForRemoteNotifications else {
            return
        }

        await uploadCurrentTokenIfPossible(for: shortCode)
    }

    private func uploadCurrentTokenIfPossible(for shortCode: String) async {
        do {
            let fcmToken = try await fetchFCMToken()
            currentFCMToken = fcmToken
            try await registerToken(fcmToken, shortCode: shortCode)
        } catch {
            print("FCM token preparation failed: \(error.localizedDescription)")
        }
    }

    func handleAPNsTokenRegistration() {
        hasRegisteredAPNSToken = true

        guard let activeShortCode else { return }

        Task {
            await uploadCurrentTokenIfPossible(for: activeShortCode)
        }
    }

    func handleAPNsRegistrationFailure(_ error: Error) {
        hasRegisteredAPNSToken = false
        print("APNs registration failed: \(error.localizedDescription)")
    }

    func handleFCMTokenUpdate(_ fcmToken: String) {
        let trimmedToken = fcmToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else { return }

        currentFCMToken = trimmedToken

        guard let activeShortCode else { return }

        guard hasRegisteredAPNSToken || UIApplication.shared.isRegisteredForRemoteNotifications else {
            return
        }

        Task {
            do {
                try await registerToken(trimmedToken, shortCode: activeShortCode)
            } catch {
                print("FCM token registration failed: \(error.localizedDescription)")
            }
        }
    }

    private func fetchFCMToken() async throws -> String {
        if let currentFCMToken, !currentFCMToken.isEmpty {
            return currentFCMToken
        }

        return try await withCheckedThrowingContinuation { continuation in
            Messaging.messaging().token { token, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let token else {
                    continuation.resume(throwing: PushNotificationRegistrationError.missingFCMToken)
                    return
                }

                let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedToken.isEmpty else {
                    continuation.resume(throwing: PushNotificationRegistrationError.missingFCMToken)
                    return
                }

                Task { @MainActor in
                    PushNotificationRegistrationManager.shared.currentFCMToken = trimmedToken
                }
                continuation.resume(returning: trimmedToken)
            }
        }
    }

    private func registerToken(_ fcmToken: String, shortCode: String) async throws {
        let trimmedShortCode = shortCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedShortCode.isEmpty else { return }

        try await SupabaseFunctionsClient.shared.registerDeviceToken(
            fcmToken,
            shortCode: trimmedShortCode,
            platform: "ios"
        )
    }
}

class WaitDeskAppDelegate: NSObject, UIApplicationDelegate, MessagingDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken
        Task { @MainActor in
            PushNotificationRegistrationManager.shared.handleAPNsTokenRegistration()
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("APNs registration failed: \(error.localizedDescription)")
        Task { @MainActor in
            PushNotificationRegistrationManager.shared.handleAPNsRegistrationFailure(error)
        }
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        print("Received remote notification: \(userInfo)")
        return .newData
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        Task { @MainActor in
            PushNotificationRegistrationManager.shared.handleFCMTokenUpdate(fcmToken)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        print("Presenting notification while active: \(notification.request.content.userInfo)")
        return [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        print("Opened notification: \(response.notification.request.content.userInfo)")
    }
}
