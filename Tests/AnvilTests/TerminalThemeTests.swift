import XCTest
@testable import Anvil

final class TerminalThemeTests: XCTestCase {

    // MARK: - Helpers

    /// Relative luminance per WCAG 2.1 formula.
    private func relativeLuminance(r: CGFloat, g: CGFloat, b: CGFloat) -> CGFloat {
        func linearize(_ c: CGFloat) -> CGFloat {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b)
    }

    private func contrastRatio(between color1: NSColor, and color2: NSColor) -> CGFloat {
        let c1 = color1.usingColorSpace(.sRGB) ?? color1
        let c2 = color2.usingColorSpace(.sRGB) ?? color2
        let l1 = relativeLuminance(r: c1.redComponent, g: c1.greenComponent, b: c1.blueComponent)
        let l2 = relativeLuminance(r: c2.redComponent, g: c2.greenComponent, b: c2.blueComponent)
        let lighter = max(l1, l2)
        let darker = min(l1, l2)
        return (lighter + 0.05) / (darker + 0.05)
    }

    // MARK: - Visibility Tests

    /// Verifies that no ANSI color in any built-in theme is invisible
    /// (contrast ratio > 1:1) against the theme background.
    func testNoAnsiColorIsIdenticalToBackground() {
        for theme in TerminalTheme.builtIn {
            for (index, color) in theme.ansiColors.enumerated() {
                let ratio = contrastRatio(between: color, and: theme.background)
                XCTAssertGreaterThan(
                    ratio, 1.0,
                    "Theme '\(theme.name)' ANSI[\(index)] is identical to background (invisible)"
                )
            }
        }
    }

    /// Verifies that the theme foreground color has adequate contrast (≥ 3:1)
    /// against the background.
    func testForegroundHasAdequateContrastAgainstBackground() {
        for theme in TerminalTheme.builtIn {
            let ratio = contrastRatio(between: theme.foreground, and: theme.background)
            XCTAssertGreaterThanOrEqual(
                ratio, 3.0,
                "Theme '\(theme.name)' foreground has insufficient contrast (\(String(format: "%.2f", ratio)):1)"
            )
        }
    }

    /// Verifies specific previously-broken colors in solarized-dark.
    func testSolarizedDarkBrightBlackIsNotBackground() {
        let theme = TerminalTheme.solarizedDark
        let brightBlack = theme.ansiColors[8] // was 0x002B36 == background
        let ratio = contrastRatio(between: brightBlack, and: theme.background)
        XCTAssertGreaterThan(ratio, 1.0, "solarized-dark bright-black must not be same as background")
    }
}
