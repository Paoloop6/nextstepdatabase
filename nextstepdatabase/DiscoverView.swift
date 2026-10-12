//
//  DiscoverView.swift
//  nextstepdatabase
//
//  The landing tab: NextStep Database branding, a prominent entry into Browse,
//  category shortcuts derived from the real data, and a few real opportunity
//  cards. No invented recommendations or match scores.
//

import SwiftUI

struct DiscoverView: View {
    @Environment(OpportunityStore.self) private var store
    @Environment(SavedStore.self) private var saved
    @Environment(StudentVideoStore.self) private var videos
    @State private var selectedVideo: StudentVideo?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.xl) {
                    brandHeader
                    searchEntry
                    if store.source == .demo, case .loaded = store.state {
                        demoNotice
                    }
                    if store.source == .cache, let notice = store.cacheNotice {
                        cacheBanner(notice)
                    }
                    switch store.state {
                    case .idle, .loading:
                        StateView(kind: .loading, title: "Loading",
                                  message: "Fetching opportunities.", systemImage: "hourglass")
                            .padding(.top, Theme.Space.xxl)
                    case .failed(let message):
                        StateView(kind: .error, title: "Couldn’t load", message: message,
                                  systemImage: "exclamationmark.triangle", actionTitle: "Retry") {
                            Task { await store.load() }
                        }
                    case .loaded:
                        sourceStats
                        categoryShortcuts
                        studentStories
                        featured
                    }
                }
                .padding(Theme.Space.lg)
            }
            .refreshable { await store.refresh() }
            .background(Color.brandBackground)
            .navigationTitle("Discover")
            .navigationDestination(for: BrowseRoute.self) { route in
                BrowseView(initialCategory: route.category)
            }
            .navigationDestination(for: Opportunity.self) { opp in
                OpportunityDetailView(opportunity: opp)
            }
            .sheet(item: $selectedVideo) { StudentVideoPlayer(video: $0) }
            .task(id: videos.videos.count) {
                // Test hook: auto-open the first video's player for verification.
                if CommandLine.arguments.contains("-openFirstVideo"),
                   selectedVideo == nil, let first = videos.videos.first {
                    selectedVideo = first
                }
            }
        }
    }

    @ViewBuilder
    private var studentStories: some View {
        if !videos.videos.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                HStack {
                    Text("Student stories").font(.headline)
                    Spacer()
                    NavigationLink { StudentVideosView() } label: {
                        Text("See all").font(.subheadline)
                    }
                    .tint(.brandAccent)
                }
                Text("How students landed the activities that got them into college.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Space.md) {
                        ForEach(videos.videos.prefix(8)) { video in
                            Button { selectedVideo = video } label: { StudentVideoThumb(video: video) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Pieces

    private var brandHeader: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(spacing: Theme.Space.sm) {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                    .font(.title2)
                    .foregroundStyle(Color.brandAccent)
                Text("NextStep Database")
                    .font(.title.weight(.bold))
            }
            Text("Find real STEM internships, research, competitions, and scholarships — then save the ones you want to come back to.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var searchEntry: some View {
        NavigationLink(value: BrowseRoute(category: nil)) {
            HStack {
                Image(systemName: "magnifyingglass")
                Text("Search opportunities")
                Spacer()
            }
            .font(.body)
            .foregroundStyle(.secondary)
            .padding(.horizontal, Theme.Space.lg)
            .frame(minHeight: Theme.minTouchTarget + 4)
            .background(Color.brandSurface, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .strokeBorder(Color.brandBorder, lineWidth: 0.5))
        }
        .accessibilityLabel("Search opportunities")
    }

    private var demoNotice: some View {
        Label("Showing demo data — the live database couldn’t be reached.",
              systemImage: "wifi.exclamationmark")
            .font(.footnote.weight(.medium))
            .foregroundStyle(Color.statusWarning)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Space.md)
            .background(Color.statusWarning.opacity(0.12),
                       in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
    }

    private func cacheBanner(_ notice: String) -> some View {
        Label(notice, systemImage: "clock.arrow.circlepath")
            .font(.footnote.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Space.md)
            .background(Color.brandChip,
                       in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
    }

    /// At-a-glance counts of how much real data backs the app. Only shown for
    /// live data; the demo notice covers the fallback case.
    private var sourceStats: some View {
        HStack(spacing: Theme.Space.md) {
            stat("\(store.all.count.formatted())", "Opportunities", "tray.full")
            Divider().frame(height: 32)
            stat("\(store.organizationCount)", "Organizations", "building.2")
            Divider().frame(height: 32)
            stat("\(store.sourceWebsiteCount)", "Sources", "link")
        }
        .frame(maxWidth: .infinity)
        .cardSurface()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(store.all.count) opportunities from \(store.organizationCount) organizations across \(store.sourceWebsiteCount) source websites")
    }

    private func stat(_ value: String, _ label: String, _ icon: String) -> some View {
        VStack(spacing: Theme.Space.xs) {
            Label(value, systemImage: icon)
                .labelStyle(.titleOnly)
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.brandAccent)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var categoryShortcuts: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            Text("Browse by category")
                .font(.headline)
            FlowLayout {
                ForEach(store.availableCategories, id: \.self) { category in
                    NavigationLink(value: BrowseRoute(category: category)) {
                        Badge(text: category, systemImage: iconForCategory(category), tint: .brandAccent)
                            .font(.subheadline)
                    }
                    .accessibilityLabel("Browse \(category)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var featured: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            Text("Recently added")
                .font(.headline)
            ForEach(Array(store.all.prefix(5))) { opp in
                NavigationLink(value: opp) {
                    OpportunityCard(opportunity: opp,
                                    isSaved: saved.isSaved(opp.id),
                                    onToggleSave: { saved.toggle(opp.id) })
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func iconForCategory(_ category: String) -> String {
        switch category {
        case "Scholarships": return "graduationcap"
        case "Internships": return "briefcase"
        case "Research": return "flask"
        case "Competitions": return "trophy"
        case "Mentorship": return "person.2"
        case "Volunteering": return "hands.sparkles"
        case "Summer Programs": return "sun.max"
        default: return "square.grid.2x2"
        }
    }
}

/// Value used to push Browse with an optional preselected category.
struct BrowseRoute: Hashable {
    let category: String?
}
