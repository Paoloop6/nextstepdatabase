//
//  SavedView.swift
//  nextstepdatabase
//
//  Shows opportunities the user saved, resolved from the loaded set. Save state
//  is shared with every other screen and persists across relaunch. Includes a
//  helpful empty state that routes back to Browse.
//

import SwiftUI

struct SavedView: View {
    @Environment(OpportunityStore.self) private var store
    @Environment(SavedStore.self) private var saved
    @Binding var selectedTab: RootTab

    private var items: [Opportunity] { saved.savedItems(from: store.all) }

    var body: some View {
        NavigationStack {
            Group {
                if saved.savedIDs.isEmpty {
                    StateView(kind: .empty, title: "No saved opportunities",
                              message: "Save opportunities you’re interested in and they’ll appear here — even after you restart the app.",
                              systemImage: "bookmark",
                              actionTitle: "Browse opportunities") {
                        selectedTab = .browse
                    }
                } else if items.isEmpty {
                    // Saved IDs exist but the source list isn't loaded yet.
                    StateView(kind: .loading, title: "Loading saved",
                              message: "Restoring your saved opportunities.", systemImage: "hourglass")
                } else {
                    ScrollView {
                        LazyVStack(spacing: Theme.Space.md) {
                            ForEach(items) { opp in
                                NavigationLink(value: opp) {
                                    OpportunityCard(opportunity: opp,
                                                    isSaved: true,
                                                    onToggleSave: { saved.toggle(opp.id) })
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(Theme.Space.lg)
                    }
                }
            }
            .navigationTitle("Saved")
            .background(Color.brandBackground)
            .navigationDestination(for: Opportunity.self) { opp in
                OpportunityDetailView(opportunity: opp)
            }
        }
    }
}
