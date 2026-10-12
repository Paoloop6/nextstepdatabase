//
//  SurveyView.swift
//  nextstepdatabase
//
//  A short, self-contained feedback survey shown after a completed match.
//  Rating + optional comment; stored locally via SurveyStore.
//

import SwiftUI

struct SurveyView: View {
    @Environment(SurveyStore.self) private var survey
    @Environment(\.dismiss) private var dismiss

    @State private var rating = 0
    @State private var comment = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Text("How’s NextStep working for you?")
                            .font(.title3.weight(.bold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text("You just ran a match — a quick rating helps us improve. This stays on your device.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    stars

                    VStack(alignment: .leading, spacing: Theme.Space.sm) {
                        Text(rating >= 4 ? "Write a review (optional)" : "Write a review — what could we do better? (optional)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField("Share your experience…", text: $comment, axis: .vertical)
                            .lineLimit(3...6)
                            .textFieldStyle(.plain)
                            .padding(Theme.Space.md)
                            .background(Color.brandChip, in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
                            .accessibilityLabel("Write a review")
                    }

                    Button {
                        survey.submit(rating: rating, comment: comment)
                        dismiss()
                    } label: {
                        Text("Submit")
                            .frame(maxWidth: .infinity, minHeight: Theme.minTouchTarget)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.brandAccent)
                    .disabled(rating == 0)
                }
                .padding(Theme.Space.lg)
            }
            .background(Color.brandBackground)
            .navigationTitle("Quick survey")
            .inlineNavTitle()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Not now") {
                        survey.skip()
                        dismiss()
                    }
                }
            }
        }
    }

    private var stars: some View {
        HStack(spacing: Theme.Space.sm) {
            ForEach(1...5, id: \.self) { i in
                Button {
                    rating = i
                } label: {
                    Image(systemName: i <= rating ? "star.fill" : "star")
                        .font(.title)
                        .foregroundStyle(i <= rating ? Color.brandAccent : .secondary)
                        .frame(width: Theme.minTouchTarget, height: Theme.minTouchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(i) star\(i == 1 ? "" : "s")")
                .accessibilityAddTraits(i == rating ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Rating: \(rating) of 5 stars")
    }
}
