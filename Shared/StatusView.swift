import Combine
import Supabase
import Network
import SwiftUI
import UIKit

private let partyShortCode = "7y675ykaw1"

private struct StatusSnapshot {
    let party: PartyData
    let company: CompanyData
    let companyLogo: UIImage?
    let position: Int?
}

private enum StatusLoadError: Equatable {
    case notFound
    case rateLimited
    case generic

    init(error: Error) {
        guard let functionsError = error as? FunctionsError else {
            self = .generic
            return
        }

        switch functionsError {
        case let .httpError(code, _):
            switch code {
            case 404:
                self = .notFound
            case 429:
                self = .rateLimited            
            default:
                self = .generic
            }
        case .relayError:
            self = .generic
        }
    }

    var title: String {
        switch self {
        case .notFound:
            return "Not found"
        case .rateLimited:
            return "Too many requests"
        case .generic:
            return "Something went wrong"
        }
    }

    var message: String {
        switch self {
        case .notFound:
            return "We couldn't find the requested waitlist information."
        case .rateLimited:
            return "Please wait a moment and try again."
        case .generic:
            return "We couldn't load your latest waitlist status right now."
        }
    }
}

private enum GuestStatus: Equatable {
    case waiting
    case notified
    case served
    case cancelled
    case noShow

    init(status: String, notifiedAt: String?) {
        if status == "waiting", notifiedAt != nil {
            self = .notified
            return
        }

        switch status {
        case "served":
            self = .served
        case "cancelled":
            self = .cancelled
        case "no-show":
            self = .noShow
        default:
            self = .waiting
        }
    }

    var circleBaseColor: Color {
        switch self {
        case .waiting:
            return Color(red: 0.56, green: 0.39, blue: 0.96)
        case .notified:
            return Color(red: 0.93, green: 0.56, blue: 0.60)
        case .served:
            return Color(red: 0.14, green: 0.75, blue: 0.36)
        case .cancelled, .noShow:
            return Color(red: 0.18, green: 0.42, blue: 0.97)
        }
    }

    var circleGradientColors: [Color] {
        switch self {
        case .waiting:
            return [
                Color(red: 0.67, green: 0.52, blue: 0.99),
                circleBaseColor
            ]
        case .notified:
            return [
                Color(red: 0.97, green: 0.67, blue: 0.71),
                circleBaseColor
            ]
        case .served:
            return [
                Color(red: 0.24, green: 0.82, blue: 0.44),
                circleBaseColor
            ]
        case .cancelled, .noShow:
            return [
                Color(red: 0.34, green: 0.57, blue: 0.99),
                circleBaseColor
            ]
        }
    }

    var circleShadowColor: Color {
        circleBaseColor.opacity(0.3)
    }

    var title: String {
        switch self {
        case .waiting:
            return "You're next!"
        case .notified:
            return "Your spot is ready!"
        case .served:
            return "Enjoy your visit!"
        case .cancelled, .noShow:
            return "You're no longer in the queue"
        }
    }

    var message: String {
        switch self {
        case .waiting:
            return ""
        case .notified:
            return "Please proceed to the host stand."
        case .served:
            return "You've been seated. Have a great time!"
        case .cancelled, .noShow:
            return "Please check with staff if you have questions."
        }
    }

    var iconName: String? {
        switch self {
        case .waiting:
            return nil
        case .notified:
            return "exclamationmark"
        case .served:
            return "checkmark"
        case .cancelled, .noShow:
            return "minus"
        }
    }

    var showsInfoCard: Bool {
        self == .waiting || self == .notified
    }

    var circleStrokeOpacity: Double {
        switch self {
        case .cancelled, .noShow:
            return 0.5
        default:
            return 0.68
        }
    }

    var showsLeaveQueueButton: Bool {
        self == .waiting || self == .notified
    }
}

private struct StatusLayoutMetrics {
    let topPadding: CGFloat
    let contentSpacing: CGFloat
    let circleSize: CGFloat
    let logoMaxWidth: CGFloat
    let logoMaxHeight: CGFloat
    let companyNameSize: CGFloat
    let welcomeTextSize: CGFloat

    static func make(for height: CGFloat) -> StatusLayoutMetrics {
        if height < 760 {
            return StatusLayoutMetrics(
                topPadding: 18,
                contentSpacing: 18,
                circleSize: 168,
                logoMaxWidth: 112,
                logoMaxHeight: 64,
                companyNameSize: 24,
                welcomeTextSize: 18
            )
        }

        return StatusLayoutMetrics(
            topPadding: 28,
            contentSpacing: 24,
            circleSize: 188,
            logoMaxWidth: 124,
            logoMaxHeight: 76,
            companyNameSize: 28,
            welcomeTextSize: 20
        )
    }
}

private final class ConnectivityObserver: ObservableObject {
    @Published private(set) var isConnected = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "ConnectivityObserver")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}

