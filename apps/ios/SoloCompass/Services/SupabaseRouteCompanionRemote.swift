import Foundation

// MARK: - SupabaseRouteCompanionRemote

/// Stub `RouteCompanionRemote` backed by Supabase. All methods throw
/// `NotImplementedError` until the backend integration lands.
/// Resolved when `FF_BACKEND_SYNC` is true; callers must handle the error.
public final class SupabaseRouteCompanionRemote: RouteCompanionRemote {

    public init() {}

    public func fetchRecruitingRoutes(cityCode: String) async throws -> [Route] {
        throw NotImplementedError(#function)
    }

    public func sendJoinRequest(routeId: RouteId, message: String, pace: String) async throws {
        throw NotImplementedError(#function)
    }

    public func fetchInbox() async throws -> [JoinRequest] {
        throw NotImplementedError(#function)
    }

    public func accept(_ request: JoinRequest, route: Route) async throws {
        throw NotImplementedError(#function)
    }

    public func decline(_ request: JoinRequest, route: Route) async throws {
        throw NotImplementedError(#function)
    }

    public func withdraw(_ request: JoinRequest, route: Route) async throws {
        throw NotImplementedError(#function)
    }

    public func markCompleted(routeId: RouteId) async throws {
        throw NotImplementedError(#function)
    }
}
