//
//  ContentView.swift
//  WaitDesk-clip
//
//  Created by user294080 on 3/28/26.
//

import Supabase
import SwiftUI

let supabase = SupabaseClient(
    supabaseURL: URL(string: SupabaseConfig.url)!,
    supabaseKey: SupabaseConfig.anonKey,
    options: .init(auth: .init(emitLocalSessionAsInitialSession: true))
)

private let partyShortCode = "8yu6hsaflv"

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

struct PositionResponse: Decodable {
    let success: Bool
    let position: Int?
}

struct ContentView: View {
    @State private var name: String = ""
    @State private var status: String = ""
    @State private var position: Int?
    @State private var connectionStatus = "Loading…"

    var body: some View {
        VStack(spacing: 20) {
            Text(connectionStatus)
                .font(.caption2)
                .foregroundStyle(connectionStatus == "Listening ✓" ? .green : .orange)

            if !name.isEmpty {
                Text(name)
                    .font(.largeTitle.weight(.bold))

                if let position {
                    Text("#\(position) in line")
                        .font(.system(.title, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }

                Text(status)
                    .font(.title3)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(statusColor(status).opacity(0.15))
                    .foregroundStyle(statusColor(status))
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .task {
            // 1. Fetch initial party data + position
            async let dataTask = fetchPartyData()
            async let posTask: Void = fetchPosition()
            _ = await posTask
            guard let data = await dataTask else { return }

            // 2. Subscribe to broadcast using businessShortCode from response
            await supabase.realtimeV2.connect()
            connectionStatus = "Subscribing…"

            let channel = supabase.realtimeV2.channel("parties:\(data.businessShortCode)")
            let stream = await channel.broadcastStream(event: "*")

            do {
                try await channel.subscribeWithError()
                connectionStatus = "Listening ✓"
            } catch {
                connectionStatus = "Subscribe error: \(error.localizedDescription)"
                return
            }

            // 3. On each broadcast event, re-fetch and update
            for await _ in stream {
                async let p = fetchPartyData()
                async let q: Void = fetchPosition()
                _ = await (p, q)
            }
        }
    }

    @discardableResult
    private func fetchPartyData() async -> PartyData? {
        do {
            let response: PartyResponse = try await supabase.functions.invoke(
                "get-party-data",
                options: .init(body: ["shortCode": partyShortCode])
            )
            name = response.data.name
            status = response.data.status
            return response.data
        } catch {
            connectionStatus = "Fetch error: \(error.localizedDescription)"
            return nil
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

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "waiting": .orange
        case "served": .green
        case "cancelled": .red
        case "no_show": .gray
        default: .secondary
        }
    }
}

#Preview {
    ContentView()
}
