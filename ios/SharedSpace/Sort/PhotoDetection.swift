import CoreML
import UIKit
import Vision

import os

// "Find things in this photo": runs YOLOv3 (Apple's Core ML build, 8-bit weights; YOLO License =
// public domain, see Resources/Models/LICENSE-YOLOv3.txt) through Vision, entirely on the iPhone.
// Nothing here touches the network. Results are only *suggestions*: the person confirms, renames or
// removes each one in DetectionReviewSheet before anything is added.
//
// Every step logs a "[Detect]" line (Xcode console, or Console.app filtered on "[Detect]").

/// "[Detect] …" lines. Labels and numbers only: never the photo or anything personal.
let detectLog = Logger(subsystem: "com.amandafong.sharedspace", category: "Detect")

/// The words around detection, shared by the photo step, the review sheet and the design system page.
enum DetectionCopy {
    static let photoStepLead = "Add a photo and we’ll use AI on your iPhone to suggest the things in it. You’ll check each one before it’s added."
    static let howTitle = "How we find things in your photo"
    // The model knows beds, chairs, sofas, tables and TVs, but not shelves.
    static let howMessage = """
    An AI model on your iPhone looks for common furniture like beds, chairs, sofas and tables.

    It can miss things or get them wrong, especially less common items. You’ll confirm, rename or remove each suggestion.

    Your photo stays on your iPhone for this.
    """
    static let suggestedTag = "Suggested — check this"
}

/// Something the model found, mapped to a room thing.
struct DetectedObject: Sendable {
    let name: String
    let category: ItemCategory
    /// Fractions of the photo, origin top left (the same space as photo pins).
    let box: CGRect
    let confidence: Float

    var center: CGPoint { CGPoint(x: box.midX, y: box.midY) }
}

enum PhotoDetectionError: LocalizedError {
    case modelMissing, unreadableImage, failed(Error)

    var errorDescription: String? { "Couldn’t look for things in this photo" }
    var recoverySuggestion: String? {
        switch self {
        case .modelMissing: "The detection model is missing from this build. You can still tap the photo to add things by hand."
        case .unreadableImage: "This photo couldn’t be read. Try adding it again."
        case .failed(let error): "Something went wrong (\(error.localizedDescription)). You can still tap the photo to add things by hand."
        }
    }
}

enum PhotoDetector {
    /// The bundled model (Resources/Models/<name>.mlmodel, compiled by Xcode into <name>.mlmodelc).
    /// The full YOLOv3: YOLOv3-tiny missed a large chair filling the frame at any threshold.
    static let modelName = "YOLOv3Int8LUT"

    /// The model's own cut-off for a box (objectness × class score), applied before its NMS.
    /// Its default dropped real things whose label confidence was 0.9, so it's set lower here and
    /// the label confidence is checked below instead.
    static let boxThreshold = 0.15
    static let overlapThreshold = 0.45
    /// Label confidence needed to suggest something.
    static let minimumConfidence: Float = 0.3

    /// COCO labels worth suggesting in a room, and what they become. Both spellings are listed:
    /// this model uses the VOC-style ones ("sofa", "diningtable", "tvmonitor", "pottedplant").
    /// People, food, cups, phones and so on are left out.
    static let roomLabels: [String: (name: String, category: ItemCategory)] = [
        "chair": ("Chair", .chair),
        "sofa": ("Sofa", .sofa), "couch": ("Sofa", .sofa),
        "bed": ("Bed", .bed),
        "diningtable": ("Table", .table), "dining table": ("Table", .table),
        "tvmonitor": ("TV", .television), "tv": ("TV", .television),
        "pottedplant": ("Plant", .plant), "potted plant": ("Plant", .plant),
        "bench": ("Bench", .bench),
        "laptop": ("Laptop", .other),
        "refrigerator": ("Fridge", .appliance),
        "microwave": ("Microwave", .appliance),
        "oven": ("Oven", .appliance),
        "toaster": ("Toaster", .appliance),
        "clock": ("Clock", .other),
        "vase": ("Vase", .other),
        "suitcase": ("Suitcase", .other),
        "bicycle": ("Bicycle", .other),
    ]

