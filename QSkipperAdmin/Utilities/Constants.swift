import SwiftUI
import UIKit

// MARK: - App Colors
struct AppColors {
    static let primaryGreen = Color(uiColor: UIColor(hex: "#34C759") ?? .systemGreen)
    static let darkGray = Color(uiColor: UIColor(hex: "#333333") ?? .darkGray)
    static let lightGray = Color(uiColor: UIColor(hex: "#F2F2F2") ?? .systemGray5)
    static let mediumGray = Color(uiColor: UIColor(hex: "#999999") ?? .systemGray)
    static let errorRed = Color(uiColor: UIColor(hex: "#FF3B30") ?? .systemRed)
    static let backgroundWhite = Color.white
    static let background = Color(uiColor: UIColor(hex: "#F9F9F9") ?? .systemBackground)
}

// MARK: - App Fonts
struct AppFonts {
    static let title = Font.system(size: 24, weight: .bold)
    static let subtitle = Font.system(size: 18, weight: .semibold)
    static let sectionTitle = Font.system(size: 18, weight: .bold)
    static let body = Font.system(size: 16, weight: .regular)
    static let caption = Font.system(size: 14, weight: .regular)
    static let buttonText = Font.system(size: 16, weight: .bold)
}

// MARK: - App Constants
struct AppConstants {
    static let appName = "QSkipper Admin"
    static let defaultAnimationDuration = 0.3
}

// MARK: - Color Extension for Hex (Now deprecated in favor of UIColor extension)
// This function is kept for backward compatibility but shouldn't be used for new code
extension Color {
    @available(*, deprecated, message: "Use UIColor(hex:) and then Color(uiColor:) instead")
    init?(hex: String) {
        guard let uiColor = UIColor(hex: hex) else { return nil }
        self.init(uiColor: uiColor)
    }
} 