import ARKit
import RoomPlan

enum DeviceCapabilities {
    /// RoomPlan needs a LiDAR scanner (iPhone 12 Pro and later Pro models). Always false in the Simulator.
    static var canScanRooms: Bool { RoomCaptureSession.isSupported }

    /// LiDAR scene mesh, used for occlusion in the live AR view.
    static var hasLiDAR: Bool { ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) }

    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }
}
