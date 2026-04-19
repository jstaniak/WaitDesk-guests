import Foundation
import Supabase
import SwiftUI
import UIKit

struct ContentView: View {
    private enum Tab: Hashable {
        case status
        case visits
        case joinWaitlist
        case profile
    }

    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var authService = GuestAuthService.shared
    @ObservedObject private var visitsService = GuestVisitsService.shared
    @State private var selectedTab: Tab = .status

    var body: some View {
        Group {
            if authService.isLoadingSession {
                ProgressView("Checking your session...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if authService.isAuthenticated {
                authenticatedApp
            } else {
                GuestVerificationView()
            }
        }
        .task(id: authService.authenticatedEmail) {
            if authService.isAuthenticated {
                visitsService.start()
            } else {
                selectedTab = .status
                visitsService.reset()
            }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                if authService.isAuthenticated {
                    visitsService.restart()
                    if selectedTab == .status {
                        Task {
                            await PushNotificationRegistrationManager.shared.prepareForStatusView(
                                shortCode: visitsService.currentVisitShortCode
                            )
                        }
                    }
                }
            } else if newPhase == .background {
                visitsService.stop()
            }
        }
    }

    private var authenticatedApp: some View {
        TabView(selection: $selectedTab) {
            statusTab
                .tabItem {
                    Label("Status", systemImage: "checkmark.circle")
                }
                .tag(Tab.status)

            VisitsView()
                .tabItem {
                    Label("Visits", systemImage: "calendar")
                }
                .tag(Tab.visits)

            JoinWaitlistView()
                .tabItem {
                    Label("Join Waitlist", systemImage: "person.3")
                }
                .tag(Tab.joinWaitlist)

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle")
                }
                .tag(Tab.profile)
        }
        .tint(AppTheme.primary)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(Color(.systemBackground), for: .tabBar)
    }

    @ViewBuilder
    private var statusTab: some View {
        if visitsService.isLoading {
            ProgressView("Loading your status...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = visitsService.error, visitsService.visits.isEmpty {
            EmptyStateView(
                title: error.title,
                systemImage: "exclamationmark.triangle",
                message: error.message
            )
        } else {
            StatusView(
                partyShortCode: visitsService.currentVisitShortCode,
                onStatusChanged: { _, _ in
                    Task {
                        await visitsService.refresh()
                    }
                }
            )
            .task(id: visitsService.currentVisitShortCode) {
                await PushNotificationRegistrationManager.shared.prepareForStatusView(
                    shortCode: visitsService.currentVisitShortCode
                )
            }
        }
    }
}

private struct GuestVerificationView: View {
    @ObservedObject private var authService = GuestAuthService.shared

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        ScreenHeader(
                            eyebrow: "WaitDesk for guests",
                            title: authService.isCodeSent ? "Check your inbox" : "Verify your email",
                            message: "Verify your email to unlock live waitlist status, visit history, and your saved profile on this device.",
                            systemImage: "envelope.badge.shield.half.filled"
                        )

                        AppCard {
                            VStack(alignment: .leading, spacing: 18) {
                                if authService.needsReauthentication {
                                    BannerView(
                                        title: "Session expired",
                                        message: "Request a new one-time code to keep using the app.",
                                        systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90"
                                    )
                                }

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Email")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.secondary)

                                    TextField("name@example.com", text: $authService.emailAddress)
                                        .textContentType(.emailAddress)
                                        .keyboardType(.emailAddress)
                                        .autocapitalization(.none)
                                        .disableAutocorrection(true)
                                        .appInputStyle()
                                }

                                if authService.isCodeSent {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("One-Time Code")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.secondary)

                                        TextField("6-digit code", text: $authService.otpCode)
                                            .textContentType(.oneTimeCode)
                                            .keyboardType(.numberPad)
                                            .appInputStyle()
                                    }
                                }

                                if let errorMessage = authService.errorMessage {
                                    BannerView(
                                        title: "Something went wrong",
                                        message: errorMessage,
                                        systemImage: "exclamationmark.triangle.fill",
                                        tint: .red
                                    )
                                }

                                VStack(spacing: 12) {
                                    Button(authService.isCodeSent ? "Resend Code" : "Send Code") {
                                        Task {
                                            await authService.sendOTP()
                                        }
                                    }
                                    .buttonStyle(PrimaryActionButtonStyle())
                                    .disabled(authService.isSendingCode || authService.isVerifyingCode)

                                    if authService.isCodeSent {
                                        Button("Verify Code") {
                                            Task {
                                                await authService.verifyOTP()
                                            }
                                        }
                                        .buttonStyle(SecondaryActionButtonStyle())
                                        .disabled(authService.isSendingCode || authService.isVerifyingCode)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                }
            }
            .navigationTitle("Login")
            .navigationBarTitleDisplayMode(.inline)
            .tint(AppTheme.primary)
        }
    }
}

private struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct VisitsView: View {
    @ObservedObject private var visitsService = GuestVisitsService.shared

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                Group {
                    if visitsService.isLoading && visitsService.nonWaitingVisits.isEmpty {
                        ProgressView("Loading visits...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let error = visitsService.error, visitsService.nonWaitingVisits.isEmpty {
                        EmptyStateView(
                            title: error.title,
                            systemImage: "exclamationmark.triangle",
                            message: error.message
                        )
                    } else if visitsService.nonWaitingVisits.isEmpty {
                        EmptyStateView(
                            title: "No visits yet",
                            systemImage: "calendar.badge.clock",
                            message: "Your previous waitlist visits will appear here."
                        )
                    } else {
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 18) {
                                ScreenHeader(
                                    eyebrow: "VISIT HISTORY",
                                    title: "Your recent visits",
                                    message: "See where you've been, how long you waited, and how each visit ended."
                                )

                                AppCard {
                                    HStack(spacing: 12) {
                                        StatPill(title: "Completed", value: "\(visitsService.nonWaitingVisits.count)")
                                        StatPill(title: "Average wait", value: averageWaitLabel)
                                        StatPill(title: "Latest", value: latestVenueName)
                                    }
                                }

                                LazyVStack(spacing: 10) {
                                    ForEach(visitsService.nonWaitingVisits) { visit in
                                        AppCard {
                                            VStack(alignment: .leading, spacing: 8) {
                                                HStack(alignment: .top, spacing: 12) {
                                                    VStack(alignment: .leading, spacing: 4) {
                                                        Text(visit.companyName)
                                                            .font(.headline)

                                                        Text(formattedDate(visit.date))
                                                            .font(.subheadline)
                                                            .foregroundStyle(.secondary)

                                                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                                                            Text("WAIT TIME")
                                                                .font(.caption2.weight(.semibold))
                                                                .foregroundStyle(.secondary)
                                                            Text(formattedWaitTime(visit.actualWaitTime))
                                                                .font(.subheadline.weight(.semibold))
                                                        }
                                                    }

                                                    Spacer(minLength: 0)

                                                    StatusBadge(
                                                        label: formattedStatus(visit.status),
                                                        tint: statusTint(for: visit.status)
                                                    )
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 24)
                        }
                    }
                }
            }
            .navigationTitle("Visits")
            .navigationBarTitleDisplayMode(.inline)
            .tint(AppTheme.primary)
            .refreshable {
                await visitsService.refresh()
            }
        }
    }

    private func formattedWaitTime(_ waitTime: Int?) -> String {
        guard let waitTime else { return "Unknown" }
        return "\(waitTime) min"
    }

    private func formattedStatus(_ status: String) -> String {
        status
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }

    private func statusTint(for status: String) -> Color {
        switch status.lowercased() {
        case "served":
            return Color(red: 0.16, green: 0.67, blue: 0.39)
        case "cancelled", "no-show":
            return Color(red: 0.30, green: 0.46, blue: 0.93)
        default:
            return AppTheme.primary
        }
    }

    private var averageWaitLabel: String {
        let waitTimes = visitsService.nonWaitingVisits.compactMap(\.actualWaitTime)
        guard !waitTimes.isEmpty else { return "N/A" }
        let average = waitTimes.reduce(0, +) / waitTimes.count
        return "\(average) min"
    }

    private var latestVenueName: String {
        visitsService.nonWaitingVisits.first?.companyName ?? "None"
    }

    private func formattedDate(_ value: String) -> String {
        for formatter in Self.iso8601Formatters {
            if let date = formatter.date(from: value) {
                return Self.displayDateFormatter.string(from: date)
            }
        }

        return value
    }

    private static let iso8601Formatters: [ISO8601DateFormatter] = {
        let standard = ISO8601DateFormatter()

        let fractionalSeconds = ISO8601DateFormatter()
        fractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return [fractionalSeconds, standard]
    }()

    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct JoinWaitlistView: View {
    @AppStorage("profile.name") private var name = ""
    @AppStorage("profile.email") private var email = ""
    @AppStorage("profile.phoneNumber") private var phoneNumber = ""
    @ObservedObject private var authService = GuestAuthService.shared
    @ObservedObject private var visitsService = GuestVisitsService.shared
    @State private var partySize = 1
    @State private var note = ""
    @State private var selectedVenue = ""
    @State private var venueQueueLength: Int?
    @State private var isLoadingVenueDetails = false
    @State private var isSubmittingWaitlist = false
    @State private var joinWaitlistErrorMessage: String?
    @State private var joinWaitlistSuccessMessage: String?
    @State private var venueDetailsError: String?

    private var selectedVenueBusinessShortCode: String? {
        visitsService.venueBusinessShortCode(for: selectedVenue)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var requestEmail: String {
        let value = authService.authenticatedEmail ?? email
        return value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var trimmedPhoneNumber: String? {
        let value = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private var trimmedNote: String? {
        let value = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private var canSubmitJoinWaitlist: Bool {
        joinWaitlistValidationMessage == nil && !isSubmittingWaitlist
    }

    private var joinWaitlistValidationMessage: String? {
        if selectedVenue.isEmpty {
            return "Choose a venue to continue."
        }

        if selectedVenueBusinessShortCode?.isEmpty != false {
            return "This venue is missing its business code."
        }

        if trimmedName.isEmpty {
            return "Add your name in the Profile tab to continue."
        }

        if requestEmail.isEmpty {
            return "Your verified email is unavailable. Sign in again to continue."
        }

        return nil
    }

    private var joinWaitlistSuccessAlertBinding: Binding<Bool> {
        Binding(
            get: { joinWaitlistSuccessMessage != nil },
            set: { isPresented in
                if !isPresented {
                    joinWaitlistSuccessMessage = nil
                }
            }
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        ScreenHeader(
                            eyebrow: "JOIN AGAIN",
                            title: "Get back in line faster",
                            message: "Pick a venue you've already visited, confirm your party details, and join the waitlist in seconds.",
                            systemImage: "person.3.sequence.fill"
                        )

                        AppCard {
                            VStack(alignment: .leading, spacing: 14) {
                                SectionLabel(title: "Venue", subtitle: "Only previously served venues are available right now.")

                                Picker("Venue", selection: $selectedVenue) {
                                    if visitsService.isLoading && visitsService.servedVenueNames.isEmpty {
                                        Text("Loading venues...").tag("")
                                    } else if visitsService.servedVenueNames.isEmpty {
                                        Text("No venues available").tag("")
                                    } else {
                                        Text("Select a venue").tag("")

                                        ForEach(visitsService.servedVenueNames, id: \.self) { venue in
                                            Text(venue).tag(venue)
                                        }
                                    }
                                }
                                .pickerStyle(.menu)
                                .disabled(visitsService.isLoading || visitsService.servedVenueNames.isEmpty)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(AppTheme.fieldBackground)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(AppTheme.border.opacity(0.18), lineWidth: 1)
                                )

                                if !selectedVenue.isEmpty {
                                    StatusBadge(label: selectedVenue, tint: AppTheme.primary)
                                }

                                if isLoadingVenueDetails {
                                    HStack(spacing: 10) {
                                        ProgressView()
                                            .controlSize(.small)

                                        Text("Loading current queue length...")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                } else if let venueQueueLength {
                                    InfoTile(
                                        title: "Current queue",
                                        value: "\(venueQueueLength) guests waiting",
                                        systemImage: "person.2.wave.2"
                                    )
                                } else if let venueDetailsError {
                                    BannerView(
                                        title: "Queue length unavailable",
                                        message: venueDetailsError,
                                        systemImage: "exclamationmark.triangle.fill",
                                        tint: .orange
                                    )
                                }
                            }
                        }

                        AppCard {
                            VStack(alignment: .leading, spacing: 14) {
                                SectionLabel(title: "Guest details", subtitle: "These come from your saved profile.")

                                ReadOnlyField(title: "Name", value: name, systemImage: "person")
                                ReadOnlyField(title: "Email", value: requestEmail, systemImage: "envelope")
                                ReadOnlyField(title: "Phone Number", value: phoneNumber, systemImage: "phone")

                                if trimmedName.isEmpty {
                                    BannerView(
                                        title: "Name required",
                                        message: "Add your name in the Profile tab before joining the waitlist.",
                                        systemImage: "person.crop.circle.badge.exclamationmark",
                                        tint: .orange
                                    )
                                }
                            }
                        }

                        AppCard {
                            VStack(alignment: .leading, spacing: 18) {
                                SectionLabel(title: "Waitlist details", subtitle: "Add a few details to help the host team.")

                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text("Party Size")
                                            .font(.headline)

                                        Spacer()

                                        StatusBadge(label: "\(partySize) guests", tint: AppTheme.secondary)
                                    }

                                    Stepper("Party Size", value: $partySize, in: 1...99)
                                        .labelsHidden()
                                }
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(AppTheme.fieldBackground)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(AppTheme.border.opacity(0.18), lineWidth: 1)
                                )

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Note")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.secondary)

                                    TextField("Anything the venue should know?", text: $note, axis: .vertical)
                                        .lineLimit(3, reservesSpace: true)
                                        .appInputStyle()
                                }

                                if let joinWaitlistErrorMessage {
                                    BannerView(
                                        title: "Unable to join waitlist",
                                        message: joinWaitlistErrorMessage,
                                        systemImage: "exclamationmark.triangle.fill",
                                        tint: .red
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 10) {
                    if let joinWaitlistValidationMessage {
                        Text(joinWaitlistValidationMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        Task {
                            await joinWaitlist()
                        }
                    } label: {
                        HStack(spacing: 10) {
                            if isSubmittingWaitlist {
                                ProgressView()
                                    .tint(.white)
                            }

                            Text(isSubmittingWaitlist ? "Joining..." : "Join Waitlist")
                        }
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                    .disabled(!canSubmitJoinWaitlist)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .background(.ultraThinMaterial)
            }
            .alert("You're on the waitlist", isPresented: joinWaitlistSuccessAlertBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(joinWaitlistSuccessMessage ?? "")
            }
            .navigationTitle("Join Waitlist")
            .navigationBarTitleDisplayMode(.inline)
            .tint(AppTheme.primary)
            .onChange(of: visitsService.servedVenueNames) { venues in
                if !venues.contains(selectedVenue) {
                    selectedVenue = ""
                }
            }
            .task(id: selectedVenue) {
                await loadSelectedVenueDetails()
            }
        }
    }

    @MainActor
    private func joinWaitlist() async {
        joinWaitlistErrorMessage = nil

        guard let businessShortCode = selectedVenueBusinessShortCode?.trimmingCharacters(in: .whitespacesAndNewlines),
              !businessShortCode.isEmpty
        else {
            joinWaitlistErrorMessage = "This venue is missing its business code."
            return
        }

        guard !trimmedName.isEmpty else {
            joinWaitlistErrorMessage = "Add your name in the Profile tab before joining the waitlist."
            return
        }

        guard !requestEmail.isEmpty else {
            joinWaitlistErrorMessage = "Your verified email is unavailable. Sign in again to continue."
            return
        }

        isSubmittingWaitlist = true
        defer { isSubmittingWaitlist = false }

        do {
            let result = try await SupabaseFunctionsClient.shared.selfCheckIn(
                input: SelfCheckInInput(
                    businessShortCode: businessShortCode,
                    name: trimmedName,
                    email: requestEmail,
                    partySize: partySize,
                    phoneNumber: trimmedPhoneNumber,
                    note: trimmedNote
                )
            )

            note = ""
            partySize = 1
            joinWaitlistSuccessMessage = formattedJoinWaitlistSuccessMessage(for: result)
            await visitsService.refresh()
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            joinWaitlistErrorMessage = await messageForJoinWaitlistError(error)
        }
    }

    @MainActor
    private func loadSelectedVenueDetails() async {
        venueQueueLength = nil
        venueDetailsError = nil

        guard !selectedVenue.isEmpty else { return }
        guard let businessShortCode = selectedVenueBusinessShortCode, !businessShortCode.isEmpty else {
            venueDetailsError = "This venue is missing its business code."
            return
        }

        isLoadingVenueDetails = true
        defer { isLoadingVenueDetails = false }

        do {
            let companyData = try await SupabaseFunctionsClient.shared.fetchCompanyData(shortCode: businessShortCode)
            guard selectedVenueBusinessShortCode == businessShortCode else { return }
            venueQueueLength = companyData.queueLength

            if companyData.queueLength == nil {
                venueDetailsError = "The venue did not return a queue length."
            }
        } catch {
            guard selectedVenueBusinessShortCode == businessShortCode else { return }
            venueDetailsError = error.localizedDescription
        }
    }

    @MainActor
    private func messageForJoinWaitlistError(_ error: Error) async -> String {
        if String(describing: error).contains("sessionMissing") {
            await authService.handleExpiredOrInvalidSession()
            return "Your session expired. Verify your email again to continue."
        }

        guard let functionsError = error as? FunctionsError else {
            return error.localizedDescription
        }

        switch functionsError {
        case let .httpError(code, _):
            switch code {
            case 400:
                return "Please review your details and try again."
            case 401:
                await authService.handleExpiredOrInvalidSession()
                return "Your session expired. Verify your email again to continue."
            case 403:
                return "This venue is not accepting self check-ins right now."
            case 429:
                return "Too many requests. Please wait a moment and try again."
            case 500, 503:
                return "The waitlist service is temporarily unavailable. Please try again soon."
            default:
                return "Server error (\(code))"
            }
        case .relayError:
            return "Unable to reach the server"
        }
    }

    private func formattedJoinWaitlistSuccessMessage(for result: SelfCheckInData) -> String {
        if let estimatedWaitTime = result.estimatedWaitTime {
            return "You joined \(selectedVenue). Estimated wait: \(estimatedWaitTime) min."
        }

        return "You joined \(selectedVenue)."
    }
}

private struct ProfileView: View {
    @AppStorage("profile.name") private var name = ""
    @AppStorage("profile.phoneNumber") private var phoneNumber = ""
    @ObservedObject private var authService = GuestAuthService.shared

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        ScreenHeader(
                            eyebrow: "PROFILE",
                            title: "Guest details",
                            message: "Keep your contact information ready so future waitlist check-ins are quick and accurate.",
                            systemImage: "person.crop.circle.badge.checkmark"
                        )

                        AppCard {
                            VStack(alignment: .leading, spacing: 14) {
                                SectionLabel(title: "Account", subtitle: "Your email stays verified on this device until you sign out or the session expires.")

                                ReadOnlyField(
                                    title: "Verified Email",
                                    value: authService.authenticatedEmail ?? "",
                                    systemImage: "checkmark.seal"
                                )

                                Button("Sign Out", role: .destructive) {
                                    Task {
                                        await authService.signOut()
                                    }
                                }
                                .buttonStyle(SecondaryActionButtonStyle(tint: .red))
                            }
                        }

                        AppCard {
                            VStack(alignment: .leading, spacing: 14) {
                                SectionLabel(title: "Personal info", subtitle: "This information is reused when you join the waitlist.")

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Name")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.secondary)

                                    TextField("Your name", text: $name)
                                        .textContentType(.name)
                                        .appInputStyle()
                                }

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Phone Number")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.secondary)

                                    TextField("Your phone number", text: $phoneNumber)
                                        .textContentType(.telephoneNumber)
                                        .keyboardType(.phonePad)
                                        .appInputStyle()
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .tint(AppTheme.primary)
        }
    }
}

private enum AppTheme {
    static let primary = Color(red: 0.45, green: 0.34, blue: 0.96)
    static let secondary = Color(red: 0.11, green: 0.69, blue: 0.84)
    static let backgroundTop = Color(
        uiColor: UIColor { traitCollection in
            if traitCollection.userInterfaceStyle == .dark {
                return UIColor(red: 0.09, green: 0.08, blue: 0.15, alpha: 1)
            }

            return UIColor(red: 0.97, green: 0.95, blue: 1.00, alpha: 1)
        }
    )
    static let backgroundBottom = Color(
        uiColor: UIColor { traitCollection in
            if traitCollection.userInterfaceStyle == .dark {
                return UIColor(red: 0.06, green: 0.12, blue: 0.18, alpha: 1)
            }

            return UIColor(red: 0.92, green: 0.97, blue: 1.00, alpha: 1)
        }
    )
    static let cardBackground = Color(uiColor: .secondarySystemBackground)
    static let fieldBackground = Color(uiColor: .tertiarySystemBackground)
    static let border = Color(uiColor: .separator)
}

private struct AppBackground: View {
    var body: some View {
        LinearGradient(
            colors: [AppTheme.backgroundTop, AppTheme.backgroundBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

private struct ScreenHeader: View {
    let eyebrow: String
    let title: String
    let message: String
    var systemImage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(AppTheme.primary)
                    .frame(width: 56, height: 56)
                    .background(
                        Circle()
                            .fill(AppTheme.cardBackground)
                    )
            }

            Text(eyebrow)
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(.secondary)

            Text(title)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AppCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(AppTheme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(AppTheme.border.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: AppTheme.primary.opacity(0.10), radius: 24, y: 14)
    }
}

private struct SectionLabel: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

private struct BannerView: View {
    let title: String
    let message: String
    let systemImage: String
    var tint: Color = AppTheme.primary

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(tint.opacity(0.10))
        )
    }
}

private struct StatPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.fieldBackground)
        )
    }
}

private struct StatusBadge: View {
    let label: String
    let tint: Color

    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.12))
            )
    }
}

private struct InfoTile: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.fieldBackground)
        )
    }
}

private struct ReadOnlyField: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(AppTheme.primary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(value.isEmpty ? "Not set" : value)
                    .font(.subheadline)
                    .foregroundStyle(value.isEmpty ? .secondary : .primary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.fieldBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppTheme.border.opacity(0.18), lineWidth: 1)
        )
    }
}

private struct PrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.primary, AppTheme.secondary],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .shadow(color: AppTheme.primary.opacity(0.22), radius: 16, y: 8)
    }
}

private struct SecondaryActionButtonStyle: ButtonStyle {
    var tint: Color = AppTheme.primary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(AppTheme.fieldBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(AppTheme.border.opacity(0.18), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
    }
}

private struct AppInputStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AppTheme.fieldBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(AppTheme.border.opacity(0.18), lineWidth: 1)
            )
    }
}

private extension View {
    func appInputStyle() -> some View {
        modifier(AppInputStyle())
    }
}
