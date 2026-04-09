import Foundation
import Supabase

let supabase = SupabaseClient(
    supabaseURL: URL(string: SupabaseConfig.url)!,
    supabaseKey: SupabaseConfig.anonKey,
    options: .init(auth: .init(emitLocalSessionAsInitialSession: true))
)

struct PartyData: Decodable {
    let name: String
    let status: String
    let businessShortCode: String
    let notified_at: String?
}

struct CompanyData: Decodable {
    let name: String
    let logoData: String?
    let queueLength: Int?
}

struct GuestVisitData: Decodable, Identifiable {
    let companyName: String
    let businessShortCode: String?
    let date: String
    let status: String
    let actualWaitTime: Int?
    let shortCode: String?

    var id: String {
        "\(companyName)-\(date)-\(status)-\(actualWaitTime ?? -1)"
    }

    private enum CodingKeys: String, CodingKey {
        case companyName
        case businessShortCode
        case date
        case status
        case actualWaitTime
        case shortCode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        companyName = try container.decode(String.self, forKey: .companyName)
        businessShortCode = try container.decodeIfPresent(String.self, forKey: .businessShortCode)
        date = try container.decode(String.self, forKey: .date)
        status = try container.decode(String.self, forKey: .status)
        shortCode = try container.decodeIfPresent(String.self, forKey: .shortCode)

        if let intValue = try? container.decodeIfPresent(Int.self, forKey: .actualWaitTime) {
            actualWaitTime = intValue
        } else if let doubleValue = try? container.decodeIfPresent(Double.self, forKey: .actualWaitTime) {
            actualWaitTime = Int(doubleValue.rounded())
        } else if let stringValue = try? container.decodeIfPresent(String.self, forKey: .actualWaitTime),
                  let parsedValue = Int(stringValue)
        {
            actualWaitTime = parsedValue
        } else {
            actualWaitTime = nil
        }
    }
}

final class SupabaseFunctionsClient {
    static let shared = SupabaseFunctionsClient()

    private init() {}

    func fetchPartyData(shortCode: String) async throws -> PartyData {
        let response: PartyResponse = try await supabase.functions.invoke(
            "get-party-data",
            options: .init(body: ["shortCode": shortCode])
        )
        return response.data
    }

    func fetchPosition(shortCode: String) async throws -> Int? {
        let response: PositionResponse = try await supabase.functions.invoke(
            "get-position",
            options: .init(body: ["shortCode": shortCode])
        )
        return response.position
    }

    func cancelQueue(shortCode: String) async throws {
        try await supabase.functions.invoke(
            "cancel-queue",
            options: .init(body: ["shortCode": shortCode])
        )
    }

    func fetchCompanyData(shortCode: String) async throws -> CompanyData {
        let response: CompanyResponse = try await supabase.functions.invoke(
            "get-company-data",
            options: .init(body: ["shortCode": shortCode])
        )
        return response.data
    }

    func fetchGuestVisits() async throws -> [GuestVisitData] {
        let session: Session

        do {
            session = try await supabase.auth.session
        } catch {
            throw EdgeFunctionError.unauthorized
        }

        let response: GuestVisitsResponse = try await supabase.functions.invoke(
            "get-guest-visits",
            options: .init(
                headers: ["Authorization": "Bearer \(session.accessToken)"]
            )
        )
        return response.data
    }

    func registerDeviceToken(_ fcmToken: String) async throws {
        try await supabase.functions.invoke(
            "register-device-token",
            options: .init(body: ["fcmToken": fcmToken])
        )
    }
}

private struct PartyResponse: Decodable {
    let success: Bool
    let data: PartyData
}

private struct CompanyResponse: Decodable {
    let success: Bool
    let data: CompanyData
}

private struct GuestVisitsResponse: Decodable {
    let success: Bool?
    let data: [GuestVisitData]

    private enum CodingKeys: String, CodingKey {
        case success
        case data
    }

    init(from decoder: Decoder) throws {
        if let visits = try? [GuestVisitData](from: decoder) {
            success = true
            data = visits
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decodeIfPresent(Bool.self, forKey: .success)
        data = try container.decode([GuestVisitData].self, forKey: .data)
    }
}

private struct PositionResponse: Decodable {
    let success: Bool
    let position: Int?
}
