import SwiftUI

struct MivoColors {
    // MARK: - New Mivo Brand Palette
    
    /// Page background - #F5E6C8
    static let background = Color(hex: "#F5E6C8")
    
    /// Cards, sections - #EDD9B3
    static let surface = Color(hex: "#EDD9B3")
    
    /// Borders, inactive states - #C8A882
    static let muted = Color(hex: "#C8A882")
    
    /// Selections, highlights, dot - #D4872A
    static let accent = Color(hex: "#D4872A")
    
    /// Labels, secondary text, icons - #B5621E
    static let secondary = Color(hex: "#B5621E")
    
    /// Headings, body text, CTA button - #5C3317
    static let primary = Color(hex: "#5C3317")
    
    // MARK: - Hero Card Colors
    
    /// Hero card darker brown background - #6B3A20
    static let heroBg = Color(hex: "#6B3A20")
    
    /// Hero card circular arc stroke - #D4872A
    static let heroArc = Color(hex: "#D4872A")
    
    /// Hero card text on dark background - #F5E6C8
    static let heroText = Color(hex: "#F5E6C8")
    
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
    
    static let white = Color.white
    static let overlay = Color.black.opacity(0.5)
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
