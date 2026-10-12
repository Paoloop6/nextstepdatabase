//
//  SavedStore.swift
//  nextstepdatabase
//
//  Persists the set of saved opportunity identifiers locally so saves survive
//  relaunch and stay synchronized across every screen.
//

import Foundation
import SwiftUI

@MainActor
@Observable
final class SavedStore {
    private static let key = "saved_opportunity_ids"
    private let defaults: UserDefaults

    /// Saved identifiers, most-recently-saved first.
    private(set) var savedIDs: [String] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let stored = defaults.array(forKey: Self.key) as? [String] {
            savedIDs = stored
        }
    }

    func isSaved(_ id: String) -> Bool { savedIDs.contains(id) }

    func toggle(_ id: String) {
        if let index = savedIDs.firstIndex(of: id) {
            savedIDs.remove(at: index)
            AppLog.ui("unsaved opportunity")
        } else {
            savedIDs.insert(id, at: 0)
            AppLog.ui("saved opportunity")
        }
        persist()
    }

    /// Returns saved opportunities from a source list, preserving save order.
    func savedItems(from all: [Opportunity]) -> [Opportunity] {
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return savedIDs.compactMap { byID[$0] }
    }

    private func persist() {
        defaults.set(savedIDs, forKey: Self.key)
    }
}
