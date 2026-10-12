//
//  StudentVideosView.swift
//  nextstepdatabase
//
//  "Student stories" — a browsable list of student college-journey videos with
//  in-app embedded playback (YouTube privacy-enhanced player).
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Student story detail (thumbnail + watch button, opens YouTube)

struct StudentVideoPlayer: View {
    let video: StudentVideo
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    // Thumbnail (tap to watch) — no in-app player, so no
                    // black box / embed errors; watching opens YouTube.
                    Button { openVideo() } label: {
                        ZStack {
                            AsyncImage(url: video.thumbnail) { phase in
                                if case .success(let img) = phase { img.resizable().aspectRatio(contentMode: .fill) }
                                else { Color.brandChip }
                            }
                            .frame(maxWidth: .infinity).frame(height: 200).clipped()
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 58)).foregroundStyle(.white.opacity(0.95)).shadow(radius: 6)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Watch \(video.title) on YouTube")

                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Text(video.title).font(.headline).fixedSize(horizontal: false, vertical: true)
                        Text(video.channelTitle).font(.subheadline).foregroundStyle(.secondary)
                    }

                    Button { openVideo() } label: {
                        Label("Watch on YouTube", systemImage: "play.rectangle.fill")
                            .frame(maxWidth: .infinity, minHeight: Theme.minTouchTarget)
                    }
                    .buttonStyle(.borderedProminent).tint(.brandAccent)

                    pathwayHeader
                    stemActivitiesSection
                }
                .padding(Theme.Space.lg)
            }
            .background(Color.brandBackground)
            .navigationTitle("STEM pathway")
            .inlineNavTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    /// Opens the YouTube app if installed, else the browser.
    private func openVideo() {
        #if canImport(UIKit)
        if let appURL = URL(string: "youtube://watch?v=\(video.videoId)"),
           UIApplication.shared.canOpenURL(appURL) {
            openURL(appURL)
            return
        }
        #endif
        if let web = video.watchURL { openURL(web) }
    }

    @ViewBuilder
    private var pathwayHeader: some View {
        if video.committedSchool != nil || !video.acceptedSchools.isEmpty || !video.intendedMajors.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                if let school = video.committedSchool {
                    row("Committed", "graduationcap", school)
                } else if !video.acceptedSchools.isEmpty {
                    row("Accepted", "graduationcap", video.acceptedSchools.joined(separator: ", "))
                }
                if !video.intendedMajors.isEmpty {
                    row("Intended major", "book", video.intendedMajors.joined(separator: ", "))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
    }

    private func row(_ label: String, _ icon: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.md) {
            Label(label, systemImage: icon)
                .font(.subheadline).foregroundStyle(.secondary)
                .frame(width: 130, alignment: .leading)
            Text(value).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var stemActivitiesSection: some View {
        let acts = video.stemActivities
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            Text("STEM extracurriculars").font(.headline)
            if acts.isEmpty {
                Text("No STEM activities were identified for this student.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(Array(acts.enumerated()), id: \.element.id) { index, activity in
                    HStack(alignment: .top, spacing: Theme.Space.sm) {
                        Text("\(index + 1)")
                            .font(.subheadline.weight(.bold)).foregroundStyle(Color.brandAccent)
                            .frame(width: 22, alignment: .leading)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(activityTitle(activity)).font(.subheadline.weight(.semibold))
                                .fixedSize(horizontal: false, vertical: true)
                            if !activity.details.isEmpty {
                                Text(activity.details).font(.footnote).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Badge(text: activity.category, systemImage: "atom")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardSurface(padding: Theme.Space.md)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func activityTitle(_ a: StoryActivity) -> String {
        var t = a.title
        if let role = a.role, !role.isEmpty { t += " — \(role)" }
        if let org = a.organization, !org.isEmpty { t += " @ \(org)" }
        return t
    }
}

// MARK: - List

struct StudentVideosView: View {
    @Environment(StudentVideoStore.self) private var store
    @State private var selected: StudentVideo?
    @State private var search = ""

    private func filtered(_ videos: [StudentVideo]) -> [StudentVideo] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return videos }
        return videos.filter { $0.collegeSearchText.contains(q) }
    }

    var body: some View {
        Group {
            switch store.state {
            case .idle, .loading:
                StateView(kind: .loading, title: "Loading stories",
                          message: "Finding student journeys.", systemImage: "play.rectangle")
            case .failed(let message):
                StateView(kind: .error, title: "Couldn’t load", message: message,
                          systemImage: "exclamationmark.triangle", actionTitle: "Retry") {
                    Task { await store.load() }
                }
            case .loaded(let videos):
                let results = filtered(videos)
                if videos.isEmpty {
                    StateView(kind: .empty, title: "No stories yet",
                              message: "Student story videos will appear here.", systemImage: "play.rectangle")
                } else {
                    ScrollView {
                        LazyVStack(spacing: Theme.Space.md) {
                            if store.usingSample {
                                Label("Curated sample videos — live feed connects when the backend is deployed.",
                                      systemImage: "info.circle")
                                    .font(.footnote).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(Theme.Space.md)
                                    .background(Color.brandChip, in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
                            }
                            Text("^[\(results.count) story](inflect: true)")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if results.isEmpty {
                                StateView(kind: .empty, title: "No matches",
                                          message: "No student went to a college matching “\(search)”. Try another name.",
                                          systemImage: "magnifyingglass")
                                    .padding(.top, Theme.Space.lg)
                            } else {
                                ForEach(results) { video in
                                    Button { selected = video } label: { StudentVideoCard(video: video) }
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(Theme.Space.lg)
                    }
                }
            }
        }
        .navigationTitle("Student stories")
        .background(Color.brandBackground)
        .searchable(text: $search,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search by college (e.g. MIT, Brown)")
        .sheet(item: $selected) { StudentVideoPlayer(video: $0) }
        .task { await store.load() }
    }
}

// MARK: - Compact thumbnail (Discover carousel)

struct StudentVideoThumb: View {
    let video: StudentVideo

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            ZStack {
                AsyncImage(url: video.thumbnail) { phase in
                    if case .success(let img) = phase { img.resizable().aspectRatio(contentMode: .fill) }
                    else { Color.brandChip }
                }
                .frame(width: 240, height: 135)
                .clipped()
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 34)).foregroundStyle(.white.opacity(0.92)).shadow(radius: 3)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
            Text(video.title).font(.caption.weight(.semibold)).foregroundStyle(.primary)
                .lineLimit(2).frame(width: 240, alignment: .leading)
            Text(video.channelTitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(width: 240)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Play \(video.title)")
    }
}

// MARK: - Card

struct StudentVideoCard: View {
    let video: StudentVideo

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            ZStack(alignment: .center) {
                AsyncImage(url: video.thumbnail) { phase in
                    switch phase {
                    case .success(let img): img.resizable().aspectRatio(contentMode: .fill)
                    default: Color.brandChip
                    }
                }
                .frame(height: 180)
                .frame(maxWidth: .infinity)
                .clipped()
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 46))
                    .foregroundStyle(.white.opacity(0.92))
                    .shadow(radius: 4)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))

            Text(video.title).font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary).lineLimit(2)
            Text(video.channelTitle).font(.caption).foregroundStyle(.secondary)
            if let school = video.displaySchool {
                Badge(text: school, systemImage: "graduationcap", tint: .brandAccent)
            }
            if !video.activities.isEmpty {
                FlowLayout { ForEach(video.activities.prefix(3), id: \.self) { Badge(text: $0) } }
            }
        }
        .cardSurface()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Play \(video.title) by \(video.channelTitle)")
    }
}
