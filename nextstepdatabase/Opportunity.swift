//
//  Opportunity.swift
//  nextstepdatabase
//
//  Model for a NextStep / STEM Path Finder opportunity plus pure, testable
//  normalization and filtering logic.
//
//  The live API (https://www.nextstepdatabase.fyi/api/opportunities) returns a
//  DynamoDB-shaped payload whose fields are heterogeneous and frequently null
//  or free-text. Decoding is deliberately lenient: a missing or malformed
//  field becomes nil rather than failing the whole record. We never infer that
//  an opportunity is free, remote, open, or eligible when the data does not
//  say so — unknowns stay unknown.
//

import Foundation

struct Opportunity: Identifiable, Hashable, Decodable {
    let id: String            // opportunityId — stable identifier used for saving
    let title: String
    let organization: String
    let opportunityType: String?
    let stemFields: [String]
    let description: String?
    let eligibility: String?
    let gradeLevels: [String]
    let location: String?
    let remoteStatus: String?
    let deadline: String?
    let applicationOpenDate: String?
    let applicationStatus: String?
    let cost: String?
    let compensation: String?
    let officialUrl: String?
    let applicationUrl: String?
    let experienceLevel: String?
    let timeCommitment: String?
    /// Precomputed coordinates served by the backend (after server-side
    /// geocoding). When present the map uses these directly — no on-device
    /// geocoding needed, so pins load instantly.
    let latitude: Double?
    let longitude: Double?

    /// Lowercased "title organization description", computed once at load so
    /// filtering never re-lowercases or re-concatenates on every keystroke.
    let searchText: String

    enum CodingKeys: String, CodingKey {
        case opportunityId, title, organization, opportunityType, stemFields
        case description, eligibility, gradeLevels, location, remoteStatus
        case deadline, applicationOpenDate, applicationStatus, cost, compensation
        case officialUrl, applicationUrl, experienceLevel, timeCommitment
        case latitude = "lat", longitude = "lng"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // opportunityId is required for identity; fall back to a UUID only if truly absent.
        id = (try? c.decode(String.self, forKey: .opportunityId)) ?? UUID().uuidString
        title = (try? c.decode(String.self, forKey: .title)) ?? "Untitled opportunity"
        organization = (try? c.decode(String.self, forKey: .organization)) ?? "Unknown organization"
        opportunityType = Self.cleaned(try? c.decodeIfPresent(String.self, forKey: .opportunityType))
        stemFields = (try? c.decodeIfPresent([String].self, forKey: .stemFields)) ?? []
        description = Self.cleaned(try? c.decodeIfPresent(String.self, forKey: .description))
        eligibility = Self.cleaned(try? c.decodeIfPresent(String.self, forKey: .eligibility))
        gradeLevels = (try? c.decodeIfPresent([String].self, forKey: .gradeLevels)) ?? []
        location = Self.cleaned(try? c.decodeIfPresent(String.self, forKey: .location))
        remoteStatus = Self.cleaned(try? c.decodeIfPresent(String.self, forKey: .remoteStatus))
        deadline = Self.cleaned(try? c.decodeIfPresent(String.self, forKey: .deadline))
        applicationOpenDate = Self.cleaned(try? c.decodeIfPresent(String.self, forKey: .applicationOpenDate))
        applicationStatus = Self.cleaned(try? c.decodeIfPresent(String.self, forKey: .applicationStatus))
        cost = Self.cleaned(try? c.decodeIfPresent(String.self, forKey: .cost))
        compensation = Self.cleaned(try? c.decodeIfPresent(String.self, forKey: .compensation))
        officialUrl = Self.cleaned(try? c.decodeIfPresent(String.self, forKey: .officialUrl))
        applicationUrl = Self.cleaned(try? c.decodeIfPresent(String.self, forKey: .applicationUrl))
        experienceLevel = Self.cleaned(try? c.decodeIfPresent(String.self, forKey: .experienceLevel))
        timeCommitment = Self.cleaned(try? c.decodeIfPresent(String.self, forKey: .timeCommitment))
        latitude = try? c.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try? c.decodeIfPresent(Double.self, forKey: .longitude)
        searchText = Self.makeSearchText(title: title, organization: organization, description: description)
    }

