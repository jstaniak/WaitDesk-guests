import Combine
import Foundation
import Supabase

@MainActor
final class GuestAuthService: ObservableObject {
    static let shared = GuestAuthService()

    @Published var emailAddress: String
    @Published var otpCode = ""
    @Published private(set) var authenticatedEmail: String?
    @Published private(set) var isAuthenticated = false
    @Published private(set) var isLoadingSession = true
    @Published private(set) var isSendingCode = false
    @Published private(set) var isVerifyingCode = false
    @Published private(set) var isCodeSent = false
    @Published private(set) var needsReauthentication = false
    @Published private(set) var errorMessage: String?

    private let profileEmailKey = "profile.email"
    private var authStateTask: Task<Void, Never>?
    private var shouldPromptAfterNextSignOut = false
    private var isUserInitiatedSignOut = false

    private init() {
        emailAddress = UserDefaults.standard.string(forKey: profileEmailKey) ?? ""
        observeAuthState()
    }

    deinit {
        authStateTask?.cancel()
    }

    func sendOTP() async {
        let email = normalizedEmail(emailAddress)
        guard isValidEmail(email) else {
            errorMessage = "Enter a valid email address."
            return
        }

        errorMessage = nil
        isSendingCode = true
        defer { isSendingCode = false }

        do {
            try await supabase.auth.signInWithOTP(email: email)
            emailAddress = email
            isCodeSent = true
            otpCode = ""
            persistProfileEmail(email)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func verifyOTP() async {
        let email = normalizedEmail(emailAddress)
        let code = otpCode.trimmingCharacters(in: .whitespacesAndNewlines)

        guard isValidEmail(email) else {
            errorMessage = "Enter a valid email address."
            return
        }

        guard !code.isEmpty else {
            errorMessage = "Enter the one-time code from your email."
            return
        }

        errorMessage = nil
        isVerifyingCode = true
        defer { isVerifyingCode = false }

        do {
            let response = try await supabase.auth.verifyOTP(
                email: email,
                token: code,
                type: .email
            )

            if let session = response.session {
                applyAuthenticatedSession(session)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() async {
        errorMessage = nil
        isUserInitiatedSignOut = true

        do {
            try await supabase.auth.signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func handleExpiredOrInvalidSession() async {
        errorMessage = "Your session expired. Verify your email again to continue."
        shouldPromptAfterNextSignOut = true

        do {
            try await supabase.auth.signOut()
        } catch {
            applySignedOut(promptForReauthentication: true)
        }
    }

    private func observeAuthState() {
        authStateTask = Task { [weak self] in
            for await (event, session) in supabase.auth.authStateChanges {
                await self?.handleAuthStateChange(event: event, session: session)
            }
        }
    }

    private func handleAuthStateChange(event: AuthChangeEvent, session: Session?) async {
        switch event {
        case .initialSession:
            if let session {
                applyAuthenticatedSession(session)
            } else {
                applySignedOut(promptForReauthentication: false)
            }
            isLoadingSession = false
        case .signedIn, .tokenRefreshed, .userUpdated, .mfaChallengeVerified:
            if let session {
                applyAuthenticatedSession(session)
            }
            isLoadingSession = false
        case .signedOut, .userDeleted:
            let prompt = shouldPromptAfterNextSignOut || (!isUserInitiatedSignOut && isAuthenticated)
            applySignedOut(promptForReauthentication: prompt)
            shouldPromptAfterNextSignOut = false
            isUserInitiatedSignOut = false
            isLoadingSession = false
        case .passwordRecovery:
            break
        }
    }

    private func applyAuthenticatedSession(_ session: Session) {
        let email = normalizedEmail(session.user.email ?? emailAddress)

        authenticatedEmail = email.isEmpty ? nil : email
        isAuthenticated = authenticatedEmail != nil
        needsReauthentication = false
        isCodeSent = false
        otpCode = ""
        errorMessage = nil

        if let authenticatedEmail {
            emailAddress = authenticatedEmail
            persistProfileEmail(authenticatedEmail)
        }
    }

    private func applySignedOut(promptForReauthentication: Bool) {
        authenticatedEmail = nil
        isAuthenticated = false
        isCodeSent = false
        otpCode = ""
        needsReauthentication = promptForReauthentication
    }

    private func persistProfileEmail(_ email: String) {
        UserDefaults.standard.set(email, forKey: profileEmailKey)
    }

    private func normalizedEmail(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func isValidEmail(_ value: String) -> Bool {
        value.contains("@") && value.contains(".")
    }
}
