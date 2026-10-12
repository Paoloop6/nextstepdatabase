//
//  Components.swift
//  nextstepdatabase
//
//  Reusable building blocks so styling lives in one place: pill badges, a
//  wrapping badge layout, the opportunity card, the save button, and the
//  loading / empty / error state view.
//

import SwiftUI

// MARK: - Badge

/// Small pill label for metadata (category, format, grade, cost, status).
/// Adapted from the web app's dense metadata pills. Status meaning is carried
/// by an icon + text, never color alone.
struct Badge: View {
    let text: String
    var systemImage: String? = nil
    var tint: Color? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).font(.caption2) }
            Text(text)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(tint ?? .secondary)
        .padding(.horizontal, Theme.Space.sm)
        .padding(.vertical, Theme.Space.xs)
        .background(
            (tint ?? .primary).opacity(0.10),
            in: Capsule()
        )
        .overlay(Capsule().strokeBorder(Color.brandBorder, lineWidth: 0.5))
    }
}

// MARK: - Flow layout (wrapping badges)

/// Lays out subviews left-to-right, wrapping to new lines. Adapts naturally to
/// Dynamic Type since it measures each subview's ideal size.
struct FlowLayout: Layout {
    var spacing: CGFloat = Theme.Space.sm

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[CGSize]] = [[]]
        var x: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, !rows[rows.count - 1].isEmpty {
                rows.append([]); x = 0
            }
            rows[rows.count - 1].append(size)
            x += size.width + spacing
        }
        let height = rows.reduce(0) { partial, row in
            partial + (row.map(\.height).max() ?? 0) + spacing
        } - (rows.isEmpty ? 0 : spacing)
        return CGSize(width: maxWidth == .infinity ? 0 : maxWidth, height: max(height, 0))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Save button

/// A generously-sized, clearly-labeled save toggle. Large enough to tap without
/// triggering the surrounding card, and announces its state to VoiceOver.
struct SaveButton: View {
    let isSaved: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(isSaved ? Color.brandAccent : .secondary)
                .frame(width: Theme.minTouchTarget, height: Theme.minTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSaved ? "Saved" : "Save")
        .accessibilityHint(isSaved ? "Double tap to remove from saved" : "Double tap to save this opportunity")
        .accessibilityAddTraits(isSaved ? .isSelected : [])
    }
}

// MARK: - Opportunity card

struct OpportunityCard: View {
    let opportunity: Opportunity
    let isSaved: Bool
    let onToggleSave: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.sm) {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text(opportunity.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(opportunity.organization)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                FlowLayout {
                    Badge(text: opportunity.category, systemImage: "square.grid.2x2")
                    if let format = opportunity.formatLabel {
                        Badge(text: format, systemImage: "mappin.and.ellipse")
                    }
                    if let cost = opportunity.costLabel {
                        Badge(text: cost, systemImage: "tag")
                    }
                    if let grade = opportunity.gradeLevels.first {
                        Badge(text: gradeSummary(opportunity.gradeLevels, first: grade),
                              systemImage: "graduationcap")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            SaveButton(isSaved: isSaved, action: onToggleSave)
                .offset(x: Theme.Space.sm, y: -Theme.Space.sm)
        }
        .cardSurface()
        .contentShape(Rectangle())
        // Card content is one element for VoiceOver; the save button stays separate.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(opportunity.title), \(opportunity.organization), \(opportunity.category)")
    }

    private func gradeSummary(_ grades: [String], first: String) -> String {
        grades.count > 1 ? "\(first) +\(grades.count - 1)" : first
    }
}

// MARK: - State view

/// Renders loading, empty, and error states consistently. Never an endless
/// spinner: loading has a label, error and empty have a call to action.
struct StateView: View {
    enum Kind { case loading, empty, error }
    let kind: Kind
    var title: String
    var message: String
    var systemImage: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: Theme.Space.md) {
            if kind == .loading {
                ProgressView()
                    .controlSize(.large)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
            }
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(.brandAccent)
                    .padding(.top, Theme.Space.xs)
            }
        }
        .padding(Theme.Space.xl)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
