import Foundation
import Sentry

/// Single entry point for Sentry SDK lifecycle and manual capture.
///
/// `Secrets.sentryDSN` is generated from `.env` by `scripts/generate_secrets.sh`.
/// When the DSN is empty (local dev without a `.env`, or CI without secrets)
/// we skip `SentrySDK.start` entirely — no-op rather than crash.
///
/// Automatic capture once started:
///   - Unhandled NSExceptions / Swift fatal errors
///   - Mach signals (SIGSEGV, SIGABRT, …)
///   - App hangs / ANR (>2s main-thread block)
///   - Network breadcrumbs (NSURLSession)
///   - UIKit lifecycle breadcrumbs
///   - Low-memory warnings
///
/// Manual capture: `SentryService.capture(error:)` / `capture(message:)` —
/// safe to call even when the SDK was skipped (DSN absent).
@MainActor
public enum SentryService {
    /// Idempotent. Safe to call from `SoloCompassApp` `onAppear` / `init`.
    public static func bootstrap() {
        guard !didStart else { return }
        let dsn = Secrets.sentryDSN
        guard !dsn.isEmpty else {
            #if DEBUG
            print("[Sentry] DSN empty — skipping SentrySDK.start (set SENTRY_DSN in .env to enable)")
            #endif
            return
        }

        SentrySDK.start { options in
            options.dsn = dsn
            options.releaseName = Self.releaseString
            options.environment = Self.environmentString
            // Crash, hang, and signal handlers are on by default; keep them.
            options.enableAutoPerformanceTracing = true
            options.enableAppHangTracking = true
            options.enableNetworkBreadcrumbs = true
            options.enableUIViewControllerTracing = true
            // Sampling — tune up/down per traffic. 20% is a reasonable start
            // that keeps the free-tier quota usable.
            options.tracesSampleRate = 0.2
            // Don't ship PII; location/voice/chat content stays local.
            options.sendDefaultPii = false
            #if DEBUG
            options.debug = true
            options.diagnosticLevel = .warning
            #endif
        }
        didStart = true
    }

    /// Capture an error from a `catch` block or a `Result.failure` path.
    public static func capture(error: Error, context: [String: Any] = [:]) {
        guard didStart else { return }
        SentrySDK.capture(error: error) { scope in
            Self.apply(context: context, to: scope)
        }
    }

    /// Capture a non-error event (e.g. a recoverable warning worth tracking).
    public static func capture(
        message: String,
        level: SentryLevel = .warning,
        context: [String: Any] = [:]
    ) {
        guard didStart else { return }
        SentrySDK.capture(message: message) { scope in
            scope.setLevel(level)
            Self.apply(context: context, to: scope)
        }
    }

    // MARK: - Private

    private static var didStart = false

    private static func apply(context: [String: Any], to scope: Scope) {
        guard !context.isEmpty else { return }
        scope.setContext(value: context, key: "extra")
    }

    private static var releaseString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        let bundleId = Bundle.main.bundleIdentifier ?? "com.solocompass.app"
        return "\(bundleId)@\(version)+\(build)"
    }

    private static var environmentString: String {
        #if DEBUG
        return "debug"
        #else
        return "release"
        #endif
    }
}
