import Foundation
import Observation

/// Live feed backing the deep cross-compile sheet. The `EnrichmentAgent` emits
/// `CompileProgressEvent`s as it walks the loop; this store collects them so the
/// SwiftUI sheet can render the running trace and its terminal outcome.
///
/// One store instance drives one sheet presentation. `MapViewModel` owns it and
/// hands the agent a `@MainActor` callback that appends here. Because both the
/// callback and the UI live on the main actor, no synchronization is needed.
@MainActor
@Observable
public final class RecompileProgressStore {
    /// The ordered feed. Newest events are appended to the end; the sheet
    /// scrolls to follow the tail.
    public private(set) var events: [CompileProgressEvent] = []

    /// The place being compiled — drives the sheet's title. Set when a run
    /// begins so the sheet can show "Compiling <name>" before any event lands.
    public private(set) var placeName: String = ""

    /// True while the loop is still running. The sheet keeps its dismiss button
    /// disabled-looking (but never traps the user) and shows the tail spinner
    /// only while this holds.
    public private(set) var isRunning: Bool = false

    /// Set once the loop reaches a terminal stage. `nil` while running.
    /// `true` = the card was upgraded; `false` = finished with no richer result.
    public private(set) var didUpgrade: Bool?

    public init() {}

    /// Begin a fresh run for `placeName`, clearing any prior feed. Idempotent
    /// per presentation — callers reset before each recompile.
    public func begin(placeName: String) {
        self.placeName = placeName
        events = [CompileProgressEvent(stage: .start, status: .running)]
        isRunning = true
        didUpgrade = nil
    }

    /// Append a new event to the feed. This is the entry point the agent's
    /// progress callback funnels into.
    public func emit(_ event: CompileProgressEvent) {
        events.append(event)
    }

    /// Convenience wrapper matching the agent callback signature.
    public func emit(_ stage: CompileProgressEvent.Stage,
                     _ status: CompileProgressEvent.Status,
                     _ detail: String = "") {
        events.append(CompileProgressEvent(stage: stage, status: status, detail: detail))
    }

    /// Mark the run finished. Appends a terminal `done`/`failed` line and flips
    /// `isRunning` off so the sheet stops its tail spinner.
    public func finish(upgraded: Bool, detail: String = "") {
        // Flip the leading `start` row from running → success now that the loop
        // has terminated, so a completed feed shows no orphaned spinner up top.
        if let first = events.first, first.stage == .start, first.status == .running {
            events[0].status = .success
        }
        events.append(
            CompileProgressEvent(
                stage: upgraded ? .done : .failed,
                status: upgraded ? .success : .failure,
                detail: detail
            )
        )
        didUpgrade = upgraded
        isRunning = false
    }
}
