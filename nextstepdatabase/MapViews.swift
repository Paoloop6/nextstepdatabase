//
//  MapViews.swift
//  nextstepdatabase
//
//  Two map features, app-only:
//   1. OpportunityLocationMap — a small Apple Maps view for a single
//      opportunity's specific address (on the detail and match-detail screens).
//   2. GlobalMapView — a world map with a pin for every opportunity that has a
//      real, geocodable address.
//
//  Both use GeocodeService (cache-first, throttled) since the data has no
//  coordinates. Remote / nationwide / blank locations are never shown as a pin.
//

import SwiftUI
import MapKit

// MARK: - Apple Maps deep link

enum AppleMaps {
    /// Builds an Apple Maps URL for an address (and optional coordinate + name).
    static func url(query: String, point: GeoPoint?) -> URL? {
        var comps = URLComponents(string: "https://maps.apple.com/")
        var items = [URLQueryItem(name: "q", value: query)]
        if let point { items.append(URLQueryItem(name: "ll", value: "\(point.lat),\(point.lon)")) }
        comps?.queryItems = items
        return comps?.url
    }
}

// MARK: - Single-opportunity map

/// Renders a compact map for one opportunity's address, or an explicit note when
/// the location isn't a mappable point. Never implies a location that isn't there.
struct OpportunityLocationMap: View {
    let rawLocation: String?
    let title: String
    /// Backend-supplied coordinate; when present we skip geocoding entirely.
    var presetPoint: GeoPoint? = nil

    @Environment(\.openURL) private var openURL
    @State private var point: GeoPoint?
    @State private var status: Status = .idle
    @State private var showFullMap = false

    private enum Status { case idle, loading, resolved, notMappable, failed }

    private var query: String? { Opportunity.mapQuery(from: rawLocation) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Location")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            switch status {
            case .notMappable:
                note(icon: "wifi", text: rawLocation.map { "\($0)" } ?? "Location not specified — this opportunity has no fixed place.")
            case .idle, .loading:
                HStack(spacing: Theme.Space.sm) {
                    ProgressView()
                    Text("Locating \(rawLocation ?? "")…").font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 80)
            case .failed:
                note(icon: "mappin.slash", text: rawLocation.map { "Couldn’t map “\($0)”." } ?? "Couldn’t map this location.")
            case .resolved:
                if let point {
                    // Inline preview is non-interactive so the page still scrolls;
                    // tapping it opens a full-screen, fully interactive map.
                    Button {
                        showFullMap = true
                    } label: {
                        Map(initialPosition: .region(MKCoordinateRegion(
                            center: point.coordinate,
                            span: MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)))) {
                            Marker(title, coordinate: point.coordinate)
                                .tint(Color.brandAccent)
                        }
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                        .allowsHitTesting(false)
                        .overlay(alignment: .topTrailing) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.footnote.weight(.bold))
                                .padding(8)
                                .background(.ultraThinMaterial, in: Circle())
                                .padding(Theme.Space.sm)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Map showing \(rawLocation ?? title). Double tap to open full screen.")

                    if let loc = rawLocation {
                        Text(loc).font(.footnote).foregroundStyle(.secondary)
                    }
                    Button {
                        if let url = AppleMaps.url(query: rawLocation ?? title, point: point) { openURL(url) }
                    } label: {
                        Label("Open in Apple Maps", systemImage: "map")
                            .frame(maxWidth: .infinity, minHeight: Theme.minTouchTarget)
                    }
                    .buttonStyle(.bordered)
                    .tint(.brandAccent)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .task(id: rawLocation) { await resolve() }
        .fullScreenCover(isPresented: $showFullMap) {
            if let point {
                FullScreenMapView(point: point, title: title, rawLocation: rawLocation)
            }
        }
    }

    private func resolve() async {
        guard let query else { status = .notMappable; return }
        if let presetPoint {                       // backend coords → instant, no geocoding
            point = presetPoint; status = .resolved; return
        }
        if let cached = await GeocodeService.shared.cachedPoint(for: query) {
            point = cached; status = .resolved; return
        }
        status = .loading
        if let p = await GeocodeService.shared.point(for: query) {
            point = p; status = .resolved
        } else {
            status = .failed
        }
    }

    private func note(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Full-screen single-location map

private struct FullScreenMapView: View {
    let point: GeoPoint
    let title: String
    let rawLocation: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Map(initialPosition: .region(MKCoordinateRegion(
                center: point.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)))) {
                Marker(title, coordinate: point.coordinate)
                    .tint(Color.brandAccent)
            }
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(rawLocation ?? title)
            .inlineNavTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        if let url = AppleMaps.url(query: rawLocation ?? title, point: point) { openURL(url) }
                    } label: {
                        Label("Apple Maps", systemImage: "map")
                    }
                }
            }
        }
    }
}

// MARK: - Global map

private struct MapPin: Identifiable, Hashable {
    let id: String
    let title: String
    let point: GeoPoint
    let opportunity: Opportunity
}

@MainActor
@Observable
private final class GlobalMapModel {
    var pins: [MapPin] = []
    var mappableTotal = 0
    var resolvedCount = 0
    var isWorking = false

    private var built = false

