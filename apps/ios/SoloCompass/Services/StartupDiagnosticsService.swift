import Foundation
import Speech
import CoreLocation
import UserNotifications

/// Startup self-diagnostics — runs once per calendar day after the map's first
/// paint (see `CompassMapContentView.onAppear`), surfaces findings through the
/// Solo Agent bubble queue, and lets the user tap into ChatSheet with the
/// finding summary seeded as the first user turn.
///
/// Design notes:
/// - No network calls. All checks are local reads of key presence + system
///   authorization state. A missing Anthropic key is a *warning*, not an
///   error — the app degrades to Solo-Score ranking (see `AIService`).
/// - CN vs. overseas branching is inferred from `LanguageService.current`
///   (same rule the rest of the codebase uses). Only CN users get the Amap
///   key check; overseas users trust MapKit which needs no key.
/// - Once-per-day caching: `UserDefaults` key stores the last-run day; a
///   fresh run only fires when the day flips.
@Observable
@MainActor
public final class StartupDiagnosticsService {

    // MARK: - Types

    public enum Check: String, Sendable, Codable {
        case anthropicKey
        case amapKey
        case locationAuth
        case micAuth
        case notificationAuth
        case userPrefs
        case seedData
    }

    public enum Severity: String, Sendable, Codable {
        case info
        case warn
        case error
    }

    public struct Finding: Identifiable, Sendable, Codable, Equatable {
        public let id: UUID
        public let check: Check
        public let severity: Severity
        /// Short bubble title, already localized.
        public let title: String
        /// Full explanation for the LLM / diagnostics sheet, already localized.
        public let detail: String
        /// One-line fix hint for the LLM prompt seed.
        public let suggestedFix: String

        public init(
            id: UUID = UUID(),
            check: Check,
            severity: Severity,
            title: String,
            detail: String,
            suggestedFix: String
        ) {
            self.id = id
            self.check = check
            self.severity = severity
            self.title = title
            self.detail = detail
            self.suggestedFix = suggestedFix
        }
    }

    // MARK: - Observable state

    public private(set) var lastRunFindings: [Finding] = []
    public private(set) var lastRunAt: Date?

    // MARK: - Dependencies

    private let preferences: UserPreferences
    private let locationService: LocationService
    private let experienceService: ExperienceService?
    private let languageService: LanguageService
    private let calendar: Calendar
    private let now: () -> Date

    /// UserDefaults key holding the yyyy-MM-dd string of the last run.
    private static let lastRunDayKey = "solo.diagnostics.lastRunDay"

    // MARK: - Init

    public init(
        preferences: UserPreferences,
        locationService: LocationService,
        experienceService: ExperienceService? = nil,
        languageService: LanguageService = LanguageService.shared,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.preferences = preferences
        self.locationService = locationService
        self.experienceService = experienceService
        self.languageService = languageService
        self.calendar = calendar
        self.now = now
    }

    // MARK: - Public entry points

    /// Runs the full check suite only if today's date is newer than the cached
    /// last-run day. Returns the resulting findings (possibly empty). Callers
    /// use the return value to decide whether to enqueue a bubble.
    @discardableResult
    public func runIfNeeded() async -> [Finding] {
        if hasRunToday() {
            return lastRunFindings
        }
        return await runAll()
    }

    /// Runs every check unconditionally and caches the result.
    @discardableResult
    public func runAll() async -> [Finding] {
        var out: [Finding] = []
        out.append(contentsOf: checkApiKeys())
        out.append(contentsOf: await checkAuthorizations())
        out.append(contentsOf: checkUserData())
        lastRunFindings = out
        lastRunAt = now()
        markRunToday()
        return out
    }

    /// Test-only: clears the once-per-day cache so `runIfNeeded()` fires again.
    public func resetDailyCache() {
        UserDefaults.standard.removeObject(forKey: Self.lastRunDayKey)
    }

    /// Test / screenshot-harness only: seeds `lastRunFindings` directly so
    /// callers can drive the bubble UI without waiting for a real run. Used
    /// by `-forceDiagnosticsBubble` launch arg in `CompassMapView`.
    public func injectFindingsForTesting(_ findings: [Finding]) {
        lastRunFindings = findings
        lastRunAt = now()
    }

    // MARK: - API keys

