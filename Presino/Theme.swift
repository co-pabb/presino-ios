import SwiftUI
import UIKit

/// اعداد فارسی (مثل fa() اپ اندروید)
enum Fa {
    static func digits(_ s: String) -> String {
        let map: [Character: Character] = ["0": "۰", "1": "۱", "2": "۲", "3": "۳", "4": "۴", "5": "۵", "6": "۶", "7": "۷", "8": "۸", "9": "۹"]
        return String(s.map { map[$0] ?? $0 })
    }

    static func n(_ v: Int) -> String { return digits(String(v)) }
}

/// تم روشن/تیره‌ی برنامه (دکمه‌ی ماه/خورشید بالای صفحه‌ی اول، مثل وب)
enum ThemeStore {
    private static let key = "theme.mode"

    /// "" = مثل سیستم، "light"، "dark"
    static var mode: String {
        get { return UserDefaults.standard.string(forKey: key) ?? "" }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            apply()
        }
    }

    static var style: UIUserInterfaceStyle {
        switch mode {
        case "light": return .light
        case "dark": return .dark
        default: return .unspecified
        }
    }

    static func apply() {
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene else { continue }
            for w in ws.windows { w.overrideUserInterfaceStyle = style }
        }
        for w in UIApplication.shared.windows { w.overrideUserInterfaceStyle = style }
    }

    static func toggle(currentlyDark: Bool) {
        mode = currentlyDark ? "light" : "dark"
    }
}

/// پالت nx داشبورد مدیر وب (همان مقدارهای StaffMap.kt اندروید)
struct Nx {
    let dark: Bool

    private func c(_ hex: UInt32, _ a: Double = 1) -> Color {
        return Color(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: a)
    }

    var bg: Color { return dark ? c(0x070C13) : c(0xF1F4F8) }
    var card: Color { return dark ? c(0x0A1322) : .white }
    var card2: Color { return dark ? c(0x0E1A2E) : c(0xF1F5FB) }
    var border: Color { return dark ? c(0x16263F) : c(0xDBE4F0) }
    var borderStrong: Color { return dark ? c(0x2A4670) : c(0xB9C9DF) }
    var text: Color { return dark ? c(0xE6EEFB) : c(0x0B1530) }
    var muted: Color { return dark ? c(0x8197B5) : c(0x5B6B86) }
    var blue: Color { return dark ? c(0x3B82F6) : c(0x2563EB) }
    var blueDark: Color { return c(0x1D4ED8) }
    var sky: Color { return dark ? c(0x60A5FA) : c(0x3B82F6) }
    var green: Color { return dark ? c(0x34D399) : c(0x16A34A) }
    var red: Color { return dark ? c(0xF87171) : c(0xDC2626) }
    var orange: Color { return dark ? c(0xFBBF24) : c(0xD97706) }

    func status(_ k: String) -> Color {
        switch k {
        case "present": return c(0x34D399)
        case "absent": return c(0xF87171)
        case "leave": return c(0xFBBF24)
        case "mission": return c(0x60A5FA)
        default: return c(0x94A3B8)
        }
    }
}

/// وضعیت‌های پنج‌گانه‌ی پرسنل (کلید، برچسب)
let StatusKeys: [(String, String)] = [("present", "حاضر در محل"), ("out", "خروج‌زده"), ("absent", "غایب"), ("leave", "مرخصی"), ("mission", "ماموریت")]

/// تبدیل رنگ‌ماتریس CSS تم تاریک نقشه‌ی وب: invert(1) hue-rotate(180deg) brightness(.82) contrast(.92) saturate(.55)
enum DarkTile {
    /// ماتریس ۳×۴ (سه سطر: R,G,B؛ چهار ستون: ضرایب R,G,B و جابه‌جایی)
    static let matrix: [Double] = {
        func mul(_ b: [Double], _ a: [Double]) -> [Double] {
            var r = [Double](repeating: 0, count: 12)
            for i in 0..<3 {
                for j in 0..<3 {
                    var s = 0.0
                    for k in 0..<3 { s += b[i * 4 + k] * a[k * 4 + j] }
                    r[i * 4 + j] = s
                }
                var t = b[i * 4 + 3]
                for k in 0..<3 { t += b[i * 4 + k] * a[k * 4 + 3] }
                r[i * 4 + 3] = t
            }
            return r
        }
        let invert: [Double] = [-1, 0, 0, 1, 0, -1, 0, 1, 0, 0, -1, 1]
        let hc = -1.0, hs = 0.0
        let hue: [Double] = [
            0.213 + hc * 0.787 - hs * 0.213, 0.715 - hc * 0.715 - hs * 0.715, 0.072 - hc * 0.072 + hs * 0.928, 0,
            0.213 - hc * 0.213 + hs * 0.143, 0.715 + hc * 0.285 + hs * 0.140, 0.072 - hc * 0.072 - hs * 0.283, 0,
            0.213 - hc * 0.213 - hs * 0.787, 0.715 - hc * 0.715 + hs * 0.715, 0.072 + hc * 0.928 + hs * 0.072, 0]
        let b = 0.82
        let bright: [Double] = [b, 0, 0, 0, 0, b, 0, 0, 0, 0, b, 0]
        let ct = 0.92, ci = 0.5 - 0.5 * ct
        let contrast: [Double] = [ct, 0, 0, ci, 0, ct, 0, ci, 0, 0, ct, ci]
        let s = 0.55
        let sat: [Double] = [
            0.213 + 0.787 * s, 0.715 - 0.715 * s, 0.072 - 0.072 * s, 0,
            0.213 - 0.213 * s, 0.715 + 0.285 * s, 0.072 - 0.072 * s, 0,
            0.213 - 0.213 * s, 0.715 - 0.715 * s, 0.072 + 0.928 * s, 0]
        return mul(sat, mul(contrast, mul(bright, mul(hue, invert))))
    }()
}

/// رنگ آواتار هر نفر از نامش (CRC32 % 360 مثل nameHue اندروید/وب)
func nameHue(_ name: String) -> Double {
    var crc: UInt32 = 0xFFFF_FFFF
    for byte in Array(name.utf8) {
        crc ^= UInt32(byte)
        for _ in 0..<8 { crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
    }
    crc = ~crc
    return Double(crc % 360)
}
