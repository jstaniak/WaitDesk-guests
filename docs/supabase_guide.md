# Supabase Swift – Realtime Broadcast & Edge Functions

Guide for using Supabase Realtime Broadcast and Edge Functions in the WaitDesk App Clip.

## Package Version

| Package | Version | Source |
|---------|---------|--------|
| supabase-swift | `>= 2.0.0` (up to next major) | [github.com/supabase/supabase-swift](https://github.com/supabase/supabase-swift) |

Added via Swift Package Manager in Xcode. The `Supabase` product is linked to the `WaitDesk-clip` target.

## Official Documentation

- **Realtime Broadcast**: https://supabase.com/docs/guides/realtime/broadcast
- **Swift Broadcast examples**: https://supabase.com/docs/guides/realtime/broadcast?language=swift
- **Edge Functions (invoke)**: https://supabase.com/docs/reference/swift/functions-invoke
- **Swift SDK reference**: https://supabase.com/docs/reference/swift/introduction
- **Auth session warning (PR #822)**: https://github.com/supabase/supabase-swift/pull/822

## Client Initialization

```swift
import Supabase

let supabase = SupabaseClient(
    supabaseURL: URL(string: "https://<project>.supabase.co")!,
    supabaseKey: "<anon-key>",
    options: .init(auth: .init(emitLocalSessionAsInitialSession: true))
)
```

The `emitLocalSessionAsInitialSession: true` option silences the deprecation warning about initial session behavior. See [PR #822](https://github.com/supabase/supabase-swift/pull/822).

## Realtime Broadcast

### Subscribing to a Channel

```swift
// 1. Connect the Realtime WebSocket
await supabase.realtimeV2.connect()

// 2. Create a channel — Supabase prefixes it as "realtime:parties:<code>"
let channel = supabase.realtimeV2.channel("parties:\(businessShortCode)")

// 3. Get an AsyncStream BEFORE subscribing
let stream = await channel.broadcastStream(event: "*")  // "*" = all events

// 4. Subscribe (throws on failure)
try await channel.subscribeWithError()

// 5. Process incoming events
for await event in stream {
    // event is a JSONObject with broadcast payload
    print(event)
}
```

### Key Points

- **Call `connect()` first** — `subscribeWithError()` may silently fail if the WebSocket isn't open and `connectOnSubscribe` isn't enabled.
- **Use `broadcastStream(event:)`** (AsyncStream) — This is the recommended pattern from official docs. The callback-based `onBroadcast(event:callback:)` had a wildcard (`*`) bug fixed in [PR #749](https://github.com/supabase/supabase-swift/pull/749).
- **Use `subscribeWithError()`** — The plain `subscribe()` is deprecated and swallows errors via `try?`.
- **Create the stream before subscribing** — Otherwise you may miss events delivered between subscribe and stream creation.
- **Channel naming**: Pass `"parties:l2d3p95nm4"` to `channel()`. The SDK internally prefixes it as `"realtime:parties:l2d3p95nm4"`.

## Edge Functions

### Invoking a Function

```swift
// Define response models matching the function's JSON output
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

// Invoke the function — body is encoded as JSON automatically
let response: PartyResponse = try await supabase.functions.invoke(
    "get-party-data",
    options: .init(body: ["shortCode": partyShortCode])
)
```

### Key Points

- **Generic return type** — `invoke` decodes JSON into the type you specify (`PartyResponse` above).
- **Input** — Pass a `Codable` body via `FunctionInvokeOptions(body:)`. It's sent as `POST` with `Content-Type: application/json`.
- **Auth** — The SDK automatically attaches the anon key (or user JWT if signed in) as the `Authorization` header.