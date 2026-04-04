import Foundation
import SwiftUI

struct ContentView: View {
    private enum Tab: Hashable {
        case status
        case visits
        case joinWaitlist
        case profile
    }

    @AppStorage("profile.email") private var email = ""
    @State private var selectedTab: Tab = .status
    @State private var partyShortCode: String?
    @State private var isLoadingPartyShortCode = false
    @State private var partyShortCodeErrorMessage: String?

    var body: some View {
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
        .task(id: trimmedEmail) {
            guard selectedTab == .status else { return }
            await loadPartyShortCode()
        }
        .onChange(of: selectedTab) { newTab in
            guard newTab == .status else { return }
            Task {
                await loadPartyShortCode()
            }
        }
    }

    @ViewBuilder
    private var statusTab: some View {
        if trimmedEmail.isEmpty {
            EmptyStateView(
                title: "No email in profile",
                systemImage: "envelope.badge",
                message: "Add your email in the Profile tab to load your waitlist status."
            )
        } else if isLoadingPartyShortCode {
            ProgressView("Loading your status...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let partyShortCodeErrorMessage {
            EmptyStateView(
                title: "Couldn't load status",
                systemImage: "exclamationmark.triangle",
                message: partyShortCodeErrorMessage
            )
        } else {
            StatusView(partyShortCode: partyShortCode)
        }
    }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    private func loadPartyShortCode() async {
        guard !trimmedEmail.isEmpty else {
            partyShortCode = nil
            partyShortCodeErrorMessage = nil
            isLoadingPartyShortCode = false
            return
        }

        isLoadingPartyShortCode = true
        partyShortCodeErrorMessage = nil

        do {
            let guestVisits = try await SupabaseFunctionsClient.shared.fetchGuestVisits(email: trimmedEmail)
            partyShortCode = guestVisits.first?.shortCode?.trimmingCharacters(in: .whitespacesAndNewlines)

            if partyShortCode?.isEmpty == true {
                partyShortCode = nil
            }
        } catch {
            partyShortCode = nil
            partyShortCodeErrorMessage = error.localizedDescription
        }

        isLoadingPartyShortCode = false
    }
}

private struct PlaceholderTabView: View {
    let title: String

    var body: some View {
        NavigationStack {
            Text("Empty page")
                .foregroundStyle(.secondary)
                .navigationTitle(title)
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
    @AppStorage("profile.email") private var email = ""
    @State private var visits: [GuestVisitData] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if trimmedEmail.isEmpty {
                    EmptyStateView(
                        title: "No email in profile",
                        systemImage: "envelope.badge",
                        message: "Add your email in the Profile tab to load your visit history."
                    )
                } else if isLoading && visits.isEmpty {
                    ProgressView("Loading visits...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage, visits.isEmpty {
                    EmptyStateView(
                        title: "Couldn't load visits",
                        systemImage: "exclamationmark.triangle",
                        message: errorMessage
                    )
                } else if visits.isEmpty {
                    EmptyStateView(
                        title: "No visits yet",
                        systemImage: "calendar.badge.clock",
                        message: "Your previous waitlist visits will appear here."
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(Array(visits.enumerated()), id: \.offset) { _, visit in
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
            .task(id: trimmedEmail) {
                await loadVisits()
            }
            .refreshable {
                await loadVisits()
            }
        }
    }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    private func loadVisits() async {
        guard !trimmedEmail.isEmpty else {
            visits = []
            errorMessage = nil
            isLoading = false
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            visits = try await SupabaseFunctionsClient.shared.fetchGuestVisits(email: trimmedEmail)
                .filter { $0.status.caseInsensitiveCompare("waiting") != .orderedSame }
        } catch {
            visits = []
            errorMessage = error.localizedDescription
        }

        isLoading = false
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
    @State private var partySize = 1
    @State private var note = ""
    @State private var selectedVenue = ""
    @State private var venues: [String] = []
    @State private var isLoadingVenues = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Venue") {
                    Picker("Venue", selection: $selectedVenue) {
                        if isLoadingVenues {
                            Text("Loading venues...").tag("")
                        } else if venues.isEmpty {
                            Text("No venues available").tag("")
                        } else {
                            Text("Select a venue").tag("")

                            ForEach(venues, id: \.self) { venue in
                                Text(venue).tag(venue)
                            }
                        }
                    }
                    .disabled(isLoadingVenues || venues.isEmpty)
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
            .task(id: trimmedEmail) {
                await loadVenues()
            }
        }
    }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    private func loadVenues() async {
        guard !trimmedEmail.isEmpty else {
            venues = []
            selectedVenue = ""
            isLoadingVenues = false
            return
        }

        isLoadingVenues = true

        do {
            let guestVisits = try await SupabaseFunctionsClient.shared.fetchGuestVisits(email: trimmedEmail)
            let uniqueVenues = Array(
                Set(
                    guestVisits
                        .filter { $0.status.caseInsensitiveCompare("served") == .orderedSame }
                        .map(\.companyName)
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                )
            )
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

            venues = uniqueVenues

            if !venues.contains(selectedVenue) {
                selectedVenue = ""
            }
        } catch {
            venues = []
            selectedVenue = ""
        }

        isLoadingVenues = false
    }
}

private struct ProfileView: View {
    @AppStorage("profile.name") private var name = ""
    @AppStorage("profile.email") private var email = ""
    @AppStorage("profile.phoneNumber") private var phoneNumber = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                    .textContentType(.name)

                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                TextField("Phone Number", text: $phoneNumber)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
            }
        }
    }
}

#Preview {
    ContentView()
}
