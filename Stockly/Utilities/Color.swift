import Foundation
import SwiftUI
// MARK: - Design Tokens

extension Color {
    static let bg            = Color(red: 0.06, green: 0.06, blue: 0.08)
    static let surface       = Color(red: 0.11, green: 0.11, blue: 0.14)
    static let surface2      = Color(red: 0.15, green: 0.15, blue: 0.18)
    static let border        = Color.white.opacity(0.07)
    static let textPrimary   = Color.white
    static let textSecondary = Color(white: 0.90)
    static let textTertiary  = Color(white: 0.90)  // raised from 0.35 for contrast
    static let accent        = Color(red: 0.55, green: 0.45, blue: 1.0) // brighter for WCAG AA
    static let gain          = Color(red: 0.18, green: 0.78, blue: 0.44)
    static let loss          = Color(red: 0.95, green: 0.32, blue: 0.32)
}
