import SwiftUI

struct MivoColors {
    static let background = Color(hex: "#E7D6C4")
    static let surface = Color(hex: "#DCC6AF")
    static let card = Color(hex: "#F3F3F3")
    static let border = Color(hex: "#E0E0E0")

    static let accent = Color(hex: "#C97942")
    static let accentLight = Color(hex: "#A97B5B")
    static let accentMuted = Color(hex: "#F3EBE3")

    static let textPrimary = Color(hex: "#2E2E2E")
    static let textSecondary = Color(hex: "#9C8573")
    static let textMuted = Color(hex: "#9E9E9E")

    static let brand = Color(hex: "#4A2E1F")

    static let timerGreen = Color(hex: "#A97B5B")
    static let timerOrange = Color(hex: "#C97942")
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