    /// Memberwise init used by demo data and tests.
    init(id: String, title: String, organization: String, opportunityType: String? = nil,
         stemFields: [String] = [], description: String? = nil, eligibility: String? = nil,
         gradeLevels: [String] = [], location: String? = nil, remoteStatus: String? = nil,
         deadline: String? = nil, applicationOpenDate: String? = nil, applicationStatus: String? = nil,
         cost: String? = nil, compensation: String? = nil, officialUrl: String? = nil,
         applicationUrl: String? = nil, experienceLevel: String? = nil, timeCommitment: String? = nil,
         latitude: Double? = nil, longitude: Double? = nil) {
        self.id = id; self.title = title; self.organization = organization
        self.opportunityType = opportunityType; self.stemFields = stemFields
        self.description = description; self.eligibility = eligibility
        self.gradeLevels = gradeLevels; self.location = location; self.remoteStatus = remoteStatus
        self.deadline = deadline; self.applicationOpenDate = applicationOpenDate
        self.applicationStatus = applicationStatus; self.cost = cost; self.compensation = compensation
        self.officialUrl = officialUrl; self.applicationUrl = applicationUrl
        self.experienceLevel = experienceLevel; self.timeCommitment = timeCommitment
        self.latitude = latitude; self.longitude = longitude
        self.searchText = Self.makeSearchText(title: title, organization: organization, description: description)
    }

    /// Backend-supplied coordinate, if both lat and lng are present.
    var storedPoint: GeoPoint? {
        guard let latitude, let longitude else { return nil }
        return GeoPoint(lat: latitude, lon: longitude)
    }

    /// Builds the precomputed lowercased search haystack.
    static func makeSearchText(title: String, organization: String, description: String?) -> String {
        [title, organization, description ?? ""].joined(separator: " ").lowercased()
    }

    /// True when the given text(s) reference year(s) but the most recent one is
    /// before 2025 — i.e. a stale/old cohort (e.g. "Class of 2021"). Text with no
    /// year is treated as current (not stale).
    static func hasOnlyStaleYears(_ texts: String?...) -> Bool {
        let joined = texts.compactMap { $0 }.joined(separator: " ")
        let years = joined.matches(of: /20[0-9]{2}/).compactMap { Int($0.output) }
        guard let newest = years.max() else { return false }
        return newest < 2025
    }

    /// Treats empty / "none" / "null" strings as genuinely absent.
    private static func cleaned(_ value: String??) -> String? {
        guard let inner = value ?? nil else { return nil }
        let trimmed = inner.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        if trimmed.isEmpty || lowered == "none" || lowered == "null" || lowered == "n/a" { return nil }
        return trimmed
    }

    /// Best available link to the source opportunity.
    var sourceURL: URL? {
        Self.makeURL(officialUrl) ?? Self.makeURL(applicationUrl)
    }

    /// Builds a valid http(s) URL, trimming whitespace and percent-encoding as a
    /// fallback so slightly-malformed links (e.g. containing a space) still open.
    static func makeURL(_ raw: String?) -> URL? {
        guard let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        if let url = URL(string: s), url.scheme?.hasPrefix("http") == true { return url }
        if let encoded = s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: encoded), url.scheme?.hasPrefix("http") == true { return url }
        return nil
    }

    /// Human-readable host of the source website, e.g. "mit.edu".
    var sourceDomain: String? {
        guard let host = sourceURL?.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// The location string when it denotes a *specific* place we can put on a
    /// map, or nil for remote / nationwide / blank locations (which aren't a
    /// single point and must never be shown as one). Static so other types
    /// (e.g. match results) can reuse the exact same rule.
    static func mapQuery(from location: String?) -> String? {
        guard let loc = location?.trimmingCharacters(in: .whitespacesAndNewlines), !loc.isEmpty else { return nil }
        let l = loc.lowercased()
        let nonPlace = ["online", "remote", "virtual", "nationwide", "varies", "multiple locations",
                        "50 states", "various"]
        if nonPlace.contains(where: { l.contains($0) }) { return nil }
        if l == "united states" || l == "u.s." || l == "usa" { return nil }
        return loc
    }

    var mapQuery: String? { Self.mapQuery(from: location) }
    var isMappable: Bool { mapQuery != nil }
}

