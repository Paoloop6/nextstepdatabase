//
//  MatchView.swift
//  nextstepdatabase
//
//  Student-profile form → DeepSeek-analyzed matches via /api/ask-stempath (the
//  same endpoint the website uses). Shows DeepSeek's summary + a reason for each
//  match. The feedback survey is offered only after the results are closed.
//

import SwiftUI

struct MatchView: View {
    @State private var store = MatchStore()
    @Environment(SurveyStore.self) private var survey
    @Environment(OpportunityStore.self) private var opportunities
    @State private var showSurvey = false
    /// Queued when a match completes and the survey is due; shown only after the
    /// user closes the results, so it never interrupts them.
    @State private var surveyPending = false

    private let stemOptions = ["Any", "Computer Science", "Engineering", "Biology", "Chemistry",
                               "Physics", "Mathematics", "Medicine", "Environmental Science"]
    private let typeOptions = ["Any", "Internship", "Research", "Competition", "Scholarship",
                               "Summer Program", "Mentorship", "Volunteering"]
    private let formatOptions = ["Any", "remote", "in-person", "hybrid"]
    private let costOptions = ["Any", "free", "low", "medium", "high"]
    private let experienceOptions = ["any", "beginner", "intermediate", "advanced"]
    private let timeOptions = ["Any", "days", "weeks", "months", "summer", "year"]

    var body: some View {
        NavigationStack {
            Group {
                switch store.state {
                case .idle:
                    form
                case .loading:
                    StateView(kind: .loading, title: "Analyzing with AI",
                              message: "DeepSeek is reviewing opportunities against your profile — this can take a moment.",
                              systemImage: "sparkles")
                case .failed(let message):
                    StateView(kind: .error, title: "Couldn’t get matches", message: message,
                              systemImage: "exclamationmark.triangle", actionTitle: "Try again") {
                        Task { await runMatch() }
                    }
                    .safeAreaInset(edge: .bottom) { editProfileBar }
                case .loaded(let response):
                    response.matches.isEmpty
                        ? AnyView(StateView(kind: .empty, title: "No matches",
                                    message: response.answer.isEmpty
                                        ? "DeepSeek didn’t find opportunities for this profile. Try broadening your preferences."
                                        : response.answer,
                                    systemImage: "magnifyingglass",
                                    actionTitle: "Edit profile") { closeResults() })
                        : AnyView(resultsList(response))
                }
            }
            .navigationTitle("Match")
            .background(Color.brandBackground)
            .navigationDestination(for: AskMatch.self) { AskMatchDetailView(match: $0) }
            .sheet(isPresented: $showSurvey) { SurveyView() }
        }
    }

    /// Runs a DeepSeek match. On success, queues the survey (shown after close).
    private func runMatch() async {
        await store.submit(candidates: opportunities.all)
        if case .loaded = store.state, survey.matchCompleted() {
            surveyPending = true
        }
    }

    /// Closes results back to the form, then presents the queued survey (if due).
    private func closeResults() {
        store.state = .idle
        if surveyPending {
            surveyPending = false
            survey.recordPrompted()
            showSurvey = true
        }
    }

    // MARK: Form

