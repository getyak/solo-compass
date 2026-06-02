import Foundation

// MARK: - SupabaseRouteCompanionRemote

/// `RouteCompanionRemote` backed by Supabase (PostgREST).
///
/// Mirrors the semantics of `LocalRouteCompanionRemote` but persists every
/// mutation to the `routes` and `join_requests` tables instead of SwiftData.
/// Resolved by `makeRouteCompanionRemote` when `FF_BACKEND_SYNC` is true.
///
/// All network access is funneled through `SupabaseClient`, which itself gates
/// every call behind `FeatureFlags.backendSync` (returns empty / success when
/// the flag is off — local-first invariant, PRD G7). On top of that this type
/// honours `FeatureFlags.companion`: when companion mode is off every method is
/// a no-op (matching `CompanionService`).
///
/// Concurrency: the class is `Sendable` (protocol requirement) and is *not*
/// `@MainActor`. The injected `SupabaseClientProtocol` and
/// `DeviceIdentityService` are `@MainActor`-isolated, so all access to them is
/// hopped onto the main actor explicitly via `onMain`.
public final class SupabaseRouteCompanionRemote: RouteCompanionRemote {

    /// Reference to the `@MainActor` Supabase client. Captured here and only
    /// ever touched inside `onMain` (i.e. on the main actor), which is why this
    /// `Sendable` type can safely hold a main-actor `AnyObject`.
    private let client: any SupabaseClientProtocol

    @MainActor
    public init(client: any SupabaseClientProtocol = SupabaseClient.shared) {
        self.client = client
    }

    // MARK: - Table names (snake_case, matching the PostgREST schema)

    private enum Table {
        static let routes = "routes"
        static let joinRequests = "join_requests"
    }

    // MARK: - Wire models

    /// PostgREST row for the `join_requests` table.
    ///
    /// The domain `JoinRequest` has no `route_id` / `host_id` columns — those
    /// live on the parent `RouteCompanion`. The join-request *table* needs both
    /// so the host can query their inbox (`host_id`) and so accept/decline can
    /// locate the parent route (`route_id`). This DTO carries them on the wire.
    private struct JoinRequestRow: Codable, Sendable {
        let id: String
        let routeId: String
        let hostId: String
        let requesterId: String
        let message: String
        let status: String
        let createdAt: String

        enum CodingKeys: String, CodingKey {
            case id
            case routeId = "route_id"
            case hostId = "host_id"
            case requesterId = "requester_id"
            case message
            case status
            case createdAt = "created_at"
        }

        /// Project the wire row onto the domain `JoinRequest`.
        func toDomain() -> JoinRequest {
            JoinRequest(
                id: JoinRequestId(rawValue: id),
                requesterId: requesterId,
                message: message,
                status: JoinRequestStatus(rawValue: status) ?? .pending,
                createdAt: createdAt
            )
        }
    }

    // MARK: - RouteCompanionRemote

    /// Fetches routes currently recruiting companions in the given city.
    ///
    /// GET `routes?city_code=eq.<cityCode>`, then filter client-side to those
    /// whose companion slot is `open` or `forming` (matches the local impl).
    /// Status filtering is kept client-side so we don't depend on a particular
    /// JSONB column layout server-side.
    public func fetchRecruitingRoutes(cityCode: String) async throws -> [Route] {
        guard FeatureFlags.companion else { return [] }

        let result = await onMain { client in
            await client.get(
                table: Table.routes,
                query: [URLQueryItem(name: "city_code", value: "eq.\(cityCode)")]
            )
        }

        let data = try unwrap(result)
        guard !data.isEmpty else { return [] }
        let routes = try decode([Route].self, from: data)
        return routes.filter {
            $0.companion?.status == .open || $0.companion?.status == .forming
        }
    }

