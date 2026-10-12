//
//  SelfTests.swift
//  nextstepdatabase
//
//  Lightweight, dependency-free assertions for the two pieces of logic most
//  worth protecting: filtering and saved-state persistence. The project has no
//  separate test target (single app target with a synchronized file group), so
//  these run on demand and are compiled out of release builds.
//
//  Run from a DEBUG build (e.g. via RunCodeSnippet or a temporary call) with:
//      SelfTests.runAll()
//

#if DEBUG
import Foundation

enum SelfTests {

    private static var sample: [Opportunity] {
        [
            Opportunity(id: "a", title: "Robotics Summer Camp", organization: "Acme Labs",
                        opportunityType: "Summer camp", gradeLevels: ["Freshman", "Sophomore"],
                        remoteStatus: "in-person", cost: "Free"),
            Opportunity(id: "b", title: "AI Research Fellowship", organization: "Beacon University",
                        opportunityType: "Research program", description: "Machine learning research",
                        gradeLevels: ["Senior"], remoteStatus: "remote", cost: "$500"),
            Opportunity(id: "c", title: "Coding Competition", organization: "Cipher Foundation",
                        opportunityType: "Hackathon", gradeLevels: ["Junior", "Senior"],
                        remoteStatus: "unknown", cost: nil)
        ]
    }

