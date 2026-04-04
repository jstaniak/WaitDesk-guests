import Combine
import Foundation
import Supabase

@MainActor
final class GuestVisitsService: ObservableObject {
    static let shared = GuestVisitsService()

    @Published private(set) var visits: [GuestVisitData] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: EdgeFunctionError?

    private var email = ""
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

    // MARK: - Lifecycle

    func start(email: String) {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != self.email else { return }

        stop()
        self.email = trimmed

        guard !trimmed.isEmpty else {
            visits = []
            error = nil
            isLoading = false
            return
        }

        lifecycleTask = Task { await runLifecycle() }
    }

    func stop() {
        lifecycleTask?.cancel()
        lifecycleTask = nil
    }

    func restart() {
        guard !email.isEmpty else { return }
        stop()
        lifecycleTask = Task { await runLifecycle() }
    }

    func refresh() async {
        await fetchVisits()
    }

    // MARK: - Private

    private func runLifecycle() async {
        await fetchVisits()
        guard !Task.isCancelled else { return }

        do {
            try Task.checkCancellation()
            await supabase.realtimeV2.connect()

            let channel = supabase.realtimeV2.channel("visits:\(email)")
            let stream = await channel.broadcastStream(event: "*")

            defer {
                Task { await channel.unsubscribe() }
            }

            try await channel.subscribeWithError()

            await withTaskGroup(of: Void.self) { group in
                group.addTask { @MainActor [weak self] in
                    for await _ in stream {
                        guard !Task.isCancelled else { return }
                        await self?.fetchVisits()
                    }
                }

                group.addTask { @MainActor [weak self] in
                    while !Task.isCancelled {
                        do {
                            try await Task.sleep(nanoseconds: Self.pollingInterval)
                        } catch {
                            return
                        }
                        await self?.fetchVisits()
                    }
                }
            }
        } catch is CancellationError {
            return
        } catch {
            await pollOnly()
        }
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
        guard !email.isEmpty else { return }

        let wasEmpty = visits.isEmpty
        if wasEmpty { isLoading = true }

        do {
            visits = try await SupabaseFunctionsClient.shared.fetchGuestVisits(email: email)
            error = nil
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            self.error = EdgeFunctionError(error)
            if wasEmpty { visits = [] }
        }

        isLoading = false
    }
}
