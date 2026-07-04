import Foundation

/// Single choke-point for "what time is it right now?" across the app.
///
/// Production reads the device wall clock. The DEBUG build recognises a
/// `-scenarioHour <int>` launch argument so the rubric screenshot harness can
/// pin the app to a persona's local hour (e.g. hour=12 for the SZX lunch
/// story) without the harness's real clock (which may be midnight when tests
/// run overnight) leaking into `bottomInfoText`, `isBestNow`,
/// `nextBestExperience`, etc.
///
/// The override only pins hour+minute of *today* — day/month/year still come
/// from `Date()`, so timer arithmetic and expiry logic stay correct.
public enum AppClock {
    public static func now() -> Date {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let idx = args.firstIndex(of: "-scenarioHour"),
           idx + 1 < args.count,
           let hour = Int(args[idx + 1]),
           (0...23).contains(hour) {
            var components = Calendar.current.dateComponents(
                [.year, .month, .day], from: Date()
            )
            components.hour = hour
            components.minute = 0
            if let d = Calendar.current.date(from: components) { return d }
        }
        #endif
        return Date()
    }
}
