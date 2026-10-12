//
//  Match.swift
//  nextstepdatabase
//
//  Student-profile matching via the backend's POST /api/ask-stempath endpoint —
//  the SAME DeepSeek-backed endpoint the website uses. DeepSeek runs entirely on
//  the server (it analyzes the candidates and writes each match_reason); the app
//  only sends a question + profile and never holds a model key.
//
//  (The older /api/match route was rubric-only in practice — its DeepSeek
//  refinement silently fell back — so we use ask-stempath, which is pure
//  DeepSeek, to match the website's behavior.)
//

import Foundation

// MARK: - Form input (bound by the Match form UI)

struct MatchProfileInput: Equatable {
    var grade: Int = 11
    var age: Int = 16
    var stemInterest: String = "Any"
    var opportunityType: String = "Any"
    var locationPreference: String = "Any"
    var formatPreference: String = "Any"
    var costPreference: String = "Any"
    var experienceLevel: String = "any"
    var timeCommitment: String = "Any"
    var tier: String = "standard"
}

// MARK: - Request (mirrors the website's ask-stempath payload)

private struct AskRequest: Encodable {
    let question: String
    let context: [String]
    let tier: String
    let profile: AskProfile
}

private struct AskProfile: Encodable {
    let grade: String?
    let location: Location?
    let interests: [String]?
    let opportunityTypes: [String]?
    let formats: [String]?
    let costPreference: String?
    let specificInterest: String?

    struct Location: Encodable { let cityOrZip: String }
}

// MARK: - Response

struct AskStempathResponse: Decodable {
    let answer: String
    let clarificationQuestion: String?
    let matches: [AskMatch]

    enum CodingKeys: String, CodingKey {
        case answer, clarification_question, matches
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        answer = (try? c.decode(String.self, forKey: .answer)) ?? ""
        clarificationQuestion = try? c.decodeIfPresent(String.self, forKey: .clarification_question)
        matches = (try? c.decodeIfPresent([AskMatch].self, forKey: .matches)) ?? []
    }
    init(answer: String, matches: [AskMatch]) {
        self.answer = answer
        self.clarificationQuestion = nil
        self.matches = matches
    }
}

struct AskMatch: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let organization: String
    let opportunityType: String?
    let stemFields: [String]
    let eligibleGrades: [String]
    let location: String?
    let cost: String?
    let applicationStatus: String?
    let deadline: String?
    let officialUrl: String?
    let applicationUrl: String?
    let matchReason: String
    let eligibilityWarning: String?

    enum CodingKeys: String, CodingKey {
        case id, title, organization, opportunity_type, stem_fields, eligible_grades
        case location, cost, application_status, deadline, official_url, application_url
        case match_reason, eligibility_warning
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        title = (try? c.decode(String.self, forKey: .title)) ?? "Untitled opportunity"
        organization = (try? c.decode(String.self, forKey: .organization)) ?? "Unknown organization"
        opportunityType = try? c.decodeIfPresent(String.self, forKey: .opportunity_type)
        stemFields = (try? c.decodeIfPresent([String].self, forKey: .stem_fields)) ?? []
        // eligible_grades may be [String], a single String, or null.
        if let arr = try? c.decodeIfPresent([String].self, forKey: .eligible_grades) {
            eligibleGrades = arr
        } else if let s = try? c.decodeIfPresent(String.self, forKey: .eligible_grades), !s.isEmpty {
            eligibleGrades = [s]
        } else {
            eligibleGrades = []
        }
        location = try? c.decodeIfPresent(String.self, forKey: .location)
        cost = try? c.decodeIfPresent(String.self, forKey: .cost)
        applicationStatus = try? c.decodeIfPresent(String.self, forKey: .application_status)
        deadline = try? c.decodeIfPresent(String.self, forKey: .deadline)
        officialUrl = try? c.decodeIfPresent(String.self, forKey: .official_url)
        applicationUrl = try? c.decodeIfPresent(String.self, forKey: .application_url)
        matchReason = (try? c.decodeIfPresent(String.self, forKey: .match_reason)) ?? ""
        eligibilityWarning = try? c.decodeIfPresent(String.self, forKey: .eligibility_warning)
    }

    var sourceURL: URL? {
        Opportunity.makeURL(officialUrl) ?? Opportunity.makeURL(applicationUrl)
    }

    /// Build a match from a locally-loaded opportunity (for instant results).
    init(opportunity o: Opportunity, reason: String) {
        id = o.id
        title = o.title
        organization = o.organization
        opportunityType = o.opportunityType
        stemFields = o.stemFields
        eligibleGrades = o.gradeLevels
        location = o.location
        cost = o.cost
        applicationStatus = o.applicationStatus
        deadline = o.deadline
        officialUrl = o.officialUrl
        applicationUrl = o.applicationUrl
        matchReason = reason
        eligibilityWarning = nil
    }
}