    /// Loaded once, on first use, and logged so a missing or broken model is obvious.
    private static let model: Result<VNCoreMLModel, PhotoDetectionError> = {
        guard let url = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") else {
            detectLog.error("[Detect] model \(modelName, privacy: .public).mlmodelc NOT FOUND in the app bundle")
            return .failure(.modelMissing)
        }
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            let ml = try MLModel(contentsOf: url, configuration: config)
            let labels = ml.modelDescription.classLabels as? [String] ?? []
            let inputs = ml.modelDescription.inputDescriptionsByName.keys.sorted().joined(separator: ", ")
            let room = labels.filter { roomLabels[$0] != nil }
            detectLog.notice("[Detect] model loaded: \(modelName, privacy: .public), \(labels.count) labels, inputs: \(inputs, privacy: .public)")
            detectLog.notice("[Detect] labels: \(labels.joined(separator: ", "), privacy: .public)")
            detectLog.notice("[Detect] room labels this model has (\(room.count)): \(room.joined(separator: ", "), privacy: .public)")
            let vn = try VNCoreMLModel(for: ml)
            vn.featureProvider = Thresholds()
            return .success(vn)
        } catch {
            detectLog.error("[Detect] model failed to load: \(error.localizedDescription, privacy: .public)")
            return .failure(.failed(error))
        }
    }()

    /// Supplies the model's optional threshold inputs (Vision passes these alongside the image).
    private final class Thresholds: NSObject, MLFeatureProvider {
        var featureNames: Set<String> { ["iouThreshold", "confidenceThreshold"] }
        func featureValue(for name: String) -> MLFeatureValue? {
            switch name {
            case "iouThreshold": MLFeatureValue(double: overlapThreshold)
            case "confidenceThreshold": MLFeatureValue(double: boxThreshold)
            default: nil
            }
        }
    }

    /// Finds room things in `image`. Runs off the main thread; on-device only.
    static func detect(in image: UIImage) async throws -> [DetectedObject] {
        guard let cgImage = image.cgImage else {
            detectLog.error("[Detect] photo has no CGImage")
            throw PhotoDetectionError.unreadableImage
        }
        // Room photos are saved upright, but a photo straight from the camera may still carry an
        // EXIF rotation; Vision needs it to see the picture the right way up.
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        detectLog.notice("[Detect] photo \(cgImage.width)×\(cgImage.height) px, UIImage orientation \(image.imageOrientation.rawValue) → Vision orientation \(orientation.rawValue)")
        return try await Task.detached(priority: .userInitiated) {
            let vnModel = try model.get()
            let request = VNCoreMLRequest(model: vnModel)
            // Fit the whole photo into the model's 416×416 square without stretching. Vision maps
            // the boxes back onto the full photo.
            request.imageCropAndScaleOption = .scaleFit
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
            let started = Date()
            do { try handler.perform([request]) } catch {
                detectLog.error("[Detect] Vision request failed: \(error.localizedDescription, privacy: .public)")
                throw PhotoDetectionError.failed(error)
            }
            let observations = request.results as? [VNRecognizedObjectObservation] ?? []
            detectLog.notice("[Detect] \(observations.count) raw detections in \(Int(Date().timeIntervalSince(started) * 1000)) ms (box threshold \(boxThreshold))")

            var kept: [DetectedObject] = []
            for (i, observation) in observations.enumerated() {
                let b = observation.boundingBox   // normalised, origin bottom left
                let runnerUp = observation.labels.dropFirst().prefix(2)
                    .map { "\($0.identifier) \(String(format: "%.2f", $0.confidence))" }.joined(separator: ", ")
                guard let top = observation.labels.first else { continue }
                let raw = "#\(i) \(top.identifier) \(String(format: "%.2f", top.confidence)) box(x \(String(format: "%.2f", b.minX)), y \(String(format: "%.2f", b.minY)), w \(String(format: "%.2f", b.width)), h \(String(format: "%.2f", b.height))) next: \(runnerUp)"
                guard let mapped = roomLabels[top.identifier] else {
                    detectLog.notice("[Detect] raw \(raw, privacy: .public) → skipped: not a room label")
                    continue
                }
                guard top.confidence >= minimumConfidence else {
                    detectLog.notice("[Detect] raw \(raw, privacy: .public) → skipped: below \(minimumConfidence)")
                    continue
                }
                // Pins use fractions of the photo with the origin top left, so flip y.
                let box = CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height)
                let object = DetectedObject(name: mapped.name, category: mapped.category, box: box, confidence: top.confidence)
                detectLog.notice("[Detect] raw \(raw, privacy: .public) → kept as \(mapped.name, privacy: .public), pin at x \(String(format: "%.2f", object.center.x)), y \(String(format: "%.2f", object.center.y)) (top-left origin)")
                kept.append(object)
            }
            detectLog.notice("[Detect] \(kept.count) of \(observations.count) kept as suggestions")
            return kept.sorted { $0.confidence > $1.confidence }
        }.value
    }
}

