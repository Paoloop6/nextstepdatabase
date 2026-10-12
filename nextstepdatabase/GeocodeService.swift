//
//  GeocodeService.swift
//  nextstepdatabase
//
//  Turns free-text opportunity locations into map coordinates. The data has no
//  lat/lng, so we forward-geocode with CLGeocoder. Geocoding is rate-limited by
//  Apple, so this actor: (1) serves from a persistent on-disk cache first,
//  (2) throttles live requests, (3) caps new lookups per app session, and
//  (4) remembers "no result" so it never re-requests a dead address.
//

import Foundation
import CoreLocation

/// A plain, Sendable, codable coordinate.
struct GeoPoint: Codable, Hashable, Sendable {
    let lat: Double
    let lon: Double
    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
}

actor GeocodeService {
    static let shared = GeocodeService()

    private let geocoder = CLGeocoder()
    private var resolved: [String: GeoPoint] = [:]
    private var failed: Set<String> = []
    private let cacheURL: URL

    // Throttling / rate-limit protection.
    private var lastRequest = Date(timeIntervalSince1970: 0)
    private let minInterval: TimeInterval = 0.7
    private var sessionLookups = 0
    private let sessionCap = 90     // remaining addresses resolve on later launches from cache

    private struct Blob: Codable { var resolved: [String: GeoPoint]; var failed: [String] }

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        cacheURL = dir.appendingPathComponent("geocode-cache.json")

        // Seed from the coordinates shipped in the app bundle (server-geocoded
        // ahead of time). This preloads most map pins instantly with no network.
        if let url = Bundle.main.url(forResource: "bundled-coordinates", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let raw = try? JSONDecoder().decode([String: [String: Double]].self, from: data) {
            for (location, coord) in raw {
                if let lat = coord["lat"], let lng = coord["lng"] {
                    resolved[key(location)] = GeoPoint(lat: lat, lon: lng)
                }
            }
        }

        // The on-device disk cache (Apple-geocoded) overrides the bundle where present.
        if let data = try? Data(contentsOf: cacheURL),
           let blob = try? JSONDecoder().decode(Blob.self, from: data) {
            for (k, v) in blob.resolved { resolved[k] = v }
            failed = Set(blob.failed)
        }
    }

    /// Returns a cached coordinate immediately if known (nil if cached-as-failed
    /// or not yet looked up). Pure cache read, never hits the network.
    func cachedPoint(for address: String) -> GeoPoint? {
        resolved[key(address)]
    }

    /// Batch cache read — resolves many addresses in a single actor hop and
    /// returns a map keyed by the original address (only hits are included).
    func cachedPoints(for addresses: [String]) -> [String: GeoPoint] {
        var out: [String: GeoPoint] = [:]
        for address in addresses {
            if let point = resolved[key(address)] { out[address] = point }
        }
        return out
    }

    /// Resolves an address to a coordinate, using cache first. Returns nil for
    /// known failures, throttle/cap deferrals, or genuine no-results.
    func point(for address: String) async -> GeoPoint? {
        let k = key(address)
        if let hit = resolved[k] { return hit }
        if failed.contains(k) { return nil }
        guard sessionLookups < sessionCap else { return nil }

        let elapsed = Date().timeIntervalSince(lastRequest)
        if elapsed < minInterval {
            try? await Task.sleep(for: .seconds(minInterval - elapsed))
        }
        lastRequest = Date()
        sessionLookups += 1

        do {
            let placemarks = try await geocoder.geocodeAddressString(address)
            if let loc = placemarks.first?.location {
                let point = GeoPoint(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude)
                resolved[k] = point
                persist()
                return point
            }
            failed.insert(k); persist()
            return nil
        } catch {
            // Only cache a permanent failure when the address genuinely has no
            // result; transient/network/rate errors stay retryable.
            let ns = error as NSError
            if ns.domain == kCLErrorDomain, ns.code == CLError.geocodeFoundNoResult.rawValue {
                failed.insert(k); persist()
            }
            return nil
        }
    }

    private func key(_ address: String) -> String {
        address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func persist() {
        let blob = Blob(resolved: resolved, failed: Array(failed))
        if let data = try? JSONEncoder().encode(blob) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }
}
