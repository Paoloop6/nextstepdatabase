//
//  OpportunityDetailView.swift
//  nextstepdatabase
//
//  Full opportunity detail. Every field is shown only when the data actually
//  provides it; missing information is stated explicitly rather than inferred.
//

import SwiftUI

struct OpportunityDetailView: View {
    let opportunity: Opportunity
    @Environment(SavedStore.self) private var saved
    @Environment(\.openURL) private var openURL
    @State private var linkError = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                header
                badges
                if let status = opportunity.applicationStatus {
                    Label(status, systemImage: statusIcon(status))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(statusColor(status))
                        .accessibilityLabel("Application status: \(status)")
                }

                section("About", value: opportunity.description)
                section("Eligibility", value: opportunity.eligibility)
                detailGrid
                OpportunityLocationMap(rawLocation: opportunity.location, title: opportunity.title,
                                       presetPoint: opportunity.storedPoint)
                if !opportunity.stemFields.isEmpty {
                    labeledBlock("STEM fields") {
                        FlowLayout {
                            ForEach(opportunity.stemFields, id: \.self) { field in
                                Badge(text: field)
                            }
                        }
                    }
                }
                actions
            }
            .padding(Theme.Space.lg)
        }
        .background(Color.brandBackground)
        .navigationTitle("Details")
        .inlineNavTitle()
        .alert("Couldn’t open link", isPresented: $linkError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The source link for this opportunity is missing or invalid.")
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(opportunity.title)
                .font(.title2.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
            Text(opportunity.organization)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    private var badges: some View {
        FlowLayout {
            Badge(text: opportunity.category, systemImage: "square.grid.2x2")
            if let format = opportunity.formatLabel {
                Badge(text: format, systemImage: "mappin.and.ellipse")
            }
            if let cost = opportunity.costLabel {
                Badge(text: cost, systemImage: "tag")
            }
        }
    }

    @ViewBuilder
    private var detailGrid: some View {
        let rows: [(String, String, String)] = [
            ("Location", "mappin.and.ellipse", opportunity.location ?? "Not specified"),
            ("Format", "wifi", opportunity.formatLabel ?? "Not specified"),
            ("Cost", "tag", opportunity.cost ?? "Not specified"),
            ("Compensation", "dollarsign.circle", opportunity.compensation ?? "Not specified"),
            ("Deadline", "calendar", opportunity.deadline ?? "Not specified"),
            ("Grade levels", "graduationcap",
                opportunity.gradeLevels.isEmpty ? "Not specified" : opportunity.gradeLevels.joined(separator: ", ")),
            ("Experience", "chart.bar", opportunity.experienceLevel ?? "Not specified"),
            ("Time commitment", "clock", opportunity.timeCommitment ?? "Not specified")
        ]
        labeledBlock("Details") {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    HStack(alignment: .top, spacing: Theme.Space.md) {
                        Label(row.0, systemImage: row.1)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(width: 130, alignment: .leading)
                        Text(row.2)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(row.2 == "Not specified" ? .tertiary : .primary)
                    }
                    .padding(.vertical, Theme.Space.sm)
                    .accessibilityElement(children: .combine)
                    if index < rows.count - 1 { Divider() }
                }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: Theme.Space.md) {
            Button {
                saved.toggle(opportunity.id)
            } label: {
                Label(saved.isSaved(opportunity.id) ? "Saved" : "Save opportunity",
                      systemImage: saved.isSaved(opportunity.id) ? "bookmark.fill" : "bookmark")
                    .frame(maxWidth: .infinity, minHeight: Theme.minTouchTarget)
            }
            .buttonStyle(.bordered)
            .tint(.brandAccent)
            .accessibilityAddTraits(saved.isSaved(opportunity.id) ? .isSelected : [])

            Button {
                if let url = opportunity.sourceURL {
                    openURL(url)
                } else {
                    linkError = true
                }
            } label: {
                Label("View original opportunity", systemImage: "safari")
                    .frame(maxWidth: .infinity, minHeight: Theme.minTouchTarget)
            }
            .buttonStyle(.borderedProminent)
            .tint(.brandAccent)
            .disabled(opportunity.sourceURL == nil)

            if let domain = opportunity.sourceDomain {
                Label("Opens \(domain)", systemImage: "link")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Opens the source website \(domain)")
            } else {
                Text("No source link is available for this opportunity.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, Theme.Space.sm)
    }

    // MARK: Helpers

    @ViewBuilder
    private func section(_ title: String, value: String?) -> some View {
        labeledBlock(title) {
            Text(value ?? "Not provided.")
                .font(.body)
                .foregroundStyle(value == nil ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func labeledBlock<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func statusIcon(_ status: String) -> String {
        status.lowercased().contains("open") ? "checkmark.circle.fill" : "info.circle.fill"
    }
    private func statusColor(_ status: String) -> Color {
        status.lowercased().contains("open") ? .statusOpen : .statusWarning
    }
}