private extension CGImagePropertyOrientation {
    init(_ o: UIImage.Orientation) {
        switch o {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

// MARK: - Suggestions, merged with what the room already has

/// A thing already in the list, as the suggestion merge sees it.
struct ExistingThing: Sendable {
    let id: UUID
    let name: String
    let category: ItemCategory
    /// Its pin on *this* photo, if it has one.
    let pin: CGPoint?
    /// Found by the LiDAR scan (real size and position, but no place on the photo yet).
    let scanned: Bool
    /// Pinned on any photo (this one or another), so it isn't linked to a new suggestion.
    var pinnedAnywhere: Bool = false
}

/// One suggestion in the review sheet.
struct DetectionSuggestion: Identifiable {
    enum Decision { case pending, confirmed, removed }

    let id = UUID()
    var name: String
    let category: ItemCategory
    var pin: CGPoint
    let box: CGRect
    let confidence: Float
    /// A scanned item this probably is. Confirming pins that item here instead of adding another.
    var match: ExistingThing?
    var decision: Decision = .pending
    /// What it was called when suggested, so a rename can be told apart.
    var suggestedName = ""
}

enum DetectionMerge {
    /// Turns detections into suggestions:
    /// * skipped when something of the same kind is already pinned inside the box on this photo;
    /// * linked to a scanned item of the same kind that has no pin on this photo yet (each scanned
    ///   item at most once), so it isn't added twice;
    /// * otherwise a new thing.
    static func suggestions(from detections: [DetectedObject], existing: [ExistingThing]) -> (suggestions: [DetectionSuggestion], skipped: Int) {
        var skipped = 0
        var available = existing.filter { $0.scanned && $0.pin == nil && !$0.pinnedAnywhere }
        var result: [DetectionSuggestion] = []
        for d in detections {   // highest confidence first
            let grown = d.box.insetBy(dx: -0.03, dy: -0.03)
            if existing.contains(where: { thing in
                guard let pin = thing.pin else { return false }
                return grown.contains(pin) && sameKind(thing.category, d.category, thing.name, d.name)
            }) {
                skipped += 1
                continue
            }
            var suggestion = DetectionSuggestion(name: d.name, category: d.category, pin: d.center, box: d.box, confidence: d.confidence)
            if let i = available.firstIndex(where: { sameKind($0.category, d.category, $0.name, d.name) }) {
                suggestion.match = available.remove(at: i)
                suggestion.name = suggestion.match!.name
            }
            suggestion.suggestedName = suggestion.name
            result.append(suggestion)
        }
        // Read top to bottom, left to right, like the photo.
        result.sort { ($0.pin.y, $0.pin.x) < ($1.pin.y, $1.pin.x) }
        return (result, skipped)
    }

    /// "Chair" matches an armchair, "Table" a desk or side table, and so on. "Something else"
    /// only matches by name.
    static func sameKind(_ a: ItemCategory, _ b: ItemCategory, _ nameA: String, _ nameB: String) -> Bool {
        if a == .other || b == .other { return nameA.lowercased() == nameB.lowercased() }
        if a == b { return true }
        let families: [Set<ItemCategory>] = [
            [.chair, .armchair], [.sofa, .armchair], [.table, .desk, .sideTable, .nightstand],
        ]
        return families.contains { $0.contains(a) && $0.contains(b) }
    }
}
