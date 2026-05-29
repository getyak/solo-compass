
// MARK: - SupabaseRouteCompanionRemote

/// Stub `RouteCompanionRemote` backed by Supabase. All methods throw
/// `NotImplementedError` until the backend integration lands.
/// Resolved when `FF_BACKEND_SYNC` is true; callers must handle the error.
public final class SupabaseRouteCompanionRemote: RouteCompanionRemote {

    public init() {}

    /// Fetches routes currently recruiting companions in the given city.
    public func fetchRecruitingRoutes(cityCode: String) async throws -> [Route] {
        throw NotImplementedError(#function)
    }

    /// Submits a request to join a route's companion group with a message and pace preference.
    public func sendJoinRequest(routeId: RouteId, message: String, pace: String) async throws {
        throw NotImplementedError(#function)
    }

    /// Fetches the host's pending join requests awaiting a decision.
    public func fetchInbox() async throws -> [JoinRequest] {
        throw NotImplementedError(#function)
    }

    /// Accepts a join request, adding the requester to the route's companion group.
    public func accept(_ request: JoinRequest, route: Route) async throws {
        throw NotImplementedError(#function)
    }

    /// Declines a join request, leaving the companion group unchanged.
    public func decline(_ request: JoinRequest, route: Route) async throws {
        throw NotImplementedError(#function)
    }

    /// Withdraws a previously submitted join request.
    public func withdraw(_ request: JoinRequest, route: Route) async throws {
        throw NotImplementedError(#function)
    }

    /// Marks a route as completed, verifying it for the confirmed companions.
    public func markCompleted(routeId: RouteId) async throws {
        throw NotImplementedError(#function)
    }
}
