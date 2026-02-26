import AppKit
import SwiftTerm

/// A terminal color theme defining background, foreground, cursor, selection,
/// and the 16 ANSI colors (8 normal + 8 bright).
struct TerminalTheme: Identifiable, Equatable {
    let id: String
    let name: String
    let background: NSColor
    let foreground: NSColor
    let cursor: NSColor
    let selection: NSColor
    /// 16 ANSI colors: indices 0-7 are normal, 8-15 are bright.
    let ansiColors: [NSColor]

    /// Convert ansiColors to SwiftTerm Color array for `installColors`.
    var swiftTermColors: [SwiftTerm.Color] {
        ansiColors.map { nsColor in
            let c = nsColor.usingColorSpace(.sRGB) ?? nsColor
            return SwiftTerm.Color(
                red: UInt16(c.redComponent * 255),
                green: UInt16(c.greenComponent * 255),
                blue: UInt16(c.blueComponent * 255)
            )
        }
    }

    static func == (lhs: TerminalTheme, rhs: TerminalTheme) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - Lookup

    static let builtIn: [TerminalTheme] = [
        defaultDark, oneDark, dracula, solarizedDark, nord, githubDark
    ]

    static func theme(forID id: String) -> TerminalTheme {
        builtIn.first { $0.id == id } ?? defaultDark
    }

    // MARK: - Hex Helper

    private static func hex(_ value: UInt32) -> NSColor {
        let r = CGFloat((value >> 16) & 0xFF) / 255.0
        let g = CGFloat((value >> 8) & 0xFF) / 255.0
        let b = CGFloat(value & 0xFF) / 255.0
        return NSColor(red: r, green: g, blue: b, alpha: 1.0)
    }

    private static func hexA(_ value: UInt32, alpha: CGFloat) -> NSColor {
        let r = CGFloat((value >> 16) & 0xFF) / 255.0
        let g = CGFloat((value >> 8) & 0xFF) / 255.0
        let b = CGFloat(value & 0xFF) / 255.0
        return NSColor(red: r, green: g, blue: b, alpha: alpha)
    }

    private static func makeAnsi(_ hexValues: [UInt32]) -> [NSColor] {
        hexValues.map { hex($0) }
    }
}

// MARK: - Built-in Themes (split into extension to avoid type-checker limits)

extension TerminalTheme {

    static let defaultDark: TerminalTheme = {
        let ansi = makeAnsi([
            0x2E3436, 0xCC0000, 0x4E9A06, 0xC4A000,
            0x3465A4, 0x75507B, 0x06989A, 0xD3D7CF,
            0x555753, 0xEF2929, 0x8AE234, 0xFCE94F,
            0x729FCF, 0xAD7FA8, 0x34E2E2, 0xEEEEEC,
        ])
        return TerminalTheme(
            id: "default-dark", name: "Default Dark",
            background: NSColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1.0),
            foreground: NSColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1.0),
            cursor: NSColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1.0),
            selection: hexA(0x4D6699, alpha: 0.5),
            ansiColors: ansi
        )
    }()

    static let oneDark: TerminalTheme = {
        let ansi = makeAnsi([
            0x5C6370, 0xE06C75, 0x98C379, 0xE5C07B,
            0x61AFEF, 0xC678DD, 0x56B6C2, 0xABB2BF,
            0x5C6370, 0xF06B7E, 0xAED78A, 0xF2D478,
            0x78AAED, 0xD98FEE, 0x6ED4D9, 0xCDD1DB,
        ])
        return TerminalTheme(
            id: "one-dark", name: "One Dark",
            background: hex(0x282C34),
            foreground: hex(0xABB2BF),
            cursor: hex(0x548BD4),
            selection: hex(0x3E4452),
            ansiColors: ansi
        )
    }()

    static let dracula: TerminalTheme = {
        let ansi = makeAnsi([
            0x44475A, 0xFF5555, 0x50FA7B, 0xF1FA8C,
            0xBD93F9, 0xFF79C6, 0x8BE9FD, 0xF8F8F2,
            0x414558, 0xFF6B6B, 0x69FF94, 0xF8FFA6,
            0xD2AEFF, 0xFF92D0, 0xA4F4FC, 0xFFFFFF,
        ])
        return TerminalTheme(
            id: "dracula", name: "Dracula",
            background: hex(0x282A36),
            foreground: hex(0xF8F8F2),
            cursor: hex(0xF8F8F2),
            selection: hex(0x44475A),
            ansiColors: ansi
        )
    }()

    static let solarizedDark: TerminalTheme = {
        let ansi = makeAnsi([
            0x073642, 0xDC322F, 0x859900, 0xB58900,
            0x268BD2, 0xD33682, 0x2AA198, 0xEEE8D5,
            0x586E75, 0xCB4B16, 0x859900, 0xB58900,
            0x839496, 0x6C71C4, 0x93A1A1, 0xFDF6E3,
        ])
        return TerminalTheme(
            id: "solarized-dark", name: "Solarized Dark",
            background: hex(0x002B36),
            foreground: hex(0x839496),
            cursor: hex(0x839496),
            selection: hex(0x073642),
            ansiColors: ansi
        )
    }()

    static let nord: TerminalTheme = {
        let ansi = makeAnsi([
            0x4C566A, 0xBF616A, 0xA3BE8C, 0xEBCB8B,
            0x81A1C1, 0xB48EAD, 0x88C0D0, 0xE5E9F0,
            0x4C566A, 0xBF616A, 0xA3BE8C, 0xEBCB8B,
            0x81A1C1, 0xB48EAD, 0x8FBCBB, 0xECEFF4,
        ])
        return TerminalTheme(
            id: "nord", name: "Nord",
            background: hex(0x2E3440),
            foreground: hex(0xD8DEE9),
            cursor: hex(0xD8DEE9),
            selection: hex(0x434C5E),
            ansiColors: ansi
        )
    }()

    static let githubDark: TerminalTheme = {
        let ansi = makeAnsi([
            0x484F58, 0xFF7B72, 0x3FB950, 0xD29922,
            0x58A6FF, 0xBC8CFF, 0x39C5CF, 0xE6EDF3,
            0x6E7681, 0xFF9589, 0x56E66D, 0xE3C959,
            0x79C0FF, 0xD2A8FF, 0x56D4DD, 0xFFFFFF,
        ])
        return TerminalTheme(
            id: "github-dark", name: "GitHub Dark",
            background: hex(0x0D1117),
            foreground: hex(0xE6EDF3),
            cursor: hex(0x548BD4),
            selection: hex(0x30446B),
            ansiColors: ansi
        )
    }()
}