    func build(from opportunities: [Opportunity]) async {
        // Ignore the initial empty call; only build once real data has loaded.
        guard !opportunities.isEmpty, !built else { return }
        built = true
        let mappable = opportunities.compactMap { opp -> (Opportunity, String)? in
            guard let q = opp.mapQuery else { return nil }
            return (opp, q)
        }
        mappableTotal = mappable.count
        isWorking = true

        // 1) Instant batch: backend coords + all cached/bundled coords resolved in
        //    ONE actor hop and assigned to `pins` a SINGLE time — so ~hundreds of
        //    pins appear in one render instead of one-at-a-time (which was O(n²)).
        let cached = await GeocodeService.shared.cachedPoints(for: mappable.map(\.1))
        var initial: [MapPin] = []
        var remaining: [(Opportunity, String)] = []
        for (opp, q) in mappable {
            if let p = opp.storedPoint ?? cached[q] {
                initial.append(MapPin(id: opp.id, title: opp.title, point: p, opportunity: opp))
            } else {
                remaining.append((opp, q))
            }
        }
        pins = initial
        resolvedCount = initial.count

        // 2) Live pass for the rest (throttled + capped). Append in small batches
        //    so the map isn't re-rendered on every single lookup.
        var batch: [MapPin] = []
        for (opp, q) in remaining {
            if let p = await GeocodeService.shared.point(for: q) {
                batch.append(MapPin(id: opp.id, title: opp.title, point: p, opportunity: opp))
                if batch.count >= 15 {
                    pins.append(contentsOf: batch); resolvedCount = pins.count; batch.removeAll(keepingCapacity: true)
                }
            }
        }
        if !batch.isEmpty { pins.append(contentsOf: batch); resolvedCount = pins.count }
        isWorking = false
    }
}

struct GlobalMapView: View {
    @Environment(OpportunityStore.self) private var store
    @Environment(SavedStore.self) private var saved
    @State private var model = GlobalMapModel()
    @State private var selectedID: String?
    /// Start on a stable continental-US view (the data is US-centric) and never
    /// move the camera automatically, so the user's zoom/pan always stick instead
    /// of snapping back as more pins stream in from geocoding.
    @State private var camera: MapCameraPosition = .region(GlobalMapView.usRegion)
    /// Tracks the live camera region so the +/- buttons can zoom from it.
    @State private var currentRegion: MKCoordinateRegion = GlobalMapView.usRegion
    @State private var path: [Opportunity] = []

    static let usRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35),
        span: MKCoordinateSpan(latitudeDelta: 55, longitudeDelta: 60))

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .top) {
                Map(position: $camera, selection: $selectedID) {
                    ForEach(model.pins) { pin in
                        Marker(pin.title, coordinate: pin.point.coordinate)
                            .tint(Color.brandAccent)
                            .tag(pin.id)
                    }
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .mapControls {
                    MapCompass()
                    MapScaleView()
                }
                .onMapCameraChange(frequency: .onEnd) { context in
                    currentRegion = context.region
                }
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .bottomTrailing) { zoomControls }

                statusBar
            }
            .navigationTitle("Map")
            .inlineNavTitle()
            .navigationDestination(for: Opportunity.self) { OpportunityDetailView(opportunity: $0) }
            .sheet(item: selectedOpportunity) { opp in
                selectionSheet(opp)
                    .fixedDetent(240)
            }
            .task(id: store.all.count) { await model.build(from: store.all) }
        }
    }

    // Bridges the selected id <-> an optional Opportunity for the sheet.
    private var selectedOpportunity: Binding<Opportunity?> {
        Binding(
            get: { model.pins.first { $0.id == selectedID }?.opportunity },
            set: { newValue in selectedID = newValue?.id }
        )
    }

    private var statusBar: some View {
        Group {
            if model.pins.isEmpty && model.isWorking {
                Label("Placing opportunities on the map…", systemImage: "globe.americas")
            } else {
                Label("\(model.resolvedCount) of \(model.mappableTotal) mapped\(model.isWorking ? " · locating more…" : "")",
                      systemImage: "mappin.and.ellipse")
            }
        }
        .font(.footnote.weight(.medium))
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, Theme.Space.sm)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.top, Theme.Space.sm)
        .accessibilityLabel("\(model.resolvedCount) of \(model.mappableTotal) opportunities mapped")
    }

    private var zoomControls: some View {
        VStack(spacing: 0) {
            zoomButton(system: "plus", label: "Zoom in") { zoom(by: 0.5) }
            Divider().frame(width: 44)
            zoomButton(system: "minus", label: "Zoom out") { zoom(by: 2.0) }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
            .strokeBorder(Color.brandBorder, lineWidth: 0.5))
        .padding(.trailing, Theme.Space.md)
        .padding(.bottom, 72)   // keep clear of the tab bar
    }

    private func zoomButton(system: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.headline)
                .foregroundStyle(Color.brandAccent)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func zoom(by factor: Double) {
        let lat = min(120, max(0.005, currentRegion.span.latitudeDelta * factor))
        let lon = min(120, max(0.005, currentRegion.span.longitudeDelta * factor))
        let region = MKCoordinateRegion(center: currentRegion.center,
                                        span: MKCoordinateSpan(latitudeDelta: lat, longitudeDelta: lon))
        currentRegion = region
        withAnimation(.easeInOut(duration: 0.25)) { camera = .region(region) }
    }

    private func selectionSheet(_ opp: Opportunity) -> some View {
        VStack(spacing: Theme.Space.sm) {
            OpportunityCard(opportunity: opp,
                            isSaved: saved.isSaved(opp.id),
                            onToggleSave: { saved.toggle(opp.id) })
            Button {
                selectedID = nil
                path.append(opp)
            } label: {
                Label("View details", systemImage: "chevron.right")
                    .frame(maxWidth: .infinity, minHeight: Theme.minTouchTarget)
            }
            .buttonStyle(.borderedProminent)
            .tint(.brandAccent)
        }
        .padding(Theme.Space.lg)
    }
}
