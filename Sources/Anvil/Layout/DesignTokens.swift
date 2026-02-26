import Foundation

/// Standard spacing scale used across the Anvil UI.
///
/// Use these tokens instead of ad-hoc numeric literals to keep spacing
/// consistent in toolbars, status bars, sidebars, and other chrome areas.
enum Spacing {
    /// 4pt – extra small: tight icon-to-label pairs and inline items.
    static let xs: CGFloat = 4
    /// 8pt – small: spacing between related items within a control.
    static let sm: CGFloat = 8
    /// 12pt – medium: spacing between control groups and section padding.
    static let md: CGFloat = 12
    /// 16pt – large: spacing between distinct sections.
    static let lg: CGFloat = 16
    /// 20pt – extra large.
    static let xl: CGFloat = 20
    /// 24pt – double-extra large.
    static let xxl: CGFloat = 24
    /// 32pt – triple-extra large.
    static let xxxl: CGFloat = 32
}
