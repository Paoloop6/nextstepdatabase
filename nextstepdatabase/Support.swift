//
//  Support.swift
//  nextstepdatabase
//
//  Sanitized logging and a small set of demo opportunities used only when the
//  live backend is unreachable. Demo data is clearly flagged in the UI.
//

import Foundation
import OSLog

/// Sanitized diagnostic logging. Never log tokens, credentials, or user data.
enum AppLog {
    private static let net = Logger(subsystem: "k.nextstepdatabase", category: "network")
    private static let ui = Logger(subsystem: "k.nextstepdatabase", category: "ui")
    static func net(_ message: String) { net.debug("\(message, privacy: .public)") }
    static func ui(_ message: String) { ui.debug("\(message, privacy: .public)") }
}

/// A handful of representative records for offline / failure fallback. These
/// mirror the real schema's shape (including deliberately missing fields) so
/// the "unknown" handling is exercised even without a network.
enum DemoData {
    static let opportunities: [Opportunity] = [
        Opportunity(
            id: "demo-1",
            title: "Summer Science Research Internship",
            organization: "Riverside University",
            opportunityType: "Summer research internship",
            stemFields: ["Biology", "Chemistry"],
            description: "An eight-week mentored research placement in a university lab for high school students.",
            eligibility: "Open to rising juniors and seniors with prior coursework in biology or chemistry.",
            gradeLevels: ["Junior", "Senior"],
            location: "Riverside, CA",
            remoteStatus: "in-person",
            deadline: "2026-03-15",
            applicationStatus: "Open",
            cost: "Free",
            compensation: "Stipend available",
            officialUrl: "https://example.org/summer-research"
        ),
        Opportunity(
            id: "demo-2",
            title: "National High School Coding Competition",
            organization: "Open Compute Foundation",
            opportunityType: "Hackathon",
            stemFields: ["Computer Science"],
            description: "A 24-hour virtual hackathon with tracks for beginners and advanced builders.",
            eligibility: "Any enrolled high school student.",
            gradeLevels: ["Freshman", "Sophomore", "Junior", "Senior"],
            location: "Online",
            remoteStatus: "remote",
            deadline: "Rolling",
            applicationStatus: "Open",
            cost: nil, // cost not specified — UI must not claim it is free
            officialUrl: "https://example.org/hackathon"
        ),
        Opportunity(
            id: "demo-3",
            title: "Undergraduate Engineering Scholarship",
            organization: "Bridge STEM Fund",
            opportunityType: "Scholarship",
            stemFields: ["Engineering"],
            description: "A merit scholarship for students pursuing an engineering degree.",
            eligibility: "Graduating seniors admitted to an accredited engineering program.",
            gradeLevels: ["Senior"],
            location: "United States",
            remoteStatus: "unknown",
            deadline: "2026-05-01",
            applicationStatus: "Open",
            cost: "Free",
            officialUrl: "https://example.org/scholarship"
        )
    ]
}
