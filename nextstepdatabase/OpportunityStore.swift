//
//  OpportunityStore.swift
//  nextstepdatabase
//
//  Owns the fetched opportunities, load state, and the source (live/cache/demo).
//  On cold launch it shows a fresh disk cache instantly, then refreshes from the
//  network. Decoding of the large (~1.5 MB) payload happens off the main actor;
//  only the final array is assigned on the main actor. Filtering happens
//  on-device against the loaded set.
//

import Foundation
import SwiftUI

enum DataSource: Equatable { case live, cache, demo }

/// Reads and writes the raw opportunities JSON to Application Support so a cold
/// launch can show data instantly before the network responds. The save time
/// is the file's modification date, so no wrapper envelope is needed.
struct OpportunityCache {
    let url: URL

    init(url: URL = OpportunityCache.defaultURL) { self.url = url }

    static var defaultURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("opportunities-cache.json")
    }

    func write(_ data: Data) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    /// Cached raw JSON plus the time it was written.
    func read() -> (data: Data, savedAt: Date)? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let savedAt = (attrs?[.modificationDate] as? Date) ?? Date(timeIntervalSince1970: 0)
        return (data, savedAt)
    }

    func clear() { try? FileManager.default.removeItem(at: url) }
}

@MainActor
@Observable
final class OpportunityStore {
    private let service: OpportunityProviding
    private let cache: OpportunityCache
    private static let maxCacheAge: TimeInterval = 24 * 60 * 60

    var state: LoadState<[Opportunity]> = .idle
    /// Whether the displayed data came from the network, the disk cache, or the
    /// demo fallback — so the UI can label it honestly.
    private(set) var source: DataSource = .live
    /// Non-nil when we're showing cached data because the network is stale or
    /// unavailable, e.g. "Showing saved data from 2 hours ago".
    private(set) var cacheNotice: String?

    var all: [Opportunity] {
        if case .loaded(let items) = state { return items }
        return []
    }

    init(service: OpportunityProviding = LiveOpportunityService(),
         cache: OpportunityCache = OpportunityCache()) {
        self.service = service
        self.cache = cache
    }

    /// Cold-launch load: show fresh cache instantly, then refresh from network.
    func load() async { await load(forceRefresh: false) }

    /// Pull-to-refresh: ignore cache age and refetch, keeping current content on
    /// screen (no spinner) while the request is in flight.
    func refresh() async { await load(forceRefresh: true) }

    private func load(forceRefresh: Bool) async {
        // 1. Instant cache on cold launch — only if nothing is shown yet.
        if !forceRefresh, case .idle = state, let cached = cache.read() {
            let age = Date().timeIntervalSince(cached.savedAt)
            if age < Self.maxCacheAge, let opps = try? await Self.decode(cached.data), !opps.isEmpty {
                source = .cache
                cacheNotice = "Showing saved data from \(Self.relative(cached.savedAt))"
                state = .loaded(opps)
                AppLog.net("shown \(opps.count) opportunities from cache (age \(Int(age))s)")
            }
        }

        // Show a spinner only if there is still nothing on screen.
        if case .loaded = state {} else { state = .loading }

        // 2. Network refresh.
        do {
            let data = try await service.fetchOpportunitiesData()
            let opps = try await Self.decode(data)
            AppLog.net("loaded \(opps.count) opportunities from network")
            guard !opps.isEmpty else {
                if case .loaded = state { return }   // keep whatever we already show
                source = .demo; cacheNotice = nil
                state = .loaded(DemoData.opportunities)
                return
            }
            try? cache.write(data)
            source = .live; cacheNotice = nil
            state = .loaded(opps)
        } catch {
            AppLog.net("network load failed: \(error.localizedDescription)")
            // Already showing something (live or cache)? Keep it on screen.
            if case .loaded = state { return }
            // Nothing shown yet: fall back to cache (even if stale), then demo.
            if let cached = cache.read(), let opps = try? await Self.decode(cached.data), !opps.isEmpty {
                source = .cache
                cacheNotice = "Showing saved data from \(Self.relative(cached.savedAt))"
                state = .loaded(opps)
            } else {
                source = .demo; cacheNotice = nil
                state = .loaded(DemoData.opportunities)
            }
        }
    }

    /// Decodes off the main actor; only the returned array crosses back to it.
    private static func decode(_ data: Data) async throws -> [Opportunity] {
        try await Task.detached(priority: .userInitiated) {
            try LiveOpportunityService.parseOpportunities(data)
        }.value
    }

    private static func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: Date())
    }

    /// Number of distinct organizations across the loaded opportunities.
    var organizationCount: Int {
        Set(all.map { $0.organization.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }).count
    }

    /// Number of distinct source websites (domains) linked from the data.
    var sourceWebsiteCount: Int {
        Set(all.compactMap(\.sourceDomain)).count
    }

    // MARK: Derived facets for filter UI
    var availableCategories: [String] { OpportunityQuery.categories(in: all) }
    var availableGrades: [String] { OpportunityQuery.grades(in: all) }
    var availableFormats: [String] {
        let present = Set(all.compactMap(\.formatLabel))
        return ["Remote", "In-person", "Hybrid"].filter(present.contains)
    }
    var availableCosts: [String] {
        var options: [String] = []
        let labels = all.map { $0.costLabel ?? "Not specified" }
        for candidate in ["Free", "Paid", "Not specified"] where labels.contains(candidate) {
            options.append(candidate)
        }
        return options
    }
}
