//
//  RootView.swift
//  nextstepdatabase
//
//  Compact three-tab structure — Discover, Browse, Saved — with shared stores
//  injected into the environment so save state stays synchronized everywhere.
//

import SwiftUI

enum RootTab: Hashable { case discover, browse, match, map, saved }

struct RootView: View {
    @State private var store = OpportunityStore()
    @State private var saved = SavedStore()
    @State private var survey = SurveyStore()
    @State private var studentVideos = StudentVideoStore()
    @State private var selectedTab: RootTab

    init() {
        // Launch-argument hooks used only for deterministic UI verification;
        // absent in normal use, they leave default behavior untouched.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "-startTab"), i + 1 < args.count {
            switch args[i + 1] {
            case "browse": _selectedTab = State(initialValue: .browse)
            case "match": _selectedTab = State(initialValue: .match)
            case "map": _selectedTab = State(initialValue: .map)
            case "saved": _selectedTab = State(initialValue: .saved)
            default: _selectedTab = State(initialValue: .discover)
            }
        } else {
            _selectedTab = State(initialValue: .discover)
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            DiscoverView()
                .tabItem { Label("Discover", systemImage: "house") }
                .tag(RootTab.discover)

            NavigationStack {
                BrowseView()
            }
            .tabItem { Label("Browse", systemImage: "square.grid.2x2") }
            .tag(RootTab.browse)

            MatchView()
                .tabItem { Label("Match", systemImage: "sparkles") }
                .tag(RootTab.match)

            GlobalMapView()
                .tabItem { Label("Map", systemImage: "globe.americas") }
                .tag(RootTab.map)

            SavedView(selectedTab: $selectedTab)
                .tabItem { Label("Saved", systemImage: "bookmark") }
                .tag(RootTab.saved)
        }
        .tint(.brandAccent)
        .environment(store)
        .environment(saved)
        .environment(survey)
        .environment(studentVideos)
        .task { await studentVideos.load() }
        .task {
            let args = CommandLine.arguments
            if let i = args.firstIndex(of: "-seedSaved"), i + 1 < args.count, !saved.isSaved(args[i + 1]) {
                saved.toggle(args[i + 1])
            }
            if case .idle = store.state { await store.load() }
        }
    }
}

#Preview {
    RootView()
}
