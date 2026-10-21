import SwiftUI
import UIKit

struct MivoColors {
    // MARK: - Mivo Brand Palette (2026)
    
    /// Page background (slightly lighter) - #FAF3E8
    static let background = adaptive(light: "#FAF3E8", dark: "#161008")
    
    /// Cards, sections - #F0E4CC
    static let surface = adaptive(light: "#F0E4CC", dark: "#2A1D14")

    /// Raised controls and cards that are white in light mode.
    static let surfaceRaised = adaptive(light: "#FFFFFF", dark: "#34241A")
    
    /// Borders, inactive states - #C8A882
    static let muted = adaptive(light: "#C8A882", dark: "#A8896F")
    
    /// Amber accent from logo - #D4872A
    static let accent = Color(hex: "#D4872A")
    
    /// Secondary text, labels - #B5621E
    static let secondary = adaptive(light: "#B5621E", dark: "#E29A50")
    
    /// Headings, body text - #5C3317
    static let primary = adaptive(light: "#5C3317", dark: "#FAF3E8")

    /// High-contrast reading ink used beside Apple's live Screen Time report - #161008
    static let screenTimeInk = adaptive(light: "#161008", dark: "#FAF3E8")

    /// Fixed cinematic backdrop used by onboarding in either app appearance.
    static let onboardingStage = Color(hex: "#161008")
    
    /// Hero card background (lightened) - #8B4E28
    static let heroBg = adaptive(light: "#8B4E28", dark: "#704024")
    
    /// New blue accent for CTAs, icons, highlights - #4A6FA5
    static let blue = adaptive(light: "#4A6FA5", dark: "#7898C7")
    
    // MARK: - v2 Redesign Tokens
    //
    // Added alongside the existing palette rather than replacing it, so screens
    // can move to the redesign one at a time. The foundation pass will re-point
    // `primary`/`surface` at `ink`/`surfaceV2` and retire the older names.

    /// All headings, values and row labels. Slightly darker than `primary`.
    /// 10.9:1 on `background`.
    static let ink = adaptive(light: "#3D2313", dark: "#FAF3E8")

    /// Body and secondary sentences. 5.4:1 on `background` — the lightest tone
    /// permitted for prose.
    static let inkBody = adaptive(light: "#6E5238", dark: "#C8B39B")

    /// Eyebrows, meta and captions only. 2.9:1, so never used for prose.
    static let inkMuted = adaptive(light: "#9C7A56", dark: "#A8896F")

    /// Text links and tertiary buttons. 4.6:1 — the accessible stand-in for
    /// amber text, which must never appear below 18pt on cream.
    static let deep = adaptive(light: "#B5621E", dark: "#E29A50")

    /// Facts, BETA/FOUNDER badges and founder rows. Never a call to action.
    static let info = adaptive(light: "#4A6FA5", dark: "#7898C7")

    /// Positive, "kept" and completed states, and downward-trend indicators.
    static let kept = adaptive(light: "#5F7F63", dark: "#7C9C80")

    /// "Kept" and positive values as *text* on a card. `kept` is 4.2:1 on white,
    /// which is not enough for 12–13pt type; this is.
    static let keptInk = adaptive(light: "#4A6A4E", dark: "#9CBB9F")

    /// Sheet emphasis blocks, avatar and app tiles, selected chips. Never
    /// nested inside another surface.
    static let surfaceV2 = adaptive(light: "#F3E8D5", dark: "#2A1D14")

    /// Section dividers.
    static let hairline = adaptive(light: "#3D2313", dark: "#FAF3E8").opacity(0.13)

    /// Dividers between rows within one list.
    static let hairlineSoft = adaptive(light: "#3D2313", dark: "#FAF3E8").opacity(0.10)

    /// Chart bars that are not today, and progress tracks.
    static let barTrack = adaptive(light: "#3D2313", dark: "#FAF3E8").opacity(0.16)

    /// Cinematic backdrops only: the onboarding intro and the pause screen.
    static let stage = Color(hex: "#161008")

    // MARK: - Computed/Derived Colors

    /// Hero card circular arc stroke (uses accent)
    static let heroArc = accent
    
    /// Hero card text on dark background (uses background)
    static let heroText = Color(hex: "#FAF3E8")
    
    // MARK: - Legacy Aliases (for gradual migration)
    
    static let card = surface
    static let border = muted
    
    static let accentLight = secondary
    static let accentMuted = background
    
    static let textPrimary = primary
    static let textSecondary = secondary
    static let textMuted = muted
    
    static let brand = heroBg
    
    static let timerGreen = secondary
    static let timerOrange = accent
    static let timerRed = Color(hex: "#B05540")
    static let green = timerGreen
    static let orange = timerOrange
    
    static let white = Color.white
    static let overlay = Color.black.opacity(0.5)

    private static func adaptive(light: String, dark: String) -> Color {
        Color(UIColor { traits in
            UIColor(mivoHex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(mivoHex: String) {
        let hex = mivoHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let red = CGFloat((int >> 16) & 0xFF) / 255
        let green = CGFloat((int >> 8) & 0xFF) / 255
        let blue = CGFloat(int & 0xFF) / 255
        self.init(red: red, green: green, blue: blue, alpha: 1)
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
