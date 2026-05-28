import Foundation
import SwiftData

// MARK: - NotImplementedError

/// Thrown by any stub method that has not yet been implemented.
public struct NotImplementedError: Error {
    public let method: String
    public init(_ method: String = #function) { self.method = method }
}

// MARK: - RouteCompanionRemote

/// Abstracts all companion mutations so future backend swap is one-class change.
public protocol RouteCompanionRemote: Sendable {
    /// Fetch routes that are open or forming for the given city.
    func fetchRecruitingRoutes(cityCode: String) async throws -> [Route]

    /// Submit a join request for a route.
    func sendJoinRequest(routeId: RouteId, message: String, pace: String) async throws

    /// Fetch all join requests across routes where the current user is host.
    func fetchInbox() async throws -> [JoinRequest]

    /// Accept a pending join request.
    func accept(_ request: JoinRequest, route: Route) async throws

    /// Decline a pending join request.
    func decline(_ request: JoinRequest, route: Route) async throws

    /// Withdraw a join request the current user sent.
    func withdraw(_ request: JoinRequest, route: Route) async throws

    /// Transition a closed route to completed.
    func markCompleted(routeId: RouteId) async throws
}

// MARK: - Factory

/// Resolves the concrete `RouteCompanionRemote` based on `FeatureFlags.backendSync`.
/// When `FF_BACKEND_SYNC` is false (default), returns `LocalRouteCompanionRemote`.
/// When true, returns `SupabaseRouteCompanionRemote` — callers must handle `NotImplementedError`.
@MainActor
public func makeRouteCompanionRemote(context: ModelContext) -> any RouteCompanionRemote {
    if FeatureFlags.backendSync {
        return SupabaseRouteCompanionRemote()
    } else {
        return LocalRouteCompanionRemote(context: context)
    }
}
