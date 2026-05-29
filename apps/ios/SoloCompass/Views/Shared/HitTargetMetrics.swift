import CoreGraphics

/// Shared accessibility layout metrics. US-019.
///
/// Apple's Human Interface Guidelines require interactive controls to expose a
/// hit area of at least 44×44 pt for VoiceOver / Switch Control / general
/// touch reliability. Several controls render a smaller *visible* element
/// (e.g. a 36×36 filter chip, a 32×32 favorite heart, a caption-sized banner
/// dismiss button); they wrap their label in
/// `.frame(minWidth: HitTargetMetrics.minimum, minHeight: HitTargetMetrics.minimum)`
/// plus `.contentShape(Rectangle())` to expand the tappable region without
/// changing the visual appearance.
enum HitTargetMetrics {
    /// Minimum hit target dimension per Apple HIG (44×44 pt).
    static let minimum: CGFloat = 44
}
