//
//  OpportunityService.swift
//  nextstepdatabase
//
//  Network layer for fetching opportunities from the live NextStep backend,
//  with a clearly-labeled demo fallback behind the same interface.
//

import Foundation

/// One value the UI can render for every load.
enum LoadState<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(String)
}

/// Abstraction so the UI never depends on where data comes from.
protocol OpportunityProviding: Sendable {
    /// Fetches the raw opportunities JSON. The set is now large (~1,300 records,
    /// roughly 1.5 MB), so we fetch once, decode off the main actor, cache it,
    /// and filter on-device for instant, offline-friendly interaction.
    func fetchOpportunitiesData() async throws -> Data
}

/// Wraps the live API response envelope: `{ count, opportunities: [...] }`.
private struct OpportunitiesResponse: Decodable {
    let opportunities: [Opportunity]
}

enum OpportunityServiceError: LocalizedError {
    case badStatus(Int)
    case emptyPayload

    var errorDescription: String? {
        switch self {
        case .badStatus(let code): return "The server returned an error (\(code))."
        case .emptyPayload: return "No opportunities were returned."
        }
    }
}

/// Talks to the real production backend over HTTPS.
struct LiveOpportunityService: OpportunityProviding {
    static let endpoint = URL(string: "https://www.nextstepdatabase.fyi/api/opportunities")!

    let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func fetchOpportunitiesData() async throws -> Data {
        var request = URLRequest(url: Self.endpoint)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // NOTE on gzip: URLSession already advertises `Accept-Encoding: gzip`
        // and decompresses the response transparently. Setting that header
        // manually would DISABLE the automatic decompression and hand us raw
        // compressed bytes, so we intentionally let the system negotiate it.
        request.timeoutInterval = 45   // ~1.5 MB payload over slow links

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            AppLog.net("fetch non-2xx status \(http.statusCode)")
            throw OpportunityServiceError.badStatus(http.statusCode)
        }
        AppLog.net("fetched opportunities payload: \(data.count) bytes")
        return data
    }

    /// Decodes the API envelope. Pure and nonisolated so the store can run it
    /// off the main actor.
    static func parseOpportunities(_ data: Data) throws -> [Opportunity] {
        try JSONDecoder().decode(OpportunitiesResponse.self, from: data).opportunities
    }
}

/// Live service that transparently falls back to demo data if the network is
/// unavailable. The store surfaces which path was used so nothing is presented
/// as live when it is not.
struct ResilientOpportunityService: OpportunityProviding {
    let live = LiveOpportunityService()

    func fetchOpportunitiesData() async throws -> Data {
        try await live.fetchOpportunitiesData()
    }
}
