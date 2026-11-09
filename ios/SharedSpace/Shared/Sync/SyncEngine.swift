import Foundation
import Observation
import Supabase
import SwiftData

/// Keeps SwiftData (local cache) and Supabase (shared truth) in step.
///
/// * Writes are local-first: change the model, call `save(_:)`, and it uploads in the background.
///   Anything that fails to upload keeps `needsUpload = true` and is retried on next launch.
/// * While a room is open, Realtime streams the other person's changes into SwiftData, and
///   SwiftUI views using @Query or the model objects update by themselves.
/// * Conflicts: last write wins per row, using the client-written `updatedAt`.
@MainActor
@Observable
final class SyncEngine {
    let context: ModelContext

    private(set) var userId: UUID = Identity.userId
    private(set) var isSignedIn = false
    private(set) var isWorking = false
    var lastError: String?

    /// Users currently looking at the open room (from Realtime presence), including you.
    private(set) var presentUserIds: Set<UUID> = []
    /// Most recent change made by the other person, for the in-app banner.
    var activity: ActivityEvent?

    private(set) var openRoomId: UUID?
    private var channel: RealtimeChannelV2?
    private var channelTasks: [Task<Void, Never>] = []

    var isShared: Bool { Backend.isConfigured }

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Startup

    func start() async {
        guard let client = Backend.client else { return }
        do {
            let session: Session
            if let existing = try? await client.auth.session {
                session = existing
            } else {
                session = try await client.auth.signInAnonymously()
            }
            adoptUserId(session.user.id)
            isSignedIn = true
            await pushPending()
            try await pullAllRooms()
        } catch {
            report(error)
        }
    }

    /// Rooms created before the first sign-in were stamped with the device id; move them over.
    private func adoptUserId(_ id: UUID) {
        let old = userId
        guard old != id else { return }
        for room in fetchAll(Room.self) where room.hostUserId == old && !room.existsRemotely {
            room.hostUserId = id
        }
        Identity.userId = id
        userId = id
        try? context.save()
    }

    func refresh() async {
        guard isSignedIn else { return }
        await pushPending()
        do { try await pullAllRooms() } catch { report(error) }
    }

    // MARK: - Local writes

    /// Call after changing any synced model. Stamps it, saves locally and uploads.
    func save(_ room: Room) {
        room.updatedAt = .now
        room.needsUpload = true
        persist()
        Task { await upload(room) }
    }

    func save(_ item: Item) {
        item.updatedAt = .now
        item.needsUpload = true
        persist()
        Task { await upload(item) }
    }

    func save(_ design: Design) {
        design.updatedAt = .now
        design.needsUpload = true
        persist()
        Task { await upload(design) }
    }

    func save(_ placement: DesignPlacement) {
        placement.updatedAt = .now
        placement.needsUpload = true
        persist()
        Task { await upload(placement) }
    }

    func insert(_ model: some PersistentModel) {
        context.insert(model)
    }

    private func persist() {
        do { try context.save() } catch { report(error) }
    }

    // MARK: - Rooms

    /// Creates a room locally and on the server. Retries with a new code on the rare collision.
    func createRoom(name: String, currentUse: String, futureUse: String, hostName: String) -> Room {
        let room = Room(code: RoomCode.make(), name: name, currentUse: currentUse, futureUse: futureUse,
                        hostUserId: userId, hostName: hostName)
        context.insert(room)
        persist()
        Task { await upload(room) }
        return room
    }

    /// Host: delete for everyone. Guest: leave the room and forget it on this device.
    func deleteOrLeave(_ room: Room) async {
        if room.role(of: userId) == .host {
            room.deletedAt = .now
            save(room)
        } else if let client = Backend.client, isSignedIn {
            do {
                try await client.rpc("leave_room", params: ["p_room": room.id.uuidString]).execute()
            } catch { report(error) }
        }
        if openRoomId == room.id { await closeRoom() }
        FileStore.deleteRoomFolder(room.id)
        context.delete(room)
        persist()
    }

    func peekRoom(code: String) async throws -> RoomPeek {
        guard let client = Backend.client else { throw SyncError.notShared }
        if !isSignedIn { await start() }
        return try await client.rpc("peek_room", params: ["p_code": code]).execute().value
    }

    func joinRoom(code: String, name: String) async throws -> UUID {
        guard let client = Backend.client else { throw SyncError.notShared }
        if !isSignedIn { await start() }
        let id: UUID = try await client.rpc("join_room", params: ["p_code": code, "p_name": name]).execute().value
        Identity.name = name
        try await pullAllRooms()
        return id
    }

    func setLike(_ design: Design, liked: Bool, as role: Role) {
        if role == .host { design.hostLikes = liked } else { design.guestLikes = liked }
        persist()
        guard let client = Backend.client, isSignedIn else { return }
        Task {
            do {
                try await client.rpc("set_design_like",
                                     params: SetLikeParams(pDesign: design.id, pLiked: liked)).execute()
            } catch { report(error) }
        }
    }

    // MARK: - Upload