    private func checkApiKeys() -> [Finding] {
        var out: [Finding] = []

        // Anthropic / DeepSeek key — a missing key downgrades AI to Solo-Score
        // ranking, so it's a warning, not a hard error.
        if Secrets.resolvedDeepSeekApiKey.isEmpty {
            out.append(Finding(
                check: .anthropicKey,
                severity: .warn,
                title: L.title("diagnostics.anthropic.missing.title", "AI 大脑没接上"),
                detail: L.detail("diagnostics.anthropic.missing.detail",
                    "没检测到 AI API key，Solo 现在只会用离线排序推荐地点，不会跟你自然对话。"),
                suggestedFix: L.fix("diagnostics.anthropic.missing.fix",
                    "去 设置 → AI Provider 填一个 Anthropic 或 DeepSeek 的 key。")
            ))
        }

        // Amap key — only relevant when the app is running in Chinese.
        // Overseas users rely on MapKit which needs no key.
        if isCNLocale() && Secrets.resolvedAmapKey.isEmpty {
            out.append(Finding(
                check: .amapKey,
                severity: .warn,
                title: L.title("diagnostics.amap.missing.title", "高德地图没接上"),
                detail: L.detail("diagnostics.amap.missing.detail",
                    "在中国区域，Solo 优先用高德查周边。当前没检测到高德 key，会回退到 Overpass 公共数据，结果可能不全。"),
                suggestedFix: L.fix("diagnostics.amap.missing.fix",
                    "在设置或环境变量里配一个 AMAP_API_KEY，再重启 App。")
            ))
        }

        return out
    }

    // MARK: - Authorizations

    private func checkAuthorizations() async -> [Finding] {
        var out: [Finding] = []

        #if DEBUG
        // e2e rubric harness (scripts/user-story-rubric/run.sh): if the caller
        // asked us to skip the CoreLocation prompt we also must not surface a
        // "location isn't authorized yet" diagnostic — otherwise the banner
        // covers the very content the harness is trying to screenshot.
        if ProcessInfo.processInfo.arguments.contains("-uiTestBypassLocationPrompt") {
            return out
        }
        #endif

        switch locationService.authorizationStatus {
        case .denied, .restricted:
            out.append(Finding(
                check: .locationAuth,
                severity: .error,
                title: L.title("diagnostics.location.denied.title", "定位被拒了"),
                detail: L.detail("diagnostics.location.denied.detail",
                    "地图不知道你在哪，附近推荐、Now 排序、Live Activity 都会失效。"),
                suggestedFix: L.fix("diagnostics.location.denied.fix",
                    "去 系统设置 → Solo Compass → 位置 → 使用期间。")
            ))
        case .notDetermined:
            out.append(Finding(
                check: .locationAuth,
                severity: .info,
                title: L.title("diagnostics.location.pending.title", "还没授权定位"),
                detail: L.detail("diagnostics.location.pending.detail",
                    "点一下右下角 Solo 或者定位按钮，我会请求一次位置授权。"),
                suggestedFix: L.fix("diagnostics.location.pending.fix",
                    "触发一次定位授权弹窗。")
            ))
        default:
            break
        }

        switch SFSpeechRecognizer.authorizationStatus() {
        case .denied, .restricted:
            out.append(Finding(
                check: .micAuth,
                severity: .warn,
                title: L.title("diagnostics.mic.denied.title", "语音识别被关了"),
                detail: L.detail("diagnostics.mic.denied.detail",
                    "长按 Solo 说话没法转成文字，只能打字聊。"),
                suggestedFix: L.fix("diagnostics.mic.denied.fix",
                    "去 系统设置 → Solo Compass → 语音识别 打开。")
            ))
        default:
            break
        }

        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .denied:
            out.append(Finding(
                check: .notificationAuth,
                severity: .info,
                title: L.title("diagnostics.notification.denied.title", "通知被拒了"),
                detail: L.detail("diagnostics.notification.denied.detail",
                    "拿不到孤独时段提醒、灵动岛胶囊、每月洞察推送。"),
                suggestedFix: L.fix("diagnostics.notification.denied.fix",
                    "去 系统设置 → Solo Compass → 通知 打开。")
            ))
        default:
            break
        }

