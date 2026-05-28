import Foundation
import SwiftData

// MARK: - LocalRouteCompanionRemote

/// `RouteCompanionRemote` that persists mutations via `RouteStore` (SwiftData).
/// Used when `FF_BACKEND_SYNC` is false — all data lives on-device.
@MainActor
public final class LocalRouteCompanionRemote: RouteCompanionRemote {
    private let store: RouteStore

    public init(context: ModelContext) {
        self.store = RouteStore(context: context)
    }

    public init(store: RouteStore) {
        self.store = store
    }

    // MARK: - RouteCompanionRemote

    public func fetchRecruitingRoutes(cityCode: String) async throws -> [Route] {
        store.all().filter {
            $0.cityCode == cityCode
                && ($0.companion?.status == .open || $0.companion?.status == .forming)
        }
    }

    public func sendJoinRequest(routeId: RouteId, message: String, pace: String) async throws {
        guard var route = store.get(routeId), route.companion != nil else { return }
        let request = JoinRequest(
            id: JoinRequestId(rawValue: UUID().uuidString),
            requesterId: DeviceIdentityService.shared.deviceID,
            message: "\(pace): \(message)",
            status: .pending,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        route.companion!.joinRequests.append(request)
        store.save(route)
    }

    public func fetchInbox() async throws -> [JoinRequest] {
        let hostId = DeviceIdentityService.shared.deviceID
        return store.all().flatMap { route -> [JoinRequest] in
            guard let companion = route.companion, companion.hostId == hostId else { return [] }
            return companion.joinRequests.filter { $0.status == .pending }
        }
    }

    public func accept(_ request: JoinRequest, route: Route) async throws {
        guard var updated = store.get(route.id),
              var companion = updated.companion,
              let idx = companion.joinRequests.firstIndex(where: { $0.id == request.id }) else { return }

        let wasOpen = companion.status == .open
        let event: CompanionEvent = wasOpen ? .acceptFirst : .acceptAdditional
        let newStatus = (try? RouteCompanionStateMachine.transition(state: companion.status, event: event))
            ?? companion.status

        companion.joinRequests[idx].status = .accepted
        companion.confirmedMembers.append(request.requesterId)
        companion.status = newStatus

        if companion.confirmedMembers.count >= companion.maxMembers,
           let closed = try? RouteCompanionStateMachine.transition(state: companion.status, event: .reachMax) {
            companion.status = closed
        }

        let now = ISO8601DateFormatter().string(from: Date())
        let convStore = ConversationStore(context: store.context)

        if wasOpen && newStatus == .forming && companion.groupConversationId == nil {
            // First accept: open → forming. Create the group conversation.
            let convId = ConversationId(rawValue: UUID().uuidString)
            let conversation = Conversation(
                id: convId,
                requestId: CompanionRequestId(rawValue: request.id.rawValue),
                participantIds: [companion.hostId, request.requesterId],
                type: .groupRoute,
                routeId: route.id.rawValue,
                createdAt: now,
                updatedAt: now
            )
            companion.groupConversationId = convId.rawValue
            updated.companion = companion
            store.saveWithContext(updated)
            convStore.saveWithContext(conversation)
            try store.commitContext()
        } else if let existingConvIdStr = companion.groupConversationId,
                  let existingConv = convStore.get(ConversationId(rawValue: existingConvIdStr)) {
            // Subsequent accept: still forming. Append requesterId to participants.
            var participants = existingConv.participantIds
            if !participants.contains(request.requesterId) {
                participants.append(request.requesterId)
            }
            let updatedConv = Conversation(
                id: existingConv.id,
                requestId: existingConv.requestId,
                participantIds: participants,
                type: existingConv.type,
                routeId: existingConv.routeId,
                lastMessageAt: existingConv.lastMessageAt,
                createdAt: existingConv.createdAt,
                updatedAt: now
            )
            updated.companion = companion
            store.saveWithContext(updated)
            convStore.saveWithContext(updatedConv)
            try store.commitContext()
        } else {
            updated.companion = companion
            store.save(updated)
        }
    }

    public func decline(_ request: JoinRequest, route: Route) async throws {
        guard var updated = store.get(route.id),
              let idx = updated.companion?.joinRequests.firstIndex(where: { $0.id == request.id }) else { return }
        updated.companion!.joinRequests[idx].status = .declined
        store.save(updated)
    }

    public func withdraw(_ request: JoinRequest, route: Route) async throws {
        guard var updated = store.get(route.id),
              let idx = updated.companion?.joinRequests.firstIndex(where: { $0.id == request.id }) else { return }
        updated.companion!.joinRequests[idx].status = .withdrawn
        store.save(updated)
    }

    public func markCompleted(routeId: RouteId) async throws {
        guard var route = store.get(routeId),
              let companion = route.companion else { return }
        let newStatus = try RouteCompanionStateMachine.transition(
            state: companion.status,
            event: .markCompleted
        )
        route.companion!.status = newStatus
        let newMembers = companion.confirmedMembers
        route.verification.status = .verified
        route.verification.walkedByCount += newMembers.count
        for memberId in newMembers where !route.verification.walkedBy.contains(memberId) {
            route.verification.walkedBy.append(memberId)
        }

        if let convIdStr = companion.groupConversationId {
            let convStore = ConversationStore(context: store.context)
            let convId = ConversationId(rawValue: convIdStr)
            if let conv = convStore.get(convId) {
                let frozen = Conversation(
                    id: conv.id,
                    requestId: conv.requestId,
                    participantIds: conv.participantIds,
                    type: conv.type,
                    routeId: conv.routeId,
                    lastMessageAt: conv.lastMessageAt,
                    createdAt: conv.createdAt,
                    updatedAt: ISO8601DateFormatter().string(from: Date()),
                    isReadOnly: true
                )
                store.saveWithContext(route)
                convStore.saveWithContext(frozen)
                try store.commitContext()
                return
            }
        }

        store.save(route)
    }
}