    /// Submits a request to join a route's companion group.
    ///
    /// POSTs a new row to `join_requests`. The message is prefixed with the pace
    /// preference exactly like `LocalRouteCompanionRemote` so downstream display
    /// logic is identical regardless of backend.
    public func sendJoinRequest(routeId: RouteId, message: String, pace: String) async throws {
        guard FeatureFlags.companion else { return }

        // Resolve the parent route to capture its host id (needed so the host's
        // inbox query can find this request). If the route or its companion is
        // missing, mirror the local no-op behaviour.
        guard let route = try await fetchRoute(routeId) else { return }
        guard let hostId = route.companion?.hostId else {
            await captureNilCompanion(
                "SupabaseRouteCompanionRemote.sendJoinRequest",
                context: ["routeId": routeId.rawValue]
            )
            return
        }

        let requesterId = await onMain { _ in DeviceIdentityService.shared.deviceID }

        let row = JoinRequestRow(
            id: UUID().uuidString,
            routeId: routeId.rawValue,
            hostId: hostId,
            requesterId: requesterId,
            message: "\(pace): \(message)",
            status: JoinRequestStatus.pending.rawValue,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )

        let body = try encode(row)
        let result = await onMain { client in
            await client.post(table: Table.joinRequests, body: body)
        }
        _ = try unwrap(result)
    }

    /// Fetches the host's pending join requests awaiting a decision.
    ///
    /// GET `join_requests?host_id=eq.<me>&status=eq.pending&order=created_at.desc`.
    public func fetchInbox() async throws -> [JoinRequest] {
        guard FeatureFlags.companion else { return [] }

        let hostId = await onMain { _ in DeviceIdentityService.shared.deviceID }

        let result = await onMain { client in
            await client.get(
                table: Table.joinRequests,
                query: [
                    URLQueryItem(name: "host_id", value: "eq.\(hostId)"),
                    URLQueryItem(name: "status", value: "eq.\(JoinRequestStatus.pending.rawValue)"),
                    URLQueryItem(name: "order", value: "created_at.desc"),
                ]
            )
        }

        let data = try unwrap(result)
        guard !data.isEmpty else { return [] }
        return try decode([JoinRequestRow].self, from: data).map { $0.toDomain() }
    }

    /// Accepts a join request, adding the requester to the route's companion group.
    public func accept(_ request: JoinRequest, route: Route) async throws {
        try await updateRequestStatus(request, route: route, to: .accepted)
    }

    /// Declines a join request, leaving the companion group unchanged.
    public func decline(_ request: JoinRequest, route: Route) async throws {
        try await updateRequestStatus(request, route: route, to: .declined)
    }

    /// Withdraws a previously submitted join request.
    public func withdraw(_ request: JoinRequest, route: Route) async throws {
        try await updateRequestStatus(request, route: route, to: .withdrawn)
    }

    /// Marks a route as completed.
    ///
    /// Fetches the route, drives the companion status through the state machine
    /// (`.markCompleted`), flips verification to `.verified`, credits confirmed
    /// members as walkers, then upserts the whole route row back. Mirrors
    /// `LocalRouteCompanionRemote.markCompleted`.
    public func markCompleted(routeId: RouteId) async throws {
        guard FeatureFlags.companion else { return }

        guard var route = try await fetchRoute(routeId) else { return }
        guard var companion = route.companion else {
            await captureNilCompanion(
                "SupabaseRouteCompanionRemote.markCompleted",
                context: ["routeId": routeId.rawValue]
            )
            return
        }

        // State machine is nonisolated + Sendable, no actor hop required.
        let newStatus = try RouteCompanionStateMachine.transition(
            state: companion.status,
            event: .markCompleted
        )
        companion.status = newStatus
        route.companion = companion

        let newMembers = companion.confirmedMembers
        route.verification.status = .verified
        route.verification.walkedByCount += newMembers.count
        for memberId in newMembers where !route.verification.walkedBy.contains(memberId) {
            route.verification.walkedBy.append(memberId)
        }

        try await upsertRoute(route)
    }

    // MARK: - Internals

