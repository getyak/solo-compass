import Foundation

// MARK: - SupabaseRouteCompanionRemote

/// `RouteCompanionRemote` backed by Supabase — NOT YET IMPLEMENTED.
///
/// Construction is gated: in non-DEBUG builds, instantiating this class while
/// `FF_BACKEND_SYNC=true` is a `preconditionFailure` so a stray flag flip
/// in TestFlight/prod crashes at first call instead of silently corrupting
/// state. In DEBUG / under tests, the init succeeds and methods throw
/// `NotImplementedError` so the existing UI fallbacks
/// (`catch is NotImplementedError` in ApprovalQueueView, JoinRouteRequestSheet,
/// MyRequestsListView, CompletionMoment) can still surface a graceful
/// "backend not ready" state during development.
public final class SupabaseRouteCompanionRemote: RouteCompanionRemote {

    public init() {
        #if !DEBUG
        if FeatureFlags.backendSync {
            preconditionFailure(
                "SupabaseRouteCompanionRemote is not implemented yet. " +
                "Set FF_BACKEND_SYNC=false until the Supabase companion backend ships."
            )
        }
        #endif
    }

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
