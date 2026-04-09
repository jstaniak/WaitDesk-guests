import Combine
import Foundation

@MainActor
final class GuestVisitsService: ObservableObject {
    static let shared = GuestVisitsService()

    @Published private(set) var visits: [GuestVisitData] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: EdgeFunctionError?

    private var lifecycleTask: Task<Void, Never>?

    private static let pollingInterval: UInt64 = 60_000_000_000

    private init() {}

    // MARK: - Derived properties

    var currentVisitShortCode: String? {
        let code = visits.first?.shortCode?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (code?.isEmpty == true) ? nil : code
    }

    var nonWaitingVisits: [GuestVisitData] {
        visits.filter { $0.status.caseInsensitiveCompare("waiting") != .orderedSame }
    }

    var servedVenueNames: [String] {
        Array(
            Set(
                visits
                    .filter { $0.status.caseInsensitiveCompare("served") == .orderedSame }
                    .map(\.companyName)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        )
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func venueBusinessShortCode(for venueName: String) -> String? {
        let normalizedVenueName = venueName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedVenueName.isEmpty else { return nil }

        return visits.first {
            $0.status.caseInsensitiveCompare("served") == .orderedSame
                && $0.companyName.trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare(normalizedVenueName) == .orderedSame
        }?.businessShortCode?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Lifecycle

    func start() {
        guard GuestAuthService.shared.isAuthenticated else {
            reset()
            return
        }

        guard lifecycleTask == nil else { return }
        lifecycleTask = Task { await runLifecycle() }
    }

    func stop() {
        lifecycleTask?.cancel()
        lifecycleTask = nil
    }

    func restart() {
        guard GuestAuthService.shared.isAuthenticated else {
            reset()
            return
        }
        stop()
        lifecycleTask = Task { await runLifecycle() }
    }

    func refresh() async {
        guard GuestAuthService.shared.isAuthenticated else {
            reset()
            return
        }
        await fetchVisits()
    }

    func reset() {
        stop()
        visits = []
        error = nil
        isLoading = false
    }

    // MARK: - Private

    private func runLifecycle() async {
        await fetchVisits()

        guard !Task.isCancelled else { return }
        await pollOnly()
    }

    private func pollOnly() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: Self.pollingInterval)
            } catch {
                return
            }
            await fetchVisits()
        }
    }

    private func fetchVisits() async {
        guard GuestAuthService.shared.isAuthenticated else {
            reset()
            return
        }

        let wasEmpty = visits.isEmpty
        if wasEmpty { isLoading = true }

        do {
            visits = try await SupabaseFunctionsClient.shared.fetchGuestVisits()
            error = nil
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            let edgeError = EdgeFunctionError(error)
            self.error = edgeError
            if wasEmpty || edgeError.requiresReauthentication { visits = [] }

            if edgeError.requiresReauthentication {
                stop()
                Task {
                    await GuestAuthService.shared.handleExpiredOrInvalidSession()
                }
            }
        }

        isLoading = false
    }
}