// MARK: - Derived facets (normalization)

extension Opportunity {

    /// Collapses the many free-text `opportunityType` variants into a stable set
    /// of categories that actually appear in the data.
    var category: String { Self.category(for: opportunityType) }

    static func category(for type: String?) -> String {
        let t = (type ?? "").lowercased()
        if t.isEmpty { return "Other" }
        if t.contains("hackathon") || t.contains("competition") { return "Competitions" }
        if t.contains("scholarship") || t.contains("award") { return "Scholarships" }
        if t.contains("research") { return "Research" }
        if t.contains("internship") { return "Internships" }
        if t.contains("mentor") { return "Mentorship" }
        if t.contains("volunteer") { return "Volunteering" }
        if t.contains("summer") || t.contains("pre-college") || t.contains("precollege")
            || t.contains("academy") || t.contains("camp") || t.contains("program") { return "Summer Programs" }
        return "Other"
    }

    /// Remote / in-person / hybrid, or nil when the data does not establish it.
    var formatLabel: String? {
        guard let r = remoteStatus?.lowercased() else { return nil }
        if r == "unknown" { return nil }
        if r.contains("remote") || r.contains("virtual") || r.contains("online") { return "Remote" }
        if r.contains("hybrid") { return "Hybrid" }
        if r.contains("person") || r.contains("onsite") || r.contains("residential") { return "In-person" }
        return nil
    }

    /// Free / Paid, or nil when cost is not specified. We only say "Free" when
    /// the source explicitly indicates it — never inferred from a null.
    var costLabel: String? {
        guard let c = cost?.lowercased() else { return nil }
        if c.contains("free") || c.contains("no cost") || c.contains("fully funded") { return "Free" }
        return "Paid"
    }
}

// MARK: - Filtering (pure, unit-tested)

struct OpportunityFilters: Equatable {
    var categories: Set<String> = []
    var grades: Set<String> = []
    var formats: Set<String> = []
    var costs: Set<String> = []   // "Free", "Paid", "Not specified"

    var isEmpty: Bool {
        categories.isEmpty && grades.isEmpty && formats.isEmpty && costs.isEmpty
    }
    var activeCount: Int {
        categories.count + grades.count + formats.count + costs.count
    }
}

enum OpportunityQuery {

    /// Applies free-text search and structured filters. Order-independent and
    /// side-effect free so it can be exercised directly in tests.
    static func apply(_ items: [Opportunity], search: String, filters: OpportunityFilters) -> [Opportunity] {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return items.filter { opp in
            if !needle.isEmpty {
                // Uses the precomputed per-opportunity searchText (title +
                // organization + description) rather than rebuilding it here.
                if !opp.searchText.contains(needle) { return false }
            }
            if !filters.categories.isEmpty, !filters.categories.contains(opp.category) { return false }
            if !filters.grades.isEmpty {
                let oppGrades = Set(opp.gradeLevels)
                if oppGrades.isDisjoint(with: filters.grades) { return false }
            }
            if !filters.formats.isEmpty {
                guard let f = opp.formatLabel, filters.formats.contains(f) else { return false }
            }
            if !filters.costs.isEmpty {
                let label = opp.costLabel ?? "Not specified"
                if !filters.costs.contains(label) { return false }
            }
            return true
        }
    }

    /// Distinct categories present in the data, ordered by frequency.
    static func categories(in items: [Opportunity]) -> [String] {
        frequencyOrdered(items.map(\.category))
    }

    /// Distinct grade levels present in the data.
    static func grades(in items: [Opportunity]) -> [String] {
        frequencyOrdered(items.flatMap(\.gradeLevels))
    }

    private static func frequencyOrdered(_ values: [String]) -> [String] {
        var counts: [String: Int] = [:]
        for v in values where !v.isEmpty { counts[v, default: 0] += 1 }
        return counts.keys.sorted { (counts[$0]!, $1) > (counts[$1]!, $0) }
    }
}