// MARK: - On-device instant ranking (shown before DeepSeek returns)

enum LocalMatcher {
    /// Ranks already-loaded opportunities against the profile. Fast, no network.
    static func matches(profile p: MatchProfileInput, from opportunities: [Opportunity], limit: Int = 12) -> [AskMatch] {
        let interest = p.stemInterest.lowercased()
        let type = p.opportunityType.lowercased()
        let wantFormat = p.formatPreference.lowercased()
        let wantFree = p.costPreference.lowercased() == "free"

        func score(_ o: Opportunity) -> (Int, [String]) {
            var s = 0
            var reasons: [String] = []
            // Grade eligibility (empty grade list = open to all).
            let gradeText = o.gradeLevels.joined(separator: " ").lowercased()
            if o.gradeLevels.isEmpty || gradeText.contains("\(p.grade)") {
                s += 2
            }
            if interest != "any", o.searchText.contains(interest) || o.stemFields.contains(where: { $0.lowercased().contains(interest) }) {
                s += 3; reasons.append("matches your interest in \(p.stemInterest)")
            }
            if type != "any", o.category.lowercased().contains(type) || (o.opportunityType ?? "").lowercased().contains(type) {
                s += 3; reasons.append("it's \(p.opportunityType.lowercased())")
            }
            if wantFormat != "any", let f = o.formatLabel, f.lowercased() == wantFormat {
                s += 2; reasons.append(f.lowercased())
            }
            if wantFree, o.costLabel == "Free" {
                s += 1; reasons.append("free")
            }
            return (s, reasons)
        }

        return opportunities
            // Drop stale cohorts (only reference years before 2025).
            .filter { !Opportunity.hasOnlyStaleYears($0.deadline, $0.title, $0.applicationOpenDate) }
            .map { (o: $0, r: score($0)) }
            .filter { $0.r.0 > 0 }
            // Relevance first, but jitter so results mix up each run instead of
            // being identical every time.
            .map { (o: $0.o, key: Double($0.r.0) + Double.random(in: 0..<1.5), reasons: $0.r.1) }
            .sorted { $0.key > $1.key }
            .prefix(limit)
            .map { item in
                let why = item.reasons.isEmpty
                    ? "A strong fit for a grade \(p.grade) student."
                    : "Quick match: " + item.reasons.joined(separator: ", ") + "."
                return AskMatch(opportunity: item.o, reason: why)
            }
    }
}

// MARK: - Service

protocol MatchProviding: Sendable {
    func ask(profile: MatchProfileInput) async throws -> AskStempathResponse
}

extension LiveOpportunityService: MatchProviding {
    static let askEndpoint = URL(string: "https://www.nextstepdatabase.fyi/api/ask-stempath")!

    func ask(profile: MatchProfileInput) async throws -> AskStempathResponse {
        var request = URLRequest(url: Self.askEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 90   // DeepSeek analysis can take a while
        request.httpBody = try JSONEncoder().encode(Self.buildRequest(from: profile))

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            AppLog.net("ask-stempath non-2xx status \(http.statusCode)")
            throw OpportunityServiceError.badStatus(http.statusCode)
        }
        let decoded = try JSONDecoder().decode(AskStempathResponse.self, from: data)
        AppLog.net("ask-stempath returned \(decoded.matches.count) DeepSeek matches (tier: \(profile.tier))")
        return decoded
    }

