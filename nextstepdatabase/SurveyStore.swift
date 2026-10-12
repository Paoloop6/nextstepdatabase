//
//  SurveyStore.swift
//  nextstepdatabase
//
//  Decides when to show the feedback survey:
//   • First offered after the user's first completed match.
//   • If they submit it, it's never shown again (once).
//   • If they ignore/dismiss it, it re-appears at most once every 7 days
//     (on a subsequent match completion).
//
//  Responses are stored locally only — nothing is sent to a server (there is no
//  survey endpoint), so no user data leaves the device.
//

import Foundation
import SwiftUI

/// One stored review — kept locally on device.
struct Review: Codable, Identifiable, Hashable {
    var id = UUID()
    let rating: Int
    let comment: String
    let at: Double   // seconds since 1970

    var date: Date { Date(timeIntervalSince1970: at) }
}

@MainActor
@Observable
final class SurveyStore {
    private enum Key {
        static let completed = "survey_completed"
        static let firstMatch = "survey_firstMatchCompleted"
        static let lastPrompted = "survey_lastPromptedAt"
        static let rating = "survey_rating"
    }
    static let repromptInterval: TimeInterval = 7 * 24 * 60 * 60   // 1 week

    private let defaults: UserDefaults
    private let now: () -> Date
    /// Where submitted reviews are persisted (local JSON, no server).
    private let reviewsURL: URL

    private(set) var completed: Bool
    private(set) var firstMatchCompleted: Bool
    private(set) var lastPromptedAt: Date?
    /// All reviews the user has submitted, most recent last.
    private(set) var reviews: [Review] = []

    init(defaults: UserDefaults = .standard,
         now: @escaping () -> Date = { Date() },
         reviewsURL: URL? = nil) {
        self.defaults = defaults
        self.now = now
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.reviewsURL = reviewsURL ?? dir.appendingPathComponent("reviews.json")
        completed = defaults.bool(forKey: Key.completed)
        firstMatchCompleted = defaults.bool(forKey: Key.firstMatch)
        let t = defaults.double(forKey: Key.lastPrompted)
        lastPromptedAt = t > 0 ? Date(timeIntervalSince1970: t) : nil
        if let data = try? Data(contentsOf: self.reviewsURL),
           let decoded = try? JSONDecoder().decode([Review].self, from: data) {
            reviews = decoded
        }
    }

    /// True when the survey is due: taken never, first match done, and either
    /// never prompted or the weekly interval has elapsed since the last prompt.
    var shouldPrompt: Bool {
        guard !completed, firstMatchCompleted else { return false }
        guard let last = lastPromptedAt else { return true }
        return now().timeIntervalSince(last) >= Self.repromptInterval
    }

    /// Call when a match completes. Records the first-match milestone and returns
    /// whether the survey should be presented now.
    func matchCompleted() -> Bool {
        if !firstMatchCompleted {
            firstMatchCompleted = true
            defaults.set(true, forKey: Key.firstMatch)
        }
        return shouldPrompt
    }

    /// Call when the survey is actually shown, so the weekly clock restarts.
    func recordPrompted() {
        let date = now()
        lastPromptedAt = date
        defaults.set(date.timeIntervalSince1970, forKey: Key.lastPrompted)
    }

    /// User submitted the survey — store the review locally and never show it
    /// again. The review text is saved to `reviews.json`, on-device only.
    func submit(rating: Int, comment: String) {
        completed = true
        defaults.set(true, forKey: Key.completed)
        defaults.set(rating, forKey: Key.rating)

        let review = Review(rating: rating,
                            comment: comment.trimmingCharacters(in: .whitespacesAndNewlines),
                            at: now().timeIntervalSince1970)
        reviews.append(review)
        if let data = try? JSONEncoder().encode(reviews) {
            try? data.write(to: reviewsURL, options: .atomic)
        }
        // Log only the rating and whether a comment was left — never the free text.
        AppLog.ui("review saved rating=\(rating) hasComment=\(!review.comment.isEmpty) total=\(reviews.count)")
    }

    /// User dismissed without submitting — the weekly re-prompt window applies
    /// (already started by recordPrompted at show time).
    func skip() {
        AppLog.ui("survey skipped")
    }
}
