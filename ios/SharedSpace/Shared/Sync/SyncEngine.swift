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
    /// Set when a room photo couldn't be written to disk; RootView shows it.
    var photoSaveError: String?

    /// Users currently looking at the open room (from Realtime presence), including you.
    private(set) var presentUserIds: Set<UUID> = []
    /// Most recent change made by the other person, for the in-app banner.
    var activity: ActivityEvent?
    /// The decision (or suggestion) just made on this phone, for "Marked “Keep”. Undo".
    var lastDecision: DecisionUndo?
    /// Bumped whenever a room photo arrives on disk, so views showing photos redraw.
    private(set) var photoRevision = 0

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

    enum RoomDeletion {
        /// Gone from this phone and the server (or there is no server).
        case deleted
        /// Gone from this phone; the server delete is queued until we're back online.
        case queued
    }

    /// Host only: permanently deletes the room and everything in it.
    ///
    /// * This phone: the SwiftData records (room, items, designs, placements — by cascade) and every
    ///   file in the room's folder (scan, 3D model, world map, room frame, geometry, photos, item photos).
    /// * The server: the room's files in Storage, then the room row, which removes its items, designs,
    ///   placements and memberships with it and frees the room code.
    /// Offline, the server half is queued (see `PendingRoomDeletions`) and retried on the next sync.
    func deleteRoom(_ room: Room) async -> RoomDeletion {
        guard room.role(of: userId) == .host else { await leave(room); return .deleted }
        let id = room.id
        if openRoomId == id { await closeRoom() }
        forgetLocally(room)
        guard Backend.isConfigured else { return .deleted }
        PendingRoomDeletions.add(id)
        return await pushRoomDeletion(id) ? .deleted : .queued
    }

    /// Guest: leave the room and forget it on this phone. The host's room stays as it is.
    func leave(_ room: Room) async {
        if let client = Backend.client, isSignedIn {
            do {
                try await client.rpc("leave_room", params: ["p_room": room.id.uuidString]).execute()
            } catch { report(error) }
        }
        if openRoomId == room.id { await closeRoom() }
        forgetLocally(room)
    }

    /// Removes a room, its records and its files from this phone only.
    private func forgetLocally(_ room: Room) {
        let id = room.id
        FileStore.deleteRoomFolder(id)
        RoomPhotos.purge()
        PhotoCrops.purge()
        CaptureConsent.forget(id)
        context.delete(room)
        persist()
        photoRevision += 1
    }

    /// Deletes a room on the server: its Storage files first (the storage policies need the room to
    /// still exist to know you're its host), then the row. True once the server no longer has it.
    @discardableResult
    private func pushRoomDeletion(_ id: UUID) async -> Bool {
        guard let client = Backend.client, isSignedIn else { return false }
        let folder = id.uuidString.lowercased()
        do {
            let bucket = client.storage.from("rooms")
            var paths: [String] = []
            for sub in ["", "photos", "items"] {
                let prefix = sub.isEmpty ? folder : "\(folder)/\(sub)"
                let files = try await bucket.list(path: prefix)
                paths += files.filter { $0.id != nil }.map { "\(prefix)/\($0.name)" }   // id is nil for folders
            }
            if !paths.isEmpty { _ = try await bucket.remove(paths: paths) }
            try await client.rpc("delete_room", params: ["p_room": id.uuidString]).execute()
            PendingRoomDeletions.remove(id)
            return true
        } catch {
            report(error)
            return false
        }
    }

    // MARK: - Archive (per person)

    /// Archives or unarchives a room for the person on this phone only. Nothing in the room changes,
    /// and the other person still sees it as before.
    func setArchived(_ room: Room, _ archived: Bool) {
        room.archived = archived
        room.archiveNeedsUpload = Backend.isConfigured
        persist()
        Task { await uploadArchive(room) }
    }

    private func uploadArchive(_ room: Room) async {
        guard let client = Backend.client, isSignedIn, room.archiveNeedsUpload else { return }
        // The membership row only exists once the room is on the server.
        if !room.existsRemotely { await upload(room) }
        let value = room.archived
        do {
            try await client.rpc("set_room_archived",
                                 params: ArchiveParams(pRoom: room.id, pArchived: value)).execute()
            if room.archived == value { room.archiveNeedsUpload = false }
            persist()
        } catch { report(error) }
    }

    /// This person's archive flags, from their own membership rows.
    private func pullArchiveFlags() async {
        guard let client = Backend.client, isSignedIn else { return }
        do {
            let rows: [MembershipDTO] = try await client.from("room_members").select("room_id, archived")
                .eq("user_id", value: userId.uuidString.lowercased()).execute().value
            for row in rows {
                guard let room = fetch(Room.self, id: row.roomId), !room.archiveNeedsUpload else { continue }
                room.archived = row.archived ?? false
            }
            persist()
        } catch {
            // An older database without the column: rooms simply stay unarchived.
            print("Archive flags not available:", error)
        }
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

    /// Guest's reaction to a plan version: "Looks good" (`note == nil`) or "One thing…" with a note.
    func setReaction(_ design: Design, ok: Bool, note: String?, as role: Role) {
        if role == .host { design.hostLikes = ok } else { design.guestLikes = ok }
        design.reactionNote = ok ? nil : note
        design.reactionAt = .now
        persist()
        guard let client = Backend.client, isSignedIn else { return }
        Task {
            do {
                try await client.rpc("set_design_reaction",
                                     params: SetReactionParams(pDesign: design.id, pOk: ok, pNote: ok ? nil : note)).execute()
            } catch { report(error) }
        }
    }

    // MARK: - Room photos

    /// Stores a room photo (JPEG) as photo `index`, locally first, then in Storage for the other phone.
    /// Saves a room photo on disk, links it to the room and uploads it. False if it couldn't be written.
    @discardableResult
    func savePhoto(_ jpeg: Data, index: Int, of room: Room) -> Bool {
        // No location or camera details on disk or in Storage, whichever path the photo came by.
        guard let jpeg = PhotoMetadata.stripped(jpeg) else {
            photoSaveError = "The photo couldn’t be saved without its location details, so it wasn’t saved. Try another photo."
            return false
        }
        do {
            try jpeg.write(to: FileStore.roomPhotoURL(room.id, index: index), options: .atomic)
        } catch {
            print("Photo save failed:", error)
            photoSaveError = "The photo couldn’t be saved on this device. Free up some storage and try again."
            return false
        }
        if index == 0 { try? jpeg.write(to: FileStore.thumbnailURL(room.id), options: .atomic) }
        photoRevision += 1
        if room.photoCount <= index { room.photoCount = index + 1 }
        save(room)
        Task { await uploadPhoto(roomId: room.id, index: index) }
        return true
    }

    private func uploadPhoto(roomId: UUID, index: Int) async {
        guard let client = Backend.client, isSignedIn,
              let data = try? Data(contentsOf: FileStore.roomPhotoURL(roomId, index: index)) else { return }
        do {
            try await client.storage.from("rooms").upload(
                FileStore.roomPhotoStoragePath(roomId, index: index), data: data,
                options: FileOptions(contentType: "image/jpeg", upsert: true))
        } catch { report(error) }
    }

    /// Downloads room photos this phone doesn't have yet (the host's photos, on the guest's phone).
    private func downloadMissingPhotos(of room: Room) async {
        guard let client = Backend.client, isSignedIn else { return }
        for index in 0..<min(room.photoCount, Room.maxPhotos) {
            let url = FileStore.roomPhotoURL(room.id, index: index)
            guard !FileStore.exists(url) else { continue }
            do {
                // Photos uploaded by an older build may still carry metadata; never keep it.
                let downloaded = try await client.storage.from("rooms").download(path: FileStore.roomPhotoStoragePath(room.id, index: index))
                guard let data = PhotoMetadata.stripped(downloaded) else { continue }
                try data.write(to: url, options: .atomic)
                if index == 0 { try? data.write(to: FileStore.thumbnailURL(room.id), options: .atomic) }
                photoRevision += 1
            } catch {
                // The host's upload may still be in flight; we try again on the next refresh.
                print("Photo not available yet:", error)
            }
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
        // Room deletions made offline go first, so nothing below re-uploads a deleted room.
        for id in PendingRoomDeletions.all { await pushRoomDeletion(id) }
        for room in fetchAll(Room.self) where room.needsUpload { await upload(room) }
        // Photos taken offline: upload any the server may be missing (upsert, so repeats are harmless).
        for room in fetchAll(Room.self) where room.role(of: userId) == .host && room.needsUpload {
            for index in 0..<room.photoCount { await uploadPhoto(roomId: room.id, index: index) }
        }
        for item in fetchAll(Item.self) where item.needsUpload { await upload(item) }
        for design in fetchAll(Design.self) where design.needsUpload { await upload(design) }
        for p in fetchAll(DesignPlacement.self) where p.needsUpload { await upload(p) }
        for room in fetchAll(Room.self) where room.archiveNeedsUpload { await uploadArchive(room) }
    }

    // MARK: - Download

    /// Fetches every room this person belongs to, and everything inside them.
    func pullAllRooms() async throws {
        guard let client = Backend.client, isSignedIn else { return }
        isWorking = true
        defer { isWorking = false }
        // A room deleted on this phone while offline stays deleted until the server catches up.
        let fetched: [RoomDTO] = try await client.from("rooms").select().execute().value
        let remote = fetched.filter { !PendingRoomDeletions.contains($0.id) }
        let remoteIds = Set(remote.map(\.id))
        for dto in remote { applyRoom(dto) }
        // Forget rooms that were deleted or that we were removed from, files and all.
        for room in fetchAll(Room.self) where room.existsRemotely && !remoteIds.contains(room.id) && !room.needsUpload {
            if openRoomId == room.id { await closeRoom() }
            FileStore.deleteRoomFolder(room.id)
            CaptureConsent.forget(room.id)
            context.delete(room)
        }
        persist()
        await pullArchiveFlags()
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
        if let room = fetch(Room.self, id: roomId) { await downloadMissingPhotos(of: room) }
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
                    // The host deleted the room: drop it (and its files) from this phone now.
                    if case .delete = action { try? await self?.pullAllRooms(); continue }
                    if let dto: RoomDTO = Self.record(action) {
                        self?.applyRoom(dto)
                        self?.persist()
                        if let self, let room = self.fetch(Room.self, id: dto.id) { await self.downloadMissingPhotos(of: room) }
                    }
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
        guard !PendingRoomDeletions.contains(dto.id) else { return }
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
            let before = ActivityEvent.Before(status: local.status, suggestion: local.suggestion,
                                              owner: local.owner, askedAt: local.askedAt)
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

/// Rooms the host deleted while offline, waiting for the server delete. Kept in UserDefaults so the
/// queue survives the app being closed.
enum PendingRoomDeletions {
    private static let key = "ss.pendingRoomDeletions"

    static var all: [UUID] { (UserDefaults.standard.stringArray(forKey: key) ?? []).compactMap(UUID.init(uuidString:)) }
    static func contains(_ id: UUID) -> Bool { all.contains(id) }

    static func add(_ id: UUID) {
        guard !contains(id) else { return }
        UserDefaults.standard.set((all + [id]).map(\.uuidString), forKey: key)
    }

    static func remove(_ id: UUID) {
        UserDefaults.standard.set(all.filter { $0 != id }.map(\.uuidString), forKey: key)
    }
}

private struct ArchiveParams: Encodable {
    let pRoom: UUID
    let pArchived: Bool
}

private struct SetLikeParams: Encodable {
    let pDesign: UUID
    let pLiked: Bool
}

private struct SetReactionParams: Encodable {
    let pDesign: UUID
    let pOk: Bool
    @NullCodable var pNote: String?
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
