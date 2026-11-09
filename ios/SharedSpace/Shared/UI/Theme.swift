import SwiftUI
import UIKit

// Colours from the web prototype (light / dark pairs).

extension Color {
    static let ssBg = Color(light: 0xF3F1ED, dark: 0x141A17)
    static let ssSurface = Color(light: 0xFFFFFF, dark: 0x1D2521)
    static let ssSurface2 = Color(light: 0xEAE6DF, dark: 0x27312C)
    static let ssLine = Color(light: 0xDCD6CC, dark: 0x33403A)
    static let ssInk = Color(light: 0x1D2A25, dark: 0xEDF1EC)
    static let ssInk2 = Color(light: 0x45504A, dark: 0xC4CCC6)
    static let ssMuted = Color(light: 0x6B726D, dark: 0x98A29B)
    static let ssStage = Color(light: 0xE6E1D8, dark: 0x1A211D)

    static let ssAccent = Color(light: 0xF0B03C, dark: 0xF2B84B)
    static let ssAccentInk = Color(light: 0x4A3200, dark: 0x2B1D00)
    static let ssAccentSoft = Color(light: 0xFAEBC9, dark: 0x3A2F17)

    static let ssKeep = Color(light: 0x3B8659, dark: 0x62B584)
    static let ssKeepSoft = Color(light: 0xDCEEE2, dark: 0x1E3328)
    static let ssMove = Color(light: 0x2E8A8A, dark: 0x5FC1BF)
    static let ssMoveSoft = Color(light: 0xD8EEEE, dark: 0x1B3434)
    static let ssSend = Color(light: 0x4767CF, dark: 0x7E9AF0)
    static let ssSendSoft = Color(light: 0xE1E7FA, dark: 0x1F2946)
    static let ssLetGo = Color(light: 0xD4664A, dark: 0xEE8B6F)
    static let ssLetGoSoft = Color(light: 0xF7E0D9, dark: 0x3D2620)
    static let ssNone = Color(light: 0x9A9E98, dark: 0x7E867F)

    static let ssHost = Color(light: 0x2E5A49, dark: 0x2E5A49)
    static let ssHostSoft = Color(light: 0xDCE8E2, dark: 0x22382F)
    static let ssGuest = Color(light: 0xE7A33A, dark: 0xE7A33A)
    static let ssGuestSoft = Color(light: 0xFBE8C6, dark: 0x3A2F17)

    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    init(hex string: String) {
        let value = UInt32(string.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0xB9B2A6
        self.init(uiColor: UIColor(hex: value))
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }

    convenience init(hexString: String) {
        self.init(hex: UInt32(hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0xB9B2A6)
    }
}

// Type: the prototype pairs a serif display face with a grotesk body. On iOS we use the system's
// New York serif for headings and SF for everything else.

extension Font {
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .regular, design: .serif) }
}

extension Role {
    var color: Color { self == .host ? .ssHost : .ssGuest }
    var softColor: Color { self == .host ? .ssHostSoft : .ssGuestSoft }
}
