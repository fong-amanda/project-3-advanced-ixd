import ARKit
import Foundation
import simd

/// Where the room sits in an AR session's world: turns room coordinates (cm, x right, z toward the
/// front, from the back-left corner) into AR world positions (metres) and back.
///
/// Saved on this phone only, next to the AR world map it belongs to (Rooms/<id>/roomFrame.json and
/// worldMap.arworldmap). Neither is ever uploaded.
struct RoomFrame: Codable, Equatable {
    /// Turn about the vertical axis applied to room directions (radians, RealityKit's sense).
    var yaw: Float
    /// World position of the room's (0, 0) corner, on the floor.
    var originX: Float
    var originY: Float
    var originZ: Float

    var origin: SIMD3<Float> { [originX, originY, originZ] }
    private var turn: simd_quatf { simd_quatf(angle: yaw, axis: [0, 1, 0]) }

    init(yaw: Float, origin: SIMD3<Float>) {
        self.yaw = yaw
        originX = origin.x; originY = origin.y; originZ = origin.z
    }

    /// From a scan: the importer turned the scan by `angle` (so the longest wall runs along x) and
    /// shifted it by (minX, minZ) metres. `floorY` is the scan's floor height.
    static func fromScan(angle: Double, minX: Double, minZ: Double, floorY: Float) -> RoomFrame {
        let yaw = Float(angle)
        var o = simd_quatf(angle: yaw, axis: [0, 1, 0]).act(SIMD3<Float>(Float(minX), 0, Float(minZ)))
        o.y = floorY
        return RoomFrame(yaw: yaw, origin: o)
    }

    /// From lining up by hand: `corner` (room cm) was tapped at `cornerWorld`, and the wall leaving
    /// it in room direction `along` was tapped at `wallWorld`.
    static func fromTaps(corner: (x: Double, z: Double), along: (x: Double, z: Double),
                         cornerWorld: SIMD3<Float>, wallWorld: SIMD3<Float>) -> RoomFrame? {
        let d = wallWorld - cornerWorld
        guard hypot(d.x, d.z) > 0.2 else { return nil }   // the two taps need to be apart
        let roomAngle = atan2(Float(along.z), Float(along.x))
        let worldAngle = atan2(d.z, d.x)
        // A turn of `yaw` (RealityKit) moves directions by −yaw in the x–z plane.
        let yaw = roomAngle - worldAngle
        let turned = simd_quatf(angle: yaw, axis: [0, 1, 0]).act(SIMD3<Float>(Float(corner.x / 100), 0, Float(corner.z / 100)))
        return RoomFrame(yaw: yaw, origin: cornerWorld - turned)
    }

    func toWorld(x: Double, z: Double, floorY: Float? = nil) -> SIMD3<Float> {
        var p = origin + turn.act(SIMD3<Float>(Float(x / 100), 0, Float(z / 100)))
        p.y = floorY ?? originY
        return p
    }

    func toRoom(_ p: SIMD3<Float>) -> (x: Double, z: Double) {
        let local = turn.inverse.act(p - origin)
        return (Double(local.x * 100), Double(local.z * 100))
    }

    /// A piece's world turn (degrees, about +y) for a room yaw, and back. The plan and 3D view turn
    /// a piece by −yaw.
    func worldYawDeg(roomYaw: Double) -> Float { yaw * 180 / .pi - Float(roomYaw) }
    func roomYawDeg(worldYaw: Float) -> Double { Double(yaw * 180 / .pi - worldYaw) }

    // MARK: Saved on this phone

    static func load(_ roomId: UUID) -> RoomFrame? {
        guard let data = try? Data(contentsOf: FileStore.roomFrameURL(roomId)) else { return nil }
        return try? JSONDecoder().decode(RoomFrame.self, from: data)
    }

    func save(_ roomId: UUID) {
        if let data = try? JSONEncoder().encode(self) {
            try? data.write(to: FileStore.roomFrameURL(roomId), options: [.atomic, .completeFileProtection])
        }
    }

    /// The world map saved with this frame, if any.
    static func worldMap(_ roomId: UUID) -> ARWorldMap? {
        guard let data = try? Data(contentsOf: FileStore.worldMapURL(roomId)) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: data)
    }

    static func saveWorldMap(_ map: ARWorldMap, frame: RoomFrame, roomId: UUID) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: map, requiringSecureCoding: true) else { return }
        try? data.write(to: FileStore.worldMapURL(roomId), options: [.atomic, .completeFileProtection])
        frame.save(roomId)
    }

    static func forget(_ roomId: UUID) {
        try? FileManager.default.removeItem(at: FileStore.worldMapURL(roomId))
        try? FileManager.default.removeItem(at: FileStore.roomFrameURL(roomId))
    }
}