    private static func buildRequest(from p: MatchProfileInput) -> AskRequest {
        func clean(_ s: String) -> String? {
            let t = s.trimmingCharacters(in: .whitespaces)
            return (t.isEmpty || t.lowercased() == "any") ? nil : t
        }
        let profile = AskProfile(
            grade: String(p.grade),
            location: clean(p.locationPreference).map { AskProfile.Location(cityOrZip: $0) },
            interests: clean(p.stemInterest).map { [$0] },
            opportunityTypes: clean(p.opportunityType).map { [$0] },
            formats: clean(p.formatPreference).map { [$0] },
            costPreference: clean(p.costPreference),
            specificInterest: clean(p.stemInterest)
        )
        return AskRequest(question: buildQuestion(from: p), context: [], tier: p.tier, profile: profile)
    }

    /// Turns the structured form into a natural-language question for DeepSeek.
    private static func buildQuestion(from p: MatchProfileInput) -> String {
        var parts: [String] = ["Find"]
        parts.append(p.opportunityType.lowercased() == "any" ? "STEM opportunities" : "\(p.opportunityType.lowercased()) opportunities")
        if p.stemInterest.lowercased() != "any" { parts.append("in \(p.stemInterest)") }
        parts.append("for a grade \(p.grade) student")
        var prefs: [String] = []
        if p.formatPreference.lowercased() != "any" { prefs.append(p.formatPreference) }
        if p.costPreference.lowercased() != "any" { prefs.append("\(p.costPreference) cost") }
        if !prefs.isEmpty { parts.append("(" + prefs.joined(separator: ", ") + ")") }
        return parts.joined(separator: " ") + "."
    }
}

// MARK: - Store

@MainActor
@Observable
final class MatchStore {
    private let service: MatchProviding
    private var latestToken = 0

    var profile = MatchProfileInput()
    var state: LoadState<AskStempathResponse> = .idle
    var hasSubmitted = false
    /// True while DeepSeek is still analyzing after instant local results shown.
    var isRefining = false

    init(service: MatchProviding = LiveOpportunityService()) {
        self.service = service
    }

    /// Shows instant on-device matches from `candidates`, then replaces them with
    /// DeepSeek's analyzed results when they arrive (keeping the instant ones if
    /// DeepSeek is slow or fails).
    func submit(candidates: [Opportunity] = []) async {
        hasSubmitted = true
        latestToken += 1
        let token = latestToken

        // 1. Instant results from the already-loaded catalog.
        let local = LocalMatcher.matches(profile: profile, from: candidates)
        if !local.isEmpty {
            state = .loaded(AskStempathResponse(answer: "", matches: local))
            isRefining = true
        } else {
            state = .loading
        }

        // 2. DeepSeek analysis. Pro often 502s server-side, so fall back to
        //    Standard on the second attempt.
        for attempt in 1...2 {
            var attemptProfile = profile
            if attempt == 2 { attemptProfile.tier = "standard" }
            do {
                let result = try await service.ask(profile: attemptProfile)
                guard token == latestToken else { return }   // superseded by a newer submit
                isRefining = false
                // Drop stale (pre-2025) matches; keep DeepSeek's ranking.
                let cleaned = result.matches.filter { !Opportunity.hasOnlyStaleYears($0.deadline, $0.title) }
                state = .loaded(AskStempathResponse(answer: result.answer, matches: cleaned))
                return
            } catch {
                guard token == latestToken else { return }
                AppLog.net("ask-stempath attempt \(attempt) (tier \(attemptProfile.tier)) failed: \(error.localizedDescription)")
                if attempt == 2 {
                    isRefining = false
                    // Keep the instant local results; only error if we had none.
                    if local.isEmpty {
                        state = .failed("The AI match service is busy right now. Please try again in a moment.")
                    }
                }
            }
        }
    }

    func reset() {
        profile = MatchProfileInput()
        state = .idle
        hasSubmitted = false
    }
}
