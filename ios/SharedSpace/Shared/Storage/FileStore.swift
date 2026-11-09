import Foundation

/// Files that are too big or too device-specific for the database.
///
///     Application Support/Rooms/<room id>/
///         capturedRoom.json      RoomPlan's CapturedRoom (Codable) — the source of truth for the scan
///         room.usdz              3D model exported from the scan
///         worldMap.arworldmap    ARKit world map saved at the end of the scan, to re-anchor AR
///         roomFrame.json         transform from AR world space to room coordinates
///         geometry.json          simplified walls/doors/windows (also uploaded for other devices)
///         thumbnail.jpg          shown on the home screen (a copy of photo 0)
///         photos/<n>.jpg         room photos with the item pins (also uploaded for the other phone)
///         items/<item id>.jpg    item photos
enum FileStore {
    static var roomsRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "Rooms", directoryHint: .isDirectory)
    }

    static func roomFolder(_ roomId: UUID) -> URL {
        let url = roomsRoot.appending(path: roomId.uuidString, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func deleteRoomFolder(_ roomId: UUID) {
        try? FileManager.default.removeItem(at: roomsRoot.appending(path: roomId.uuidString))
    }

    static func capturedRoomURL(_ roomId: UUID) -> URL { roomFolder(roomId).appending(path: "capturedRoom.json") }
    static func roomModelURL(_ roomId: UUID) -> URL { roomFolder(roomId).appending(path: "room.usdz") }
    static func worldMapURL(_ roomId: UUID) -> URL { roomFolder(roomId).appending(path: "worldMap.arworldmap") }
    static func roomFrameURL(_ roomId: UUID) -> URL { roomFolder(roomId).appending(path: "roomFrame.json") }
    static func geometryURL(_ roomId: UUID) -> URL { roomFolder(roomId).appending(path: "geometry.json") }
    static func thumbnailURL(_ roomId: UUID) -> URL { roomFolder(roomId).appending(path: "thumbnail.jpg") }

    static func itemPhotoURL(roomId: UUID, itemId: UUID) -> URL {
        let folder = roomFolder(roomId).appending(path: "items", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "\(itemId.uuidString).jpg")
    }

    static func roomPhotoURL(_ roomId: UUID, index: Int) -> URL {
        let folder = roomFolder(roomId).appending(path: "photos", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "\(index).jpg")
    }

    /// Path inside the "rooms" Storage bucket. Lower-case so it matches the room id the policies check.
    static func roomPhotoStoragePath(_ roomId: UUID, index: Int) -> String {
        "\(roomId.uuidString.lowercased())/photos/\(index).jpg"
    }

    static func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path()) }
}