    @MainActor
    @discardableResult
    static func runAll() -> Bool {
        var passed = 0, failed = 0
        func check(_ name: String, _ condition: Bool) {
            if condition { passed += 1; print("✅ \(name)") }
            else { failed += 1; print("❌ \(name)") }
        }

        let items = sample

        // Search matches title, organization, and description; case-insensitive.
        check("search by title", OpportunityQuery.apply(items, search: "robotics", filters: .init()).map(\.id) == ["a"])
        check("search by organization", OpportunityQuery.apply(items, search: "beacon", filters: .init()).map(\.id) == ["b"])
        check("search by description", OpportunityQuery.apply(items, search: "machine learning", filters: .init()).map(\.id) == ["b"])
        check("empty search returns all", OpportunityQuery.apply(items, search: "  ", filters: .init()).count == 3)

        // Category normalization + filtering.
        check("hackathon → Competitions", Opportunity.category(for: "Hackathon") == "Competitions")
        check("summer research internship → Research", Opportunity.category(for: "Summer research internship") == "Research")
        var f = OpportunityFilters(); f.categories = ["Research"]
        check("category filter", OpportunityQuery.apply(items, search: "", filters: f).map(\.id) == ["b"])

        // Format filter excludes unknown remote status.
        var ff = OpportunityFilters(); ff.formats = ["Remote"]
        check("format filter remote", OpportunityQuery.apply(items, search: "", filters: ff).map(\.id) == ["b"])

        // Cost: nil is "Not specified", never inferred as Free.
        check("nil cost is not Free", items.first { $0.id == "c" }!.costLabel == nil)
        var cf = OpportunityFilters(); cf.costs = ["Not specified"]
        check("cost filter not-specified", OpportunityQuery.apply(items, search: "", filters: cf).map(\.id) == ["c"])
        var free = OpportunityFilters(); free.costs = ["Free"]
        check("cost filter free", OpportunityQuery.apply(items, search: "", filters: free).map(\.id) == ["a"])

        // Grade filter (any overlap).
        var gf = OpportunityFilters(); gf.grades = ["Senior"]
        check("grade filter", Set(OpportunityQuery.apply(items, search: "", filters: gf).map(\.id)) == ["b", "c"])

        // Combined search + filter.
        var combo = OpportunityFilters(); combo.categories = ["Competitions"]
        check("combined search+filter", OpportunityQuery.apply(items, search: "coding", filters: combo).map(\.id) == ["c"])

        // Precomputed search string: lowercased, concatenated, and actually used
        // by the filter (an organization-only match proves searchText is queried).
        check("searchText is lowercased", items[0].searchText == items[0].searchText.lowercased())
        check("searchText concatenates fields",
              items[1].searchText.contains("beacon university") && items[1].searchText.contains("machine learning"))
        check("filter uses precomputed searchText (org-only match)",
              OpportunityQuery.apply(items, search: "cipher", filters: .init()).map(\.id) == ["c"])

        // Disk cache round-trips: write raw JSON → read → decode.
        let cacheURL = FileManager.default.temporaryDirectory.appendingPathComponent("selftest-opps-cache.json")
        let cache = OpportunityCache(url: cacheURL)
        let cacheJSON = #"{"count":2,"opportunities":[{"opportunityId":"x1","title":"Alpha","organization":"Org A"},{"opportunityId":"x2","title":"Beta","organization":"Org B"}]}"#
        try? cache.write(Data(cacheJSON.utf8))
        let restored = cache.read()
        let decoded = (try? LiveOpportunityService.parseOpportunities(restored?.data ?? Data())) ?? []
        check("cache round-trips (write→read→decode)", decoded.count == 2 && decoded.first?.id == "x1")
        check("cache records a recent timestamp",
              restored.map { Date().timeIntervalSince($0.savedAt) < 60 } ?? false)
        cache.clear()

        // Saved persistence round-trips through UserDefaults.
        let suiteName = "selftests.saved"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store1 = SavedStore(defaults: defaults)
        store1.toggle("a"); store1.toggle("b")
        check("toggle saves two", store1.savedIDs.count == 2)
        check("isSaved true", store1.isSaved("a"))
        store1.toggle("a")
        check("toggle removes", !store1.isSaved("a") && store1.savedIDs == ["b"])
        let store2 = SavedStore(defaults: defaults)   // simulate relaunch
        check("persists across relaunch", store2.savedIDs == ["b"])
        defaults.removePersistentDomain(forName: suiteName)

        // Survey timing: first-match trigger, weekly re-prompt, once-completed.
        let sname = "selftests.survey"
        let sdefaults = UserDefaults(suiteName: sname)!
        sdefaults.removePersistentDomain(forName: sname)
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let reviewsURL = FileManager.default.temporaryDirectory.appendingPathComponent("selftest-reviews.json")
        try? FileManager.default.removeItem(at: reviewsURL)
        let s = SurveyStore(defaults: sdefaults, now: { clock }, reviewsURL: reviewsURL)
        check("survey hidden before first match", s.shouldPrompt == false)
        check("survey shows on first match", s.matchCompleted() == true)
        s.recordPrompted()
        check("survey not reshown immediately", s.shouldPrompt == false)
        clock = clock.addingTimeInterval(6 * 86_400)
        check("survey not reshown after 6 days", s.shouldPrompt == false)
        clock = clock.addingTimeInterval(2 * 86_400)   // now 8 days since prompt
        check("survey reshown after a week", s.shouldPrompt == true)
        s.submit(rating: 5, comment: "Loved the matches!")
        check("survey never shown after submit", s.shouldPrompt == false)
        check("review stored with text", s.reviews.count == 1 && s.reviews.first?.comment == "Loved the matches!" && s.reviews.first?.rating == 5)
        clock = clock.addingTimeInterval(30 * 86_400)
        check("survey stays gone weeks later", s.shouldPrompt == false)
        let s2 = SurveyStore(defaults: sdefaults, now: { clock }, reviewsURL: reviewsURL)   // relaunch
        check("survey completion persists across relaunch", s2.completed && !s2.shouldPrompt)
        check("review persists across relaunch", s2.reviews.first?.comment == "Loved the matches!")
        sdefaults.removePersistentDomain(forName: sname)
        try? FileManager.default.removeItem(at: reviewsURL)

        print("\nSelfTests: \(passed) passed, \(failed) failed")
        return failed == 0
    }
}
#endif
