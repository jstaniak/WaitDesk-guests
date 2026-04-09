import Foundation
import SwiftUI

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
        }
    }
}

private struct GuestVerificationView: View {
    @ObservedObject private var authService = GuestAuthService.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Verify your email to unlock your waitlist status, visits, and profile on this device.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Email Verification") {
                    if authService.needsReauthentication {
                        Text("Your session expired. Request a new one-time code to keep using the app.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    TextField("Email", text: $authService.emailAddress)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    if authService.isCodeSent {
                        TextField("One-Time Code", text: $authService.otpCode)
                            .textContentType(.oneTimeCode)
                            .keyboardType(.numberPad)
                    }

                    if let errorMessage = authService.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    Button(authService.isCodeSent ? "Resend Code" : "Send Code") {
                        Task {
                            await authService.sendOTP()
                        }
                    }
                    .disabled(authService.isSendingCode || authService.isVerifyingCode)

                    if authService.isCodeSent {
                        Button("Verify Code") {
                            Task {
                                await authService.verifyOTP()
                            }
                        }
                        .disabled(authService.isSendingCode || authService.isVerifyingCode)
                    }
                }
            }
            .navigationTitle("Verify Email")
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
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(Array(visitsService.nonWaitingVisits.enumerated()), id: \.offset) { _, visit in
                                VStack(alignment: .leading, spacing: 12) {
                                    LabeledContent("Venue", value: visit.companyName)
                                    LabeledContent("Date", value: formattedDate(visit.date))
                                    LabeledContent("Status", value: visit.status)
                                    LabeledContent("Wait Time", value: formattedWaitTime(visit.actualWaitTime))
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                        .padding()
                    }
                }
            }
            .refreshable {
                await visitsService.refresh()
            }
        }
    }

    private func formattedWaitTime(_ waitTime: Int?) -> String {
        guard let waitTime else { return "-" }
        return "\(waitTime) min"
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
    @ObservedObject private var visitsService = GuestVisitsService.shared
    @State private var partySize = 1
    @State private var note = ""
    @State private var selectedVenue = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Venue") {
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
                    .disabled(visitsService.isLoading || visitsService.servedVenueNames.isEmpty)
                }

                Section("Guest Details") {
                    TextField("Name", text: .constant(name))
                        .disabled(true)

                    TextField("Email", text: .constant(email))
                        .disabled(true)

                    TextField("Phone Number", text: .constant(phoneNumber))
                        .disabled(true)
                }

                Section("Waitlist Details") {
                    Stepper(value: $partySize, in: 1...99) {
                        HStack {
                            Text("Party Size")
                            Spacer()
                            Text("\(partySize)")
                                .foregroundStyle(.secondary)
                        }
                    }

                    TextField("Note", text: $note, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button("Join Waitlist") {
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .background(Color(.systemBackground))
                .disabled(selectedVenue.isEmpty)
            }
            .onChange(of: visitsService.servedVenueNames) { venues in
                if !venues.contains(selectedVenue) {
                    selectedVenue = ""
                }
            }
        }
    }
}

private struct ProfileView: View {
    @AppStorage("profile.name") private var name = ""
    @AppStorage("profile.phoneNumber") private var phoneNumber = ""
    @ObservedObject private var authService = GuestAuthService.shared

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    TextField("Email", text: .constant(authService.authenticatedEmail ?? ""))
                        .disabled(true)

                    Text("Your email is verified on this device, so the app opens directly until you sign out or the session expires.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button("Sign Out", role: .destructive) {
                        Task {
                            await authService.signOut()
                        }
                    }
                }

                TextField("Name", text: $name)
                    .textContentType(.name)

                TextField("Phone Number", text: $phoneNumber)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
            }
            .navigationTitle("Profile")
        }
    }
}