    private func upload(_ room: Room) async {
        guard let client = Backend.client, isSignedIn, room.role(of: userId) == .host else { return }
        let stamp = room.updatedAt
        do {
            if room.existsRemotely {
                try await client.from("rooms").update(RoomPatchDTO(room)).eq("id", value: room.id.uuidString).execute()
            } else {
                do {
                    try await client.from("rooms").insert(RoomDTO(room), returning: .minimal).execute()
                } catch let error as PostgrestError where error.code == "23505" {
                    room.code = RoomCode.make()   // code already taken; try once more with a new one
                    try await client.from("rooms").insert(RoomDTO(room), returning: .minimal).execute()
                }
                room.existsRemotely = true
            }
            if room.updatedAt == stamp { room.needsUpload = false }
            persist()
        } catch { report(error) }
    }

    private func upload(_ item: Item) async {
        guard let client = Backend.client, isSignedIn else { return }
        // An item can't exist on the server before its room does.
        if let room = item.room, !room.existsRemotely { await upload(room) }
        let stamp = item.updatedAt
        do {
            try await client.from("items").upsert(ItemDTO(item), returning: .minimal).execute()
            if item.updatedAt == stamp { item.needsUpload = false }
            persist()
        } catch { report(error) }
    }

    private func upload(_ design: Design) async {
        guard let client = Backend.client, isSignedIn else { return }
        let stamp = design.updatedAt
        do {
            try await client.from("designs").upsert(DesignUpsertDTO(design), returning: .minimal).execute()
            design.existsRemotely = true
            if design.updatedAt == stamp { design.needsUpload = false }
            persist()
        } catch { report(error) }
    }

    private func upload(_ placement: DesignPlacement) async {
        guard let client = Backend.client, isSignedIn else { return }
        // A placement can't exist on the server before its design does.
        if let design = placement.design, !design.existsRemotely { await upload(design) }
        let stamp = placement.updatedAt
        do {
            try await client.from("design_placements").upsert(PlacementDTO(placement), returning: .minimal).execute()
            if placement.updatedAt == stamp { placement.needsUpload = false }
            persist()
        } catch { report(error) }
    }

    /// Retries everything that failed to upload earlier (offline, app killed, …).
    func pushPending() async {
        for room in fetchAll(Room.self) where room.needsUpload { await upload(room) }
        for item in fetchAll(Item.self) where item.needsUpload { await upload(item) }
        for design in fetchAll(Design.self) where design.needsUpload { await upload(design) }
        for p in fetchAll(DesignPlacement.self) where p.needsUpload { await upload(p) }
    }

    // MARK: - Download

    /// Fetches every room this person belongs to, and everything inside them.
    func pullAllRooms() async throws {
        guard let client = Backend.client, isSignedIn else { return }
        isWorking = true
        defer { isWorking = false }
        let remote: [RoomDTO] = try await client.from("rooms").select().execute().value
        let remoteIds = Set(remote.map(\.id))
        for dto in remote { applyRoom(dto) }
        // Forget rooms that were deleted or that we were removed from.
        for room in fetchAll(Room.self) where room.existsRemotely && !remoteIds.contains(room.id) && !room.needsUpload {
            context.delete(room)
        }
        persist()
        for dto in remote where dto.deletedAt == nil {
            try await pullContents(of: dto.id)
        }
    }

    func pullContents(of roomId: UUID) async throws {
        guard let client = Backend.client, isSignedIn else { return }
        let rid = roomId.uuidString
        let items: [ItemDTO] = try await client.from("items").select().eq("room_id", value: rid).execute().value
        let designs: [DesignDTO] = try await client.from("designs").select().eq("room_id", value: rid).execute().value
        let placements: [PlacementDTO] = try await client.from("design_placements").select().eq("room_id", value: rid).execute().value
        items.forEach { applyItem($0, announce: false) }
        designs.forEach { applyDesign($0) }
        placements.forEach { applyPlacement($0) }
        persist()
    }

    // MARK: - Realtime

    /// Starts streaming the other person's changes and presence for one room.
    func openRoom(_ roomId: UUID) async {
        guard let client = Backend.client, isSignedIn else { return }
        guard openRoomId != roomId else { return }
        await closeRoom()
        openRoomId = roomId
        try? await pullContents(of: roomId)

        let rid = roomId.uuidString.lowercased()
        let ch = client.channel("room:\(rid)")
        let inRoom = RealtimePostgresFilter.eq("room_id", value: rid)
        let roomChanges = ch.postgresChange(AnyAction.self, table: "rooms", filter: .eq("id", value: rid))
        let itemChanges = ch.postgresChange(AnyAction.self, table: "items", filter: inRoom)
        let designChanges = ch.postgresChange(AnyAction.self, table: "designs", filter: inRoom)
        let placementChanges = ch.postgresChange(AnyAction.self, table: "design_placements", filter: inRoom)
        let presence = ch.presenceChange()

        channelTasks = [
            Task { [weak self] in
                for await action in roomChanges {
                    if let dto: RoomDTO = Self.record(action) { self?.applyRoom(dto); self?.persist() }
                }
            },
            Task { [weak self] in
                for await action in itemChanges {
                    if let dto: ItemDTO = Self.record(action) { self?.applyItem(dto, announce: true); self?.persist() }
                }
            },
            Task { [weak self] in
                for await action in designChanges {
                    if let dto: DesignDTO = Self.record(action) { self?.applyDesign(dto); self?.persist() }
                }
            },
            Task { [weak self] in
                for await action in placementChanges {
                    if let dto: PlacementDTO = Self.record(action) { self?.applyPlacement(dto); self?.persist() }
                }
            },
            Task { [weak self] in
                for await change in presence {
                    let joins = (try? change.decodeJoins(as: PresenceState.self)) ?? []
                    let leaves = (try? change.decodeLeaves(as: PresenceState.self)) ?? []
                    self?.presentUserIds.formUnion(joins.map(\.userId))
                    self?.presentUserIds.subtract(leaves.map(\.userId))
                }
            },
        ]

        channel = ch
        do {
            try await ch.subscribeWithError()
            try await ch.track(PresenceState(userId: userId, name: Identity.name))
        } catch {
            report(error)
        }
    }