    private var form: some View {
        Form {
            Section {
                Text("Tell us about yourself and DeepSeek will analyze real opportunities for fit. Nothing here is stored on a server.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Section("You") {
                Picker("Grade", selection: $store.profile.grade) {
                    ForEach(6...12, id: \.self) { Text("Grade \($0)").tag($0) }
                }
                Stepper("Age: \(store.profile.age)", value: $store.profile.age, in: 10...25)
                    .accessibilityLabel("Age \(store.profile.age)")
            }
            Section("Interests") {
                picker("STEM interest", selection: $store.profile.stemInterest, options: stemOptions)
                picker("Opportunity type", selection: $store.profile.opportunityType, options: typeOptions)
            }
            Section("Preferences") {
                picker("Format", selection: $store.profile.formatPreference, options: formatOptions)
                picker("Cost", selection: $store.profile.costPreference, options: costOptions)
                picker("Experience level", selection: $store.profile.experienceLevel, options: experienceOptions)
                picker("Time commitment", selection: $store.profile.timeCommitment, options: timeOptions)
                HStack {
                    Text("Location")
                    Spacer()
                    TextField("Any", text: $store.profile.locationPreference)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Picker("Search depth", selection: $store.profile.tier) {
                    Text("Standard").tag("standard")
                    Text("Pro").tag("pro")
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Search depth")
            } footer: {
                Text(store.profile.tier == "pro"
                     ? "Pro asks DeepSeek for a deeper analysis. It may take longer."
                     : "Standard runs a fast DeepSeek analysis.")
            }
            Section {
                Button {
                    Task { await runMatch() }
                } label: {
                    Text("Find matches")
                        .frame(maxWidth: .infinity, minHeight: Theme.minTouchTarget)
                }
                .buttonStyle(.borderedProminent)
                .tint(.brandAccent)
                .listRowInsets(EdgeInsets())
            }
        }
    }

    private func picker(_ title: String, selection: Binding<String>, options: [String]) -> some View {
        Picker(title, selection: selection) {
            ForEach(options, id: \.self) { Text($0.capitalized).tag($0) }
        }
    }

    // MARK: Results

    private func resultsList(_ response: AskStempathResponse) -> some View {
        ScrollView {
            LazyVStack(spacing: Theme.Space.md) {
                if store.isRefining {
                    HStack(spacing: Theme.Space.sm) {
                        ProgressView().controlSize(.small)
                        Text("Quick matches — refining with AI…")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.Space.md)
                    .background(Color.brandChip, in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
                }
                if !response.answer.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Space.sm) {
                        Label("DeepSeek summary", systemImage: "sparkles")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.brandAccent)
                        Text(response.answer)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardSurface()
                }

                HStack {
                    Text("^[\(response.matches.count) match](inflect: true)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Badge(text: store.profile.tier.capitalized,
                          systemImage: "sparkles", tint: .brandAccent)
                }

                ForEach(response.matches) { match in
                    NavigationLink(value: match) { MatchCard(match: match) }
                        .buttonStyle(.plain)
                }
            }
            .padding(Theme.Space.lg)
        }
        .safeAreaInset(edge: .bottom) { editProfileBar }
    }

    private var editProfileBar: some View {
        Button {
            closeResults()
        } label: {
            Label("Edit profile & search again", systemImage: "slider.horizontal.3")
                .frame(maxWidth: .infinity, minHeight: Theme.minTouchTarget)
        }
        .buttonStyle(.bordered)
        .tint(.brandAccent)
        .padding(Theme.Space.md)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Match card

private struct MatchCard: View {
    let match: AskMatch

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(match.title).font(.headline)
                Text(match.organization)
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if let warning = match.eligibilityWarning, !warning.isEmpty {
                Badge(text: warning, systemImage: "exclamationmark.circle", tint: .statusWarning)
            }
            if !match.matchReason.isEmpty {
                Label(match.matchReason, systemImage: "sparkles")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .cardSurface()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(match.title), \(match.organization)")
    }
}

// MARK: - Match detail

struct AskMatchDetailView: View {
    let match: AskMatch
    @Environment(\.openURL) private var openURL
    @State private var linkError = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(match.title).font(.title2.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(match.organization).font(.headline).foregroundStyle(.secondary)
                }

                if let status = match.applicationStatus, !status.isEmpty {
                    Label(status, systemImage: "info.circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                if !match.matchReason.isEmpty {
                    block("Why DeepSeek matched this", systemImage: "sparkles", text: match.matchReason)
                }
                if let warning = match.eligibilityWarning, !warning.isEmpty {
                    block("Eligibility to check", systemImage: "exclamationmark.triangle", text: warning)
                }

                detailRows

                OpportunityLocationMap(rawLocation: match.location, title: match.title)

                Button {
                    if let url = match.sourceURL {
                        openURL(url)
                    } else { linkError = true }
                } label: {
                    Label("View original opportunity", systemImage: "safari")
                        .frame(maxWidth: .infinity, minHeight: Theme.minTouchTarget)
                }
                .buttonStyle(.borderedProminent)
                .tint(.brandAccent)
                .disabled(match.sourceURL == nil)
            }
            .padding(Theme.Space.lg)
        }
        .background(Color.brandBackground)
        .navigationTitle("Match detail")
        .inlineNavTitle()
        .alert("Couldn’t open link", isPresented: $linkError) {
            Button("OK", role: .cancel) {}
        } message: { Text("The source link for this opportunity is missing or invalid.") }
    }

    private var detailRows: some View {
        let rows: [(String, String, String)] = [
            ("Type", "square.grid.2x2", match.opportunityType ?? "Not specified"),
            ("Cost", "tag", match.cost ?? "Not specified"),
            ("Deadline", "calendar", match.deadline ?? "Not specified"),
            ("Grades", "graduationcap", match.eligibleGrades.isEmpty ? "Not specified" : match.eligibleGrades.joined(separator: ", "))
        ]
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(alignment: .top, spacing: Theme.Space.md) {
                    Label(row.0, systemImage: row.1)
                        .font(.subheadline).foregroundStyle(.secondary)
                        .frame(width: 110, alignment: .leading)
                    Text(row.2)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(row.2 == "Not specified" ? .tertiary : .primary)
                }
                .padding(.vertical, Theme.Space.sm)
                if index < rows.count - 1 { Divider() }
            }
        }
        .cardSurface()
    }

    private func block(_ title: String, systemImage: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            Text(text).font(.body).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}