struct StatusView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var connectivityObserver = ConnectivityObserver()
    @State private var partyName: String = ""
    @State private var companyName: String = ""
    @State private var companyLogo: UIImage?
    @State private var status: String = ""
    @State private var notifiedAt: String?
    @State private var position: Int?
    @State private var loadError: StatusLoadError?
    @State private var connectionStatus = "Loading..."
    @State private var refreshCycle = 0
    @State private var hasLoadedInitialSnapshot = false
    @State private var wasConnected = true
    @State private var isCancelling = false
    @State private var cancelErrorMessage: String?

    private var guestStatus: GuestStatus {
        GuestStatus(status: status, notifiedAt: notifiedAt)
    }

    private var isInitialLoading: Bool {
        !hasLoadedInitialSnapshot && partyName.isEmpty && loadError == nil
    }

    var body: some View {
        GeometryReader { geometry in
            let metrics = StatusLayoutMetrics.make(for: geometry.size.height)

            Group {
                if isInitialLoading {
                    loadingStateView
                } else if let loadError {
                    errorStateView(loadError)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: metrics.contentSpacing) {
                            if companyLogo != nil || !companyName.isEmpty {
                                companyHeader(metrics: metrics)
                            }

                            if !partyName.isEmpty {
                                welcomeText(fontSize: metrics.welcomeTextSize)

                                if guestStatus == .waiting {
                                    Text("Your position updates automatically as the queue moves.")
                                        .font(.system(size: 17))
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 16)
                                }

                                statusCircle(size: metrics.circleSize)

                                VStack(spacing: 8) {
                                    Text(guestStatus.title)
                                        .font(.system(size: 24, weight: .bold))
                                        .multilineTextAlignment(.center)

                                    if !guestStatus.message.isEmpty {
                                        Text(guestStatus.message)
                                            .font(.system(size: 17))
                                            .foregroundStyle(.secondary)
                                            .multilineTextAlignment(.center)
                                    }
                                }
                                .padding(.horizontal, 16)

                                if guestStatus.showsInfoCard {
                                    infoCard
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 24)
                        .padding(.top, metrics.topPadding)
                        .padding(.bottom, 24)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(.systemBackground))
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !partyName.isEmpty && guestStatus.showsLeaveQueueButton && !isInitialLoading && loadError == nil {
                    leaveQueueButton
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                        .padding(.bottom, geometry.safeAreaInsets.bottom > 0 ? 8 : 14)
                        .background(Color(.systemBackground))
                }
            }
        }
        .alert("Unable to leave queue", isPresented: cancelErrorAlertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(cancelErrorMessage ?? "Please try again.")
        }
        .onAppear {
            wasConnected = connectivityObserver.isConnected
        }
        .task(id: refreshCycle) {
            await runStatusLifecycle()
        }
        .onChange(of: scenePhase) { newPhase in
            guard newPhase == .active else { return }
            restartStatusLifecycle()
        }
        .onChange(of: connectivityObserver.isConnected) { isConnected in
            defer { wasConnected = isConnected }
            guard isConnected, !wasConnected else { return }
            restartStatusLifecycle()
        }
    }

    private func restartStatusLifecycle() {
        refreshCycle += 1
    }

    private func runStatusLifecycle() async {
        var data: PartyData?

        while !Task.isCancelled {
            data = await refreshStatusSnapshot()

            if data != nil || loadError != nil {
                break
            }

            connectionStatus = "Loading your status"

            do {
                try await Task.sleep(nanoseconds: 2_000_000_000)
            } catch is CancellationError {
                connectionStatus = "Loading your status"
                return
            } catch {
                return
            }
        }

        guard let data else { return }
        hasLoadedInitialSnapshot = true

        do {
            try Task.checkCancellation()
            await supabase.realtimeV2.connect()
            connectionStatus = "Subscribing..."

            let channel = supabase.realtimeV2.channel("parties:\(data.businessShortCode)")
            let stream = await channel.broadcastStream(event: "*")

            defer {
                Task {
                    await channel.unsubscribe()
                }
            }

            try await channel.subscribeWithError()
            connectionStatus = "Listening"

            for await _ in stream {
                try Task.checkCancellation()
                _ = await refreshStatusSnapshot()
            }
        } catch is CancellationError {
            connectionStatus = hasLoadedInitialSnapshot ? "Reconnecting..." : "Loading..."
        } catch {
            connectionStatus = "Subscribe error: \(error.localizedDescription)"
        }
    }

    private func companyHeader(metrics: StatusLayoutMetrics) -> some View {
        VStack(spacing: 14) {
            if let companyLogo {
                Image(uiImage: companyLogo)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: metrics.logoMaxWidth, maxHeight: metrics.logoMaxHeight)
                    .padding(16)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(color: .black.opacity(0.08), radius: 14, y: 6)
            }

            if !companyName.isEmpty {
                Text(companyName)
                    .font(.system(size: metrics.companyNameSize, weight: .bold))
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func welcomeText(fontSize: CGFloat) -> some View {
        (
            Text("Welcome, ")
            + Text(partyName).foregroundColor(Color(red: 0.56, green: 0.39, blue: 0.96))
            + Text("!")
        )
        .font(.system(size: fontSize))
        .multilineTextAlignment(.center)
    }

    private func statusCircle(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: guestStatus.circleGradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .shadow(color: guestStatus.circleShadowColor, radius: 18, y: 8)

            if guestStatus == .waiting {
                Text(positionText)
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
            } else if let iconName = guestStatus.iconName {
                Image(systemName: iconName)
                    .font(.system(size: 72, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }

    private var positionText: String {
        if let position, position > 0 {
            return "\(position)"
        }

        return "?"
    }

    private var infoCard: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 20, weight: .medium))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text("Keep this page open")
                    .font(.system(size: 17, weight: .semibold))
                Text("Your position will update automatically. No need to refresh.")
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }

    private var leaveQueueButton: some View {
        Button {
            Task {
                await cancelQueue()
            }
        } label: {
            HStack(spacing: 10) {
                if isCancelling {
                    ProgressView()
                        .tint(.primary)
                } else {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 18, weight: .medium))
                }

                Text(isCancelling ? "Leaving queue..." : "Leave queue")
                    .font(.system(size: 20, weight: .medium))
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .disabled(isCancelling)
    }

    private var loadingStateView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)

            Text("Loading your status")
                .font(.system(size: 24, weight: .bold))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorStateView(_ loadError: StatusLoadError) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color(red: 0.93, green: 0.56, blue: 0.60))

            VStack(spacing: 8) {
                Text(loadError.title)
                    .font(.system(size: 24, weight: .bold))
                    .multilineTextAlignment(.center)

                Text(loadError.message)
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @discardableResult
    private func refreshStatusSnapshot() async -> PartyData? {
        do {
            async let partyTask = fetchPartyData()
            async let positionTask = fetchPosition()

            let party = try await partyTask
            async let companyTask = fetchCompanyData(shortCode: party.businessShortCode)

            let (company, position) = try await (companyTask, positionTask)
            let companyLogo = await loadCompanyLogo(from: company.logoData)
            try Task.checkCancellation()
            let snapshot = StatusSnapshot(
                party: party,
                company: company,
                companyLogo: companyLogo,
                position: position
            )

            try Task.checkCancellation()
            apply(snapshot)
            connectionStatus = "Loaded"
            return snapshot.party
        } catch is CancellationError {
            return nil
        } catch {
            guard !Task.isCancelled else { return nil }

            let statusLoadError = StatusLoadError(error: error)

            if hasLoadedInitialSnapshot || statusLoadError != .generic {
                apply(error: statusLoadError)
                connectionStatus = "Fetch error: \(error.localizedDescription)"
            } else {
                loadError = nil
                connectionStatus = "Loading your status"
            }
            return nil
        }
    }

    private func apply(_ snapshot: StatusSnapshot) {
        loadError = nil
        partyName = snapshot.party.name
        companyName = snapshot.company.name
        companyLogo = snapshot.companyLogo
        status = snapshot.party.status
        notifiedAt = snapshot.party.notified_at

        withAnimation {
            position = snapshot.position
        }
    }

    private func apply(error: StatusLoadError) {
        loadError = error
        partyName = ""
        companyName = ""
        companyLogo = nil
        status = ""
        notifiedAt = nil

        withAnimation {
            position = nil
        }
    }

    private func fetchPartyData() async throws -> PartyData {
        try await SupabaseFunctionsClient.shared.fetchPartyData(shortCode: partyShortCode)
    }

    private func fetchCompanyData(shortCode: String) async throws -> CompanyData {
        try await SupabaseFunctionsClient.shared.fetchCompanyData(shortCode: shortCode)
    }

    private func fetchPosition() async throws -> Int? {
        try await SupabaseFunctionsClient.shared.fetchPosition(shortCode: partyShortCode)
    }

    private func loadCompanyLogo(from logoData: String?) async -> UIImage? {
        guard let logoData, !logoData.isEmpty else { return nil }

        if let imageData = decodeBase64ImageData(from: logoData) {
            return UIImage(data: imageData)
        }

        guard let url = URL(string: logoData) else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return UIImage(data: data)
        } catch {
            print("Company logo load error: \(error.localizedDescription)")
            return nil
        }
    }

    private func decodeBase64ImageData(from value: String) -> Data? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if let commaIndex = trimmedValue.firstIndex(of: ","),
           trimmedValue[..<commaIndex].contains("base64")
        {
            let encoded = String(trimmedValue[trimmedValue.index(after: commaIndex)...])
            return Data(base64Encoded: encoded)
        }

        return Data(base64Encoded: trimmedValue)
    }

    private var cancelErrorAlertBinding: Binding<Bool> {
        Binding(
            get: { cancelErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    cancelErrorMessage = nil
                }
            }
        )
    }

    @MainActor
    private func cancelQueue() async {
        guard !isCancelling else { return }

        isCancelling = true
        defer { isCancelling = false }

        do {
            try await SupabaseFunctionsClient.shared.cancelQueue(shortCode: partyShortCode)

            withAnimation {
                status = "cancelled"
                notifiedAt = nil
                position = nil
            }
        } catch {
            cancelErrorMessage = error.localizedDescription
        }
    }
}

#Preview {
    StatusView()
}