    func closeRoom() async {
        channelTasks.forEach { $0.cancel() }
        channelTasks = []
        if let ch = channel, let client = Backend.client {
            await client.removeChannel(ch)
        }
        channel = nil
        openRoomId = nil
        presentUserIds = []
    }

    func isPresent(_ userId: UUID?) -> Bool {
        guard let userId else { return false }
        return presentUserIds.contains(userId)
    }

    private static func record<T: Decodable>(_ action: AnyAction) -> T? {
        switch action {
        case .insert(let a): try? a.decodeRecord(as: T.self, decoder: JSONCoding.decoder)
        case .update(let a): try? a.decodeRecord(as: T.self, decoder: JSONCoding.decoder)
        case .delete: nil   // we only soft-delete, which arrives as an update
        }
    }

    // MARK: - Applying remote rows

    private func applyRoom(_ dto: RoomDTO) {
        if let local = fetch(Room.self, id: dto.id) {
            guard !(local.needsUpload && local.updatedAt > dto.updatedAt) else { return }
            local.apply(dto)
        } else if dto.deletedAt == nil {
            context.insert(Room(dto))
        }
    }

    private func applyItem(_ dto: ItemDTO, announce: Bool) {
        guard let room = fetch(Room.self, id: dto.roomId) else { return }
        if let local = fetch(Item.self, id: dto.id) {
            guard !(local.needsUpload && local.updatedAt > dto.updatedAt) else { return }
            let before = (status: local.status, suggestion: local.suggestion, owner: local.owner)
            local.apply(dto)
            if announce {
                activity = ActivityEvent.describe(item: local, before: before, room: room, me: room.role(of: userId))
                    ?? activity
            }
        } else {
            let item = Item(dto, room: room)
            context.insert(item)
        }
    }

    private func applyDesign(_ dto: DesignDTO) {
        guard let room = fetch(Room.self, id: dto.roomId) else { return }
        if let local = fetch(Design.self, id: dto.id) {
            guard !(local.needsUpload && local.updatedAt > dto.updatedAt) else { return }
            local.apply(dto)
        } else {
            context.insert(Design(dto, room: room))
        }
    }

    private func applyPlacement(_ dto: PlacementDTO) {
        guard let design = fetch(Design.self, id: dto.designId) else { return }
        if let local = fetch(DesignPlacement.self, id: dto.id) {
            guard !(local.needsUpload && local.updatedAt > dto.updatedAt) else { return }
            local.apply(dto)
        } else {
            context.insert(DesignPlacement(dto, design: design))
        }
    }

    // MARK: - Fetch helpers

    func fetchAll<T: PersistentModel>(_ type: T.Type) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }

    func fetch(_ type: Room.Type, id: UUID) -> Room? {
        try? context.fetch(FetchDescriptor<Room>(predicate: #Predicate { $0.id == id })).first
    }

    func fetch(_ type: Item.Type, id: UUID) -> Item? {
        try? context.fetch(FetchDescriptor<Item>(predicate: #Predicate { $0.id == id })).first
    }

    func fetch(_ type: Design.Type, id: UUID) -> Design? {
        try? context.fetch(FetchDescriptor<Design>(predicate: #Predicate { $0.id == id })).first
    }

    func fetch(_ type: DesignPlacement.Type, id: UUID) -> DesignPlacement? {
        try? context.fetch(FetchDescriptor<DesignPlacement>(predicate: #Predicate { $0.id == id })).first
    }

    // MARK: - Errors

    private func report(_ error: Error) {
        lastError = SyncError.describe(error)
        print("Sync error:", error)
    }
}

private struct SetLikeParams: Encodable {
    let pDesign: UUID
    let pLiked: Bool
}

enum SyncError: LocalizedError {
    case notShared

    var errorDescription: String? {
        switch self {
        case .notShared: "Sharing isn’t set up in this build yet."
        }
    }

    static func describe(_ error: Error) -> String {
        let text = "\(error)"
        if text.contains("room_not_found") { return "We couldn’t find that room. Check the code and try again." }
        if (error as? URLError) != nil { return "You’re offline. Changes will sync when you’re back online." }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
