import SwiftUI
import UIKit

/// Exact color palette from desktop Hebdo (ui/style.css) for native Light & Dark parity.
enum HebdoTheme {
    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            let r = CGFloat((hex >> 16) & 0xFF) / 255.0
            let g = CGFloat((hex >> 8) & 0xFF) / 255.0
            let b = CGFloat(hex & 0xFF) / 255.0
            return UIColor(red: r, green: g, blue: b, alpha: 1.0)
        })
    }

    static let bg        = dynamic(light: 0xFFFFFF, dark: 0x191919)
    static let side      = dynamic(light: 0xF7F7F5, dark: 0x202020)
    static let text      = dynamic(light: 0x37352F, dark: 0xE6E6E4)
    static let muted     = dynamic(light: 0x787774, dark: 0x9B9B98)
    static let faint     = dynamic(light: 0xA5A29B, dark: 0x6B6B68)
    static let border    = dynamic(light: 0xE3E2DF, dark: 0x343434)
    static let codeBg    = dynamic(light: 0xF6F5F4, dark: 0x262626)
    static let calloutBg = dynamic(light: 0xF1F1EF, dark: 0x252525)
    static let active    = dynamic(light: 0xECECE9, dark: 0x2E2E2E)
    static let accent    = Color(red: 0x23 / 255.0, green: 0x83 / 255.0, blue: 0xE2 / 255.0)
}
