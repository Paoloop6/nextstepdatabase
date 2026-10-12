//
//  Theme.swift
//  nextstepdatabase
//
//  Design tokens for the NextStep Database iPhone app.
//
//  These are the app's own identity. Layout patterns (dense metadata cards,
//  pill badges, a single restrained accent) are adapted from the STEM Path
//  Finder / NextStep web app, but colors resolve through iOS semantic colors
//  so light and dark appearances both work correctly.
//

import SwiftUI

enum Theme {

    // MARK: Spacing scale (4pt grid)
    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: Corner radius
    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 14
        static let lg: CGFloat = 20
        static let pill: CGFloat = 999
    }

    /// Minimum interactive touch target per Apple HIG.
    static let minTouchTarget: CGFloat = 44
}

extension Color {

    /// Single NextStep accent — a restrained sage/teal that reads on light and
    /// dark. Adapted from the web app's `--brand-accent` (#8dc9a4) but tuned
    /// darker in light mode for text contrast.
    static let brandAccent = Color(
        light: Color(red: 0.13, green: 0.52, blue: 0.42),
        dark: Color(red: 0.55, green: 0.79, blue: 0.64)
    )

    #if canImport(UIKit)
    /// Page background.
    static let brandBackground = Color(uiColor: .systemGroupedBackground)
    /// Card / raised surface.
    static let brandSurface = Color(uiColor: .secondarySystemGroupedBackground)
    /// Subtle chip / badge fill.
    static let brandChip = Color(uiColor: .tertiarySystemFill)
    /// Hairline separators & card borders.
    static let brandBorder = Color(uiColor: .separator)
    #else
    static let brandBackground = Color(light: Color(red: 0.95, green: 0.95, blue: 0.97),
                                       dark: Color(red: 0.07, green: 0.08, blue: 0.09))
    static let brandSurface = Color(light: .white, dark: Color(red: 0.11, green: 0.12, blue: 0.13))
    static let brandChip = Color.gray.opacity(0.15)
    static let brandBorder = Color.gray.opacity(0.3)
    #endif

    /// Status colors — always paired with text/iconography, never color alone.
    static let statusOpen = Color(
        light: Color(red: 0.11, green: 0.47, blue: 0.30),
        dark: Color(red: 0.55, green: 0.82, blue: 0.64)
    )
    static let statusWarning = Color(
        light: Color(red: 0.62, green: 0.42, blue: 0.10),
        dark: Color(red: 0.84, green: 0.65, blue: 0.36)
    )

    /// Convenience initializer to build an appearance-adaptive color.
    init(light: Color, dark: Color) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
        #else
        self = dark
        #endif
    }
}

// MARK: - Reusable surface style

/// A rounded card surface used across the app so styling lives in one place.
struct CardSurface: ViewModifier {
    var padding: CGFloat = Theme.Space.lg
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color.brandSurface, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .strokeBorder(Color.brandBorder, lineWidth: 0.5)
            )
    }
}

extension View {
    func cardSurface(padding: CGFloat = Theme.Space.lg) -> some View {
        modifier(CardSurface(padding: padding))
    }

    // MARK: Cross-platform helpers
    // The app targets iPhone, but these keep the code compiling for the macOS
    // destination too so Xcode's SwiftUI Preview (canvas) renders without needing
    // the run destination changed. On macOS the iOS-only modifiers are no-ops.

    /// Inline navigation title on iOS; no-op on other platforms.
    @ViewBuilder func inlineNavTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// Medium/large sheet detents on iOS; no-op elsewhere.
    @ViewBuilder func mediumLargeDetents() -> some View {
        #if os(iOS)
        self.presentationDetents([.medium, .large])
        #else
        self
        #endif
    }

    /// A fixed-height sheet detent on iOS; no-op elsewhere.
    @ViewBuilder func fixedDetent(_ height: CGFloat) -> some View {
        #if os(iOS)
        self.presentationDetents([.height(height)])
        #else
        self
        #endif
    }
}
