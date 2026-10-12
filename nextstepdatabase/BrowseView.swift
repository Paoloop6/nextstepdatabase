//
//  BrowseView.swift
//  nextstepdatabase
//
//  The core browsing surface: search by title / organization / description,
//  a filter sheet with Apply + Reset, a live result count, and a clear way to
//  reset everything. Query, filters, and scroll position are preserved when
//  returning from a detail screen because this view stays alive during push.
//

import SwiftUI

struct BrowseView: View {
    @Environment(OpportunityStore.self) private var store
    @Environment(SavedStore.self) private var saved

    @State private var search = ""
    @State private var filters = OpportunityFilters()
    @State private var showFilters = false
    /// Filtered results, recomputed off the main thread and published back here.
    @State private var results: [Opportunity] = []
    /// False until the first filter pass finishes, so we don't flash "No matches".
    @State private var didCompute = false
    /// Initial category preselection routed in from Discover.
    var initialCategory: String?

    /// Change-key that drives debounced recomputation: search text, active
    /// filters, and a signal that the underlying data set changed.
    private struct FilterKey: Equatable {
        var search: String
        var filters: OpportunityFilters
        var dataCount: Int
    }
    private var filterKey: FilterKey {
        FilterKey(search: search, filters: filters, dataCount: store.all.count)
    }

    var body: some View {
        Group {
            switch store.state {
            case .idle, .loading:
                StateView(kind: .loading, title: "Loading opportunities",
                          message: "Fetching the latest listings.", systemImage: "hourglass")
            case .failed(let message):
                StateView(kind: .error, title: "Something went wrong", message: message,
                          systemImage: "exclamationmark.triangle", actionTitle: "Retry") {
                    Task { await store.load() }
                }
            case .loaded:
                content
            }
        }
        .task(id: filterKey) { await recompute() }
        .navigationTitle("Browse")
        .background(Color.brandBackground)
        .searchable(text: $search, prompt: "Search title, organization, description")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showFilters = true
                } label: {
                    Label("Filters", systemImage: filters.isEmpty
                          ? "line.3.horizontal.decrease.circle"
                          : "line.3.horizontal.decrease.circle.fill")
                }
                .accessibilityLabel(filters.isEmpty ? "Filters" : "Filters, \(filters.activeCount) active")
            }
        }
        .sheet(isPresented: $showFilters) {
            FilterSheet(filters: $filters,
                        categories: store.availableCategories,
                        grades: store.availableGrades,
                        formats: store.availableFormats,
                        costs: store.availableCosts)
                .mediumLargeDetents()
        }
        .navigationDestination(for: Opportunity.self) { opp in
            OpportunityDetailView(opportunity: opp)
        }
        .onAppear {
            if let initialCategory, filters.categories.isEmpty {
                filters.categories = [initialCategory]
            }
        }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Space.md) {
                resultsHeader
                if !didCompute {
                    ProgressView()
                        .padding(.top, Theme.Space.xl)
                } else if results.isEmpty {
                    StateView(kind: .empty, title: "No matches",
                              message: "No opportunities match your search and filters.",
                              systemImage: "magnifyingglass",
                              actionTitle: "Reset search & filters", action: resetAll)
                        .padding(.top, Theme.Space.xl)
                } else {
                    ForEach(results) { opp in
                        NavigationLink(value: opp) {
                            OpportunityCard(opportunity: opp,
                                            isSaved: saved.isSaved(opp.id),
                                            onToggleSave: { saved.toggle(opp.id) })
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(Theme.Space.lg)
        }
        .refreshable { await store.refresh() }
    }

    private var resultsHeader: some View {
        HStack {
            Text("\(results.count.formatted()) \(results.count == 1 ? "opportunity" : "opportunities")")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if !search.isEmpty || !filters.isEmpty {
                Button("Reset", action: resetAll)
                    .font(.subheadline)
                    .tint(.brandAccent)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(results.count) results")
    }

    /// Debounces ~250 ms, then filters off the main thread and publishes back.
    /// `.task(id:)` cancels the in-flight pass whenever the key changes, so a
    /// newer keystroke's result can never be overwritten by an older one.
    private func recompute() async {
        do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
        let snapshot = store.all
        let currentSearch = search
        let currentFilters = filters
        let filtered = await Task.detached(priority: .userInitiated) {
            OpportunityQuery.apply(snapshot, search: currentSearch, filters: currentFilters)
        }.value
        results = filtered
        didCompute = true
    }

    private func resetAll() {
        search = ""
        filters = OpportunityFilters()
    }
}

// MARK: - Filter sheet

struct FilterSheet: View {
    @Binding var filters: OpportunityFilters
    let categories: [String]
    let grades: [String]
    let formats: [String]
    let costs: [String]

    @Environment(\.dismiss) private var dismiss
    /// Working copy so Apply commits and Reset/cancel discards.
    @State private var working = OpportunityFilters()

    var body: some View {
        NavigationStack {
            Form {
                facet("Category", options: categories, keyPath: \.categories)
                facet("Grade eligibility", options: grades, keyPath: \.grades)
                facet("Format", options: formats, keyPath: \.formats)
                facet("Cost", options: costs, keyPath: \.costs)
            }
            .navigationTitle("Filters")
            .inlineNavTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") { working = OpportunityFilters() }
                        .disabled(working.isEmpty)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Apply") {
                        filters = working
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear { working = filters }
        }
    }

    @ViewBuilder
    private func facet(_ title: String, options: [String],
                       keyPath: WritableKeyPath<OpportunityFilters, Set<String>>) -> some View {
        if !options.isEmpty {
            Section(title) {
                ForEach(options, id: \.self) { option in
                    let isOn = working[keyPath: keyPath].contains(option)
                    Button {
                        if isOn { working[keyPath: keyPath].remove(option) }
                        else { working[keyPath: keyPath].insert(option) }
                    } label: {
                        HStack {
                            Text(option).foregroundStyle(.primary)
                            Spacer()
                            if isOn {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.brandAccent)
                                    .fontWeight(.semibold)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
        }
    }
}
