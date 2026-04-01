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

    func fetchCompanyData(shortCode: String) async throws -> CompanyData {
        let response: CompanyResponse = try await supabase.functions.invoke(
            "get-company-data",
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

private struct PositionResponse: Decodable {
    let success: Bool
    let position: Int?
}
