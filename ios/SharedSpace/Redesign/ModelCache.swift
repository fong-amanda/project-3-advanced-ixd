import Observation
import RealityKit
import SwiftUI

/// Catalogue furniture models (Resources/Furniture/*.usdz), loaded from disk once and copied for each
/// use. Views that read `revision` redraw when a model finishes loading.
@MainActor
@Observable
final class ModelCache {
    static let shared = ModelCache()

    /// Bumped each time a model finishes loading.
    private(set) var revision = 0
    @ObservationIgnored private var templates: [String: Entity] = [:]
    @ObservationIgnored private var pending: [String: Task<Entity?, Never>] = [:]

    /// A copy of a model that's already loaded, or nil (then call `load`).
    func cached(_ file: String) -> Entity? { templates[file]?.clone(recursive: true) }

    /// A copy of the model, loading it first if needed. Loads in the background; nil if it's missing.
    func load(_ file: String) async -> Entity? {
        if let template = templates[file] { return template.clone(recursive: true) }
        let task = pending[file] ?? Task { @MainActor in
            guard let url = FurnitureCatalog.modelURL(file) else { return nil }
            return try? await Entity(contentsOf: url)
        }
        pending[file] = task
        guard let template = await task.value else { return nil }
        pending[file] = nil
        if templates[file] == nil {
            templates[file] = template
            revision += 1
        }
        return template.clone(recursive: true)
    }

    func preload(_ files: some Sequence<String>) async {
        for file in files where templates[file] == nil { _ = await load(file) }
    }

    /// Scales a model to a piece's width (x), height (y) and depth (z) in metres, centred, standing
    /// on y = 0, so it appears at the catalogue's true size whatever size it was made at.
    static func fit(_ model: Entity, w: Float, h: Float, d: Float) {
        let b = model.visualBounds(relativeTo: nil)
        let e = b.extents
        guard e.x > 0, e.y > 0, e.z > 0 else { return }
        let s = SIMD3<Float>(w / e.x, h / e.y, d / e.z)
        model.scale *= s
        model.position = [-b.center.x * s.x, -b.min.y * s.y, -b.center.z * s.z]
    }
}
