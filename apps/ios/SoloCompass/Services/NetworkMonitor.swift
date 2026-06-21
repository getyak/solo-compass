import Foundation
import Network
import Observation

/// Publishes live network reachability via NWPathMonitor.
@Observable
@MainActor
public final class NetworkMonitor {
    public static let shared = NetworkMonitor()

    public private(set) var isConnected: Bool = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.solocompass.network-monitor")

    /// Debounce window for `isConnected` updates. Airplane-mode flicks +
    /// Wi-Fi/cell handover can generate 3-5 path events in <1s; without
    /// debouncing every `.onChange(of:isConnected)` listener (OfflineBanner
    /// retry timer, MapViewModel refresh) re-fires for each, sometimes
    /// stacking duplicate fetches. 350ms covers normal handovers while
    /// staying snappy enough that a real outage is still flagged quickly.
    private static let debounceWindowMs: Int = 350

    /// Latest path-handler result, waiting to be committed once the debounce
    /// window expires. Accessed only on `queue`.
    nonisolated(unsafe) private var pendingConnected: Bool = true
    /// Token of the in-flight `asyncAfter` so a newer event can cancel it.
    nonisolated(unsafe) private var pendingDispatch: DispatchWorkItem?

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let connected = path.status == .satisfied
            self.queue.async { [weak self] in
                guard let self else { return }
                self.pendingConnected = connected
                self.pendingDispatch?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    let final = self.pendingConnected
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        if self.isConnected != final { self.isConnected = final }
                    }
                }
                self.pendingDispatch = work
                self.queue.asyncAfter(
                    deadline: .now() + .milliseconds(Self.debounceWindowMs),
                    execute: work
                )
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    #if DEBUG
    /// Test-only override so unit tests can drive callers that branch on
    /// `isConnected` (e.g. `MapViewModel.classifyFailure`) without standing
    /// up a real `NWPathMonitor`. Production code MUST NOT call this — the
    /// production path is `pathUpdateHandler` above.
    func _setConnectedForTesting(_ value: Bool) {
        isConnected = value
    }
    #endif
}
