
import Supabase
import SwiftUI
import UIKit

let supabase = SupabaseClient(
    supabaseURL: URL(string: SupabaseConfig.url)!,
    supabaseKey: SupabaseConfig.anonKey,
    options: .init(auth: .init(emitLocalSessionAsInitialSession: true))
)

private let partyShortCode = "7y675ykaw1"

struct PartyData: Decodable {
    let name: String
    let status: String
    let businessShortCode: String
    let notified_at: String?
}

struct PartyResponse: Decodable {
    let success: Bool
    let data: PartyData
}

struct CompanyData: Decodable {
    let name: String
    let logoData: String?
}

struct CompanyResponse: Decodable {
    let success: Bool
    let data: CompanyData
}

struct PositionResponse: Decodable {
    let success: Bool
    let position: Int?
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

    var circleColor: Color {
        switch self {
        case .waiting:
            return Color(red: 0.56, green: 0.39, blue: 0.96)
        case .notified:
            return Color(red: 0.93, green: 0.56, blue: 0.60)
        case .served:
            return Color(red: 0.14, green: 0.75, blue: 0.36)
        case .cancelled, .noShow:
            return Color(.systemGray5)
        }
    }

    var circleShadowColor: Color {
        switch self {
        case .waiting:
            return Color(red: 0.56, green: 0.39, blue: 0.96).opacity(0.24)
        case .notified:
            return Color(red: 0.88, green: 0.48, blue: 0.54).opacity(0.24)
        case .served:
            return Color(red: 0.10, green: 0.67, blue: 0.32).opacity(0.24)
        case .cancelled, .noShow:
            return Color.black.opacity(0.08)
        }
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

    var darkIcon: Bool {
        self == .cancelled || self == .noShow
    }
}

struct ContentView: View {
    @State private var partyName: String = ""
    @State private var companyName: String = ""
    @State private var companyLogo: UIImage?
    @State private var status: String = ""
    @State private var notifiedAt: String?
    @State private var position: Int?
    @State private var connectionStatus = "Loading..."

    private var guestStatus: GuestStatus {
        GuestStatus(status: status, notifiedAt: notifiedAt)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                Spacer(minLength: 28)

                if companyLogo != nil || !companyName.isEmpty {
                    companyHeader
                }

                if !partyName.isEmpty {
                    welcomeText

                    if guestStatus == .waiting {
                        Text("Your position updates automatically as the queue moves.")
                            .font(.system(size: 17))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }

                    statusCircle

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

                Spacer(minLength: 28)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .task {
            async let dataTask = fetchPartyData()
            async let posTask: Void = fetchPosition()
            _ = await posTask
            guard let data = await dataTask else { return }
            await fetchCompanyData(shortCode: data.businessShortCode)

            await supabase.realtimeV2.connect()
            connectionStatus = "Subscribing..."

            let channel = supabase.realtimeV2.channel("parties:\(data.businessShortCode)")
            let stream = await channel.broadcastStream(event: "*")

            do {
                try await channel.subscribeWithError()
                connectionStatus = "Listening"
            } catch {
                connectionStatus = "Subscribe error: \(error.localizedDescription)"
                return
            }

            for await _ in stream {
                async let partyTask = fetchPartyData()
                async let positionTask: Void = fetchPosition()
                _ = await (partyTask, positionTask)
            }
        }
    }

    private var companyHeader: some View {
        VStack(spacing: 14) {
            if let companyLogo {
                Image(uiImage: companyLogo)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 124, maxHeight: 76)
                    .padding(16)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(color: .black.opacity(0.08), radius: 14, y: 6)
            }

            if !companyName.isEmpty {
                Text(companyName)
                    .font(.system(size: 28, weight: .bold))
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var welcomeText: some View {
        Text("Welcome, \(Text(partyName).foregroundStyle(Color(red: 0.56, green: 0.39, blue: 0.96)))!")
        .font(.system(size: 20))
        .multilineTextAlignment(.center)
    }

    private var statusCircle: some View {
        ZStack {
            Circle()
                .fill(guestStatus.circleColor)
                .frame(width: 188, height: 188)
                .overlay(
                    Circle()
                        .stroke(.white.opacity(0.68), lineWidth: 4)
                )
                .shadow(color: guestStatus.circleShadowColor, radius: 16, y: 8)

            if guestStatus == .waiting {
                Text(positionText)
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
            } else if let iconName = guestStatus.iconName {
                Image(systemName: iconName)
                    .font(.system(size: 72, weight: .bold))
                    .foregroundStyle(guestStatus.darkIcon ? Color.primary : Color.white)
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
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }

    @discardableResult
    private func fetchPartyData() async -> PartyData? {
        do {
            let response: PartyResponse = try await supabase.functions.invoke(
                "get-party-data",
                options: .init(body: ["shortCode": partyShortCode])
            )
            partyName = response.data.name
            status = response.data.status
            notifiedAt = response.data.notified_at
            return response.data
        } catch {
            connectionStatus = "Fetch error: \(error.localizedDescription)"
            return nil
        }
    }

    private func fetchCompanyData(shortCode: String) async {
        do {
            let response: CompanyResponse = try await supabase.functions.invoke(
                "get-company-data",
                options: .init(body: ["shortCode": shortCode])
            )
            companyName = response.data.name
            companyLogo = await loadCompanyLogo(from: response.data.logoData)
        } catch {
            print("Company fetch error: \(error.localizedDescription)")
        }
    }

    private func fetchPosition() async {
        do {
            let response: PositionResponse = try await supabase.functions.invoke(
                "get-position",
                options: .init(body: ["shortCode": partyShortCode])
            )
            withAnimation {
                position = response.position
            }
        } catch {
            print("Position fetch error: \(error.localizedDescription)")
        }
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
}

#Preview {
    ContentView()
}