        return out
    }

    // MARK: - User data & seed

    private func checkUserData() -> [Finding] {
        var out: [Finding] = []

        if !preferences.hasCompletedOnboarding {
            out.append(Finding(
                check: .userPrefs,
                severity: .info,
                title: L.title("diagnostics.onboarding.incomplete.title", "onboarding 还没走完"),
                detail: L.detail("diagnostics.onboarding.incomplete.detail",
                    "没有 vibe / 城市 / 品味偏好，推荐会退化成通用榜。"),
                suggestedFix: L.fix("diagnostics.onboarding.incomplete.fix",
                    "回到 onboarding 把三步选完。")
            ))
        }

        // Seed data — surfaced only if the ExperienceService failed to load
        // even the hardcoded fallback. Should be impossible in practice, but
        // catches a broken app bundle.
        if let svc = experienceService, svc.allExperiences.isEmpty {
            out.append(Finding(
                check: .seedData,
                severity: .error,
                title: L.title("diagnostics.seed.empty.title", "地点数据是空的"),
                detail: L.detail("diagnostics.seed.empty.detail",
                    "seed_experiences.json 没加载出来,SwiftData 里也没历史数据。地图会是空的。"),
                suggestedFix: L.fix("diagnostics.seed.empty.fix",
                    "重装 App，或者报 bug 给我。")
            ))
        }

        return out
    }

    // MARK: - Helpers

    private func isCNLocale() -> Bool {
        languageService.current == .simplifiedChinese
    }

    private func hasRunToday() -> Bool {
        let stored = UserDefaults.standard.string(forKey: Self.lastRunDayKey) ?? ""
        return stored == todayKey()
    }

    private func markRunToday() {
        UserDefaults.standard.set(todayKey(), forKey: Self.lastRunDayKey)
    }

    private func todayKey() -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: now())
        return String(format: "%04d-%02d-%02d",
                      comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
    }

    // MARK: - Diagnostic prompt for Chat seeding

    /// Renders the current findings into a first-person user message that
    /// gets sent as the first turn when the user taps a bubble into
    /// ChatSheet. The AI's first reply then explains each finding in
    /// natural language.
    ///
    /// UX layering:
    /// - Machine-readable payload inside a `<solo:diagnostics>` block —
    ///   the LLM sees findings as structured JSON so its answer can cite
    ///   each check by name / severity / suggested fix.
    /// - A short natural request follows the block — this is what the LLM
    ///   is being asked to do ("explain and fix").
    /// - The UI's `ChatSheet.sanitizeForDisplay` recognizes the marker and
    ///   replaces the whole message with a `DiagnosticsRequestCard` (a
    ///   compact "启动体检结果" pill list + one-line ask) so the traveler
    ///   never sees the raw dump.
    public func chatSeedPrompt(for findings: [Finding]) -> String? {
        guard !findings.isEmpty else { return nil }
        // Compact payload: no prettyPrinted (saves indentation + newlines),
        // no `detail` field (the UI card only shows title + fix; the LLM
        // gets enough signal from those two). Keeps the seed prompt under
        // the orchestrator's 500-char cap for up to ~5 findings.
        let payload = findings.map { f in
            [
                "check": f.check.rawValue,
                "severity": f.severity.rawValue,
                "title": f.title,
                "fix": f.suggestedFix
            ]
        }
        let jsonData = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        let json = String(data: jsonData, encoding: .utf8) ?? "[]"
        let ask = NSLocalizedString(
            "diagnostics.seed.ask",
            value: "解释每条并告诉我怎么修。",
            comment: "The natural-language part of the diagnostics seed message"
        )
        return "<solo:diagnostics>\(json)</solo:diagnostics>\n\(ask)"
    }
}

// MARK: - Localization helper

/// Tiny wrapper so the check bodies stay readable. `value:` is the fallback
/// used when the key isn't in Localizable.strings — makes CI runs on an
/// un-localized dev build still ship sensible copy.
private enum L {
    static func title(_ key: String, _ fallback: String) -> String {
        NSLocalizedString(key, value: fallback, comment: "Startup diagnostics bubble title")
    }
    static func detail(_ key: String, _ fallback: String) -> String {
        NSLocalizedString(key, value: fallback, comment: "Startup diagnostics finding detail")
    }
    static func fix(_ key: String, _ fallback: String) -> String {
        NSLocalizedString(key, value: fallback, comment: "Startup diagnostics fix hint")
    }
}
