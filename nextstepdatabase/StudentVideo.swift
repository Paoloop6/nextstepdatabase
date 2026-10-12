//
//  StudentVideo.swift
//  nextstepdatabase
//
//  "Student stories" — public YouTube videos where students explain the
//  activities that helped them get into college. Data comes from the backend's
//  /api/student-videos endpoint when available; otherwise a curated set bundled
//  in the app is used (these are public videos, embedded via YouTube's player).
//

import Foundation
import SwiftUI

/// One extracurricular from a student's pathway.
struct StoryActivity: Decodable, Hashable, Identifiable {
    let title: String
    let role: String?
    let organization: String?
    let details: String
    let category: String
    var id: String { title + "|" + category }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        role = try? c.decodeIfPresent(String.self, forKey: .role)
        organization = try? c.decodeIfPresent(String.self, forKey: .organization)
        details = (try? c.decodeIfPresent(String.self, forKey: .details)) ?? ""
        category = (try? c.decodeIfPresent(String.self, forKey: .category)) ?? "Other"
    }
    enum CodingKeys: String, CodingKey { case title, role, organization, details, category }

    /// Clearly-STEM categories.
    private static let stemCategories: Set<String> = [
        "Research", "Coding / software", "Robotics / engineering", "Competition / olympiad"
    ]
    private static let stemKeywords = [
        "research", "engineer", "robot", "coding", "software", "computer", "data",
        "math", "physics", "chemistry", "biolog", "science", "lab", "stem", " ai ",
        "machine learning", "programming", "app development", "web dev", "hackathon", "olympiad"
    ]
    /// STEM if the category is clearly STEM, or the text is STEM (covers STEM
    /// internships / summer programs / coursework without pulling in non-STEM).
    var isSTEM: Bool {
        if Self.stemCategories.contains(category) { return true }
        let hay = " \(title) \(details) \(organization ?? "") ".lowercased()
        return Self.stemKeywords.contains { hay.contains($0) }
    }
}

struct StudentVideo: Decodable, Identifiable, Hashable {
    let videoId: String
    let title: String
    let channelTitle: String
    let activities: [String]
    let thumbnailUrl: String?
    // Pathway fields (used for the ECDatabase-style STEM listing). We decode
    // schools / major / activities, but deliberately NOT GPA/SAT/hometown —
    // many of these students are minors.
    let studentName: String?
    let committedSchool: String?
    let acceptedSchools: [String]
    let intendedMajors: [String]
    let detailedActivities: [StoryActivity]

    var id: String { videoId }
    /// STEM-only activities, in listing order.
    var stemActivities: [StoryActivity] { detailedActivities.filter(\.isSTEM) }

    /// The school to show on the card (committed first, else first accepted).
    var displaySchool: String? { committedSchool ?? acceptedSchools.first }

    /// Lowercased haystack for college search (schools + title, since many
    /// titles are like "How I got into MIT").
    var collegeSearchText: String {
        (([committedSchool] + acceptedSchools).compactMap { $0 } + [title])
            .joined(separator: " ").lowercased()
    }

    enum CodingKeys: String, CodingKey {
        case videoId, title, channelTitle, activities, thumbnailUrl, story
    }
    private struct Story: Decodable {
        let studentName: String?
        let committedSchool: String?
        let acceptedSchools: [String]?
        let intendedMajors: [String]?
        let activities: [StoryActivity]?
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        videoId = (try? c.decode(String.self, forKey: .videoId)) ?? ""
        title = (try? c.decode(String.self, forKey: .title)) ?? "Untitled"
        channelTitle = (try? c.decodeIfPresent(String.self, forKey: .channelTitle)) ?? ""
        activities = (try? c.decodeIfPresent([String].self, forKey: .activities)) ?? []
        thumbnailUrl = try? c.decodeIfPresent(String.self, forKey: .thumbnailUrl)
        let story = try? c.decodeIfPresent(Story.self, forKey: .story)
        studentName = story?.studentName
        committedSchool = story?.committedSchool
        acceptedSchools = story?.acceptedSchools ?? []
        intendedMajors = story?.intendedMajors ?? []
        detailedActivities = story?.activities ?? []
    }

    /// High-quality thumbnail (falls back to the standard YouTube thumbnail URL).
    var thumbnail: URL? {
        URL(string: thumbnailUrl ?? "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg")
    }
    /// Privacy-friendly embed URL for in-app playback.
    var embedURL: URL? {
        URL(string: "https://www.youtube-nocookie.com/embed/\(videoId)?playsinline=1&rel=0&modestbranding=1")
    }
    var watchURL: URL? { URL(string: "https://www.youtube.com/watch?v=\(videoId)") }
}

private struct StudentVideoEnvelope: Decodable { let videos: [StudentVideo] }

struct StudentVideoService: Sendable {
    static let endpoint = URL(string: "https://www.nextstepdatabase.fyi/api/student-videos")!

    func fetch() async throws -> [StudentVideo] {
        var request = URLRequest(url: Self.endpoint)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw OpportunityServiceError.badStatus(http.statusCode)
        }
        if let env = try? JSONDecoder().decode(StudentVideoEnvelope.self, from: data) { return env.videos }
        return (try? JSONDecoder().decode([StudentVideo].self, from: data)) ?? []
    }

    /// Curated public videos shipped in the app (used until the API is live).
    static func bundled() -> [StudentVideo] {
        guard let url = Bundle.main.url(forResource: "sample-student-videos", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let videos = try? JSONDecoder().decode([StudentVideo].self, from: data) else { return [] }
        return videos
    }
}

@MainActor
@Observable
final class StudentVideoStore {
    var state: LoadState<[StudentVideo]> = .idle
    /// True when showing the bundled curated set because the API returned nothing.
    private(set) var usingSample = false

    var videos: [StudentVideo] {
        if case .loaded(let v) = state { return v }
        return []
    }

    private let service = StudentVideoService()

    func load() async {
        if case .loaded = state { return }
        state = .loading
        do {
            let live = try await service.fetch()
            if live.isEmpty {
                usingSample = true
                state = .loaded(StudentVideoService.bundled())
                AppLog.net("student-videos empty — using curated sample")
            } else {
                usingSample = false
                state = .loaded(live)
            }
        } catch {
            usingSample = true
            state = .loaded(StudentVideoService.bundled())
            AppLog.net("student-videos fetch failed (\(error.localizedDescription)) — using curated sample")
        }
    }
}