    /// Shared accept/decline/withdraw path.
    ///
    /// For `.accepted` the requester is added to the route's confirmed members
    /// and the companion status is advanced via the state machine — mirroring
    /// `LocalRouteCompanionRemote.accept`. The join-request row's status is
    /// upserted in `join_requests`; when accepting, the parent route is upserted
    /// too so membership / status changes persist.
    private func updateRequestStatus(
        _ request: JoinRequest,
        route: Route,
        to status: JoinRequestStatus
    ) async throws {
        guard FeatureFlags.companion else { return }

        // Prefer the server-side route so host id / companion state are
        // authoritative; fall back to the passed-in route when the fetch is
        // empty (e.g. backend-off path returns empty data).
        let serverRoute = (try await fetchRoute(route.id)) ?? route
        guard let hostId = serverRoute.companion?.hostId else {
            await captureNilCompanion(
                "SupabaseRouteCompanionRemote.updateRequestStatus",
                context: ["routeId": route.id.rawValue, "status": status.rawValue]
            )
            return
        }

        // 1) Upsert the join-request row with the new status.
        let row = JoinRequestRow(
            id: request.id.rawValue,
            routeId: route.id.rawValue,
            hostId: hostId,
            requesterId: request.requesterId,
            message: request.message,
            status: status.rawValue,
            createdAt: request.createdAt
        )
        let body = try encode(row)
        let postResult = await onMain { client in
            await client.post(table: Table.joinRequests, body: body)
        }
        _ = try unwrap(postResult)

        // 2) On accept, advance the parent route's companion membership/status.
        guard status == .accepted, var companion = serverRoute.companion else { return }

        let wasOpen = companion.status == .open
        let event: CompanionEvent = wasOpen ? .acceptFirst : .acceptAdditional
        companion.status = (try? RouteCompanionStateMachine.transition(
            state: companion.status, event: event
        )) ?? companion.status

        if !companion.confirmedMembers.contains(request.requesterId) {
            companion.confirmedMembers.append(request.requesterId)
        }

        if companion.confirmedMembers.count >= companion.maxMembers,
           let closed = try? RouteCompanionStateMachine.transition(
               state: companion.status, event: .reachMax
           ) {
            companion.status = closed
        }

        var updatedRoute = serverRoute
        updatedRoute.companion = companion
        try await upsertRoute(updatedRoute)
    }

    /// GET a single route by id. Returns nil when not found / backend off.
    private func fetchRoute(_ id: RouteId) async throws -> Route? {
        let result = await onMain { client in
            await client.get(
                table: Table.routes,
                query: [URLQueryItem(name: "id", value: "eq.\(id.rawValue)")]
            )
        }
        let data = try unwrap(result)
        guard !data.isEmpty else { return nil }
        return try decode([Route].self, from: data).first
    }

    /// POST a route row with upsert semantics (the client sends
    /// `Prefer: resolution=merge-duplicates`, so an existing `id` is updated
    /// rather than duplicated — this is how state updates are persisted given
    /// `SupabaseClient` exposes no PATCH).
    private func upsertRoute(_ route: Route) async throws {
        let body = try encode(route)
        let result = await onMain { client in
            await client.post(table: Table.routes, body: body)
        }
        _ = try unwrap(result)
    }

    // MARK: - MainActor hops & helpers

    /// Run a closure with the `@MainActor` client and return its result.
    /// Awaiting a `@MainActor` closure performs the actor hop, so every use of
    /// `self.client` happens on the main actor.
    private func onMain<T: Sendable>(
        _ body: @MainActor @Sendable (any SupabaseClientProtocol) async -> T
    ) async -> T {
        await body(client)
    }

    /// Unwrap a `SupabaseClient` result, throwing the underlying error on failure
    /// (never silently swallow network errors).
    private func unwrap(_ result: Result<Data, SupabaseClient.SupabaseError>) throws -> Data {
        switch result {
        case .success(let data): return data
        case .failure(let error): throw error
        }
    }

    /// Report a missing companion slot to Sentry on the main actor.
    /// `SentryService` is `@MainActor`; the `[String: String]` context is
    /// `Sendable` so it crosses the hop safely.
    private func captureNilCompanion(_ method: String, context: [String: String]) async {
        await MainActor.run {
            SentryService.capture(
                message: "\(method): route.companion was nil; no-op",
                context: context
            )
        }
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        try JSONEncoder.iso8601Encoder.encode(value)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder.iso8601Decoder.decode(type, from: data)
        } catch {
            throw SupabaseClient.SupabaseError.decoding(String(describing: error))
        }
    }
}
