import CoreML
import CoreVideo
import UIKit
import Vision

import os

// "Find things in this photo", entirely on the iPhone. Nothing here touches the network, and the
// photo and its crops are never written to disk or sent anywhere. Three steps, all Apple frameworks:
//
// 1. YOLOv3 (Apple's Core ML build, 8-bit weights; YOLO License = public domain, see
//    Resources/Models/LICENSE-YOLOv3.txt) names furniture and common belongings from its 80 types.
// 2. Vision's foreground instance mask finds every other separate object, named or not.
// 3. Vision's built-in image classifier names what it can of those, from a crop held in memory.
//
// Results are only *suggestions*: the person confirms, renames or removes each one in
// DetectionReviewSheet before anything is added, and names the ones nothing recognised.
//
// Every step logs a "[Detect]" line (Xcode console, or Console.app filtered on "[Detect]").

/// "[Detect] …" lines. Labels and numbers only: never the photo or anything personal.
let detectLog = Logger(subsystem: "com.amandafong.sharedspace", category: "Detect")

/// The words around detection, shared by the photo step, the review sheet and the design system page.
enum DetectionCopy {
    static let photoStepLead = "Add a photo and we’ll use AI on your iPhone to suggest the things in it. You’ll check each one before it’s added."
    static let howTitle = "How we find things in your photo"
    // "for this": detection never sends the photo anywhere, but a saved room photo is shared with
    // the other person through Storage (SyncEngine.savePhoto), so a blanket claim wouldn't be true.
    static let howMessage = """
    AI on your iPhone finds separate objects in your photo and names the ones it recognizes. It can miss things or get names wrong.

    You’ll name the rest and check each one before it’s added.

    Your photo never leaves your iPhone for this.
    """
    static let suggestedTag = "Suggested — check this"
    /// An object found on the photo that nothing could name.
    static let unnamedPrompt = "Something here — what is it?"
    static let unnamedPin = "Something here"
}

/// Something found on the photo, mapped to a room thing.
struct DetectedObject: Sendable {
    enum Source: String, Sendable {
        /// Named by YOLOv3.
        case objectModel = "YOLOv3"
        /// Found as a separate object and named by Vision's classifier.
        case classifier
        /// Found as a separate object, but nothing could name it: the person does.
        case unnamed
    }

    /// Empty when `source` is `.unnamed`.
    let name: String
    let category: ItemCategory
    /// Fractions of the photo, origin top left (the same space as photo pins).
    let box: CGRect
    let confidence: Float
    let source: Source

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

    // MARK: YOLOv3 settings

    /// The model's own cut-off for a box (objectness × class score), applied before its NMS.
    /// Its default dropped real things whose label confidence was 0.9, so it's set lower here and
    /// the label confidence is checked below instead.
    static let boxThreshold = 0.15
    static let overlapThreshold = 0.45
    /// Label confidence needed to suggest something furniture-sized…
    static let minimumConfidence: Float = 0.3
    /// …and something small (a box under `smallObjectArea` of the photo), which the model is less
    /// sure of: a cup or a phone across a room rarely scores as high as a sofa.
    static let smallObjectConfidence: Float = 0.25
    static let smallObjectArea: CGFloat = 0.05
    /// Kept boxes overlapping more than this (intersection over union) are one thing: only the more
    /// confident label is suggested. A cup on a table covers a sliver of the table's box, so the
    /// overlap is tiny and the table never hides it.
    static let duplicateOverlap: CGFloat = 0.5

    // MARK: Instance and classifier settings

    /// Separate objects smaller than this share of the photo are specks, not things.
    static let minimumInstanceArea: CGFloat = 0.0015
    /// Classifier confidence needed to suggest its name; below it the person names the object.
    static let classifierConfidence: Float = 0.5

    /// YOLOv3 labels worth suggesting, and what they become. Everything except labels that are
    /// never a belonging: people, animals, vehicles, food and street furniture. Both spellings are
    /// listed for the furniture: this model uses the VOC-style ones ("sofa", "diningtable",
    /// "tvmonitor", "pottedplant").
    static let belongingLabels: [String: (name: String, category: ItemCategory)] = [
        // Furniture, fixtures and appliances
        "chair": ("Chair", .chair),
        "sofa": ("Sofa", .sofa), "couch": ("Sofa", .sofa),
        "bed": ("Bed", .bed),
        "diningtable": ("Table", .table), "dining table": ("Table", .table),
        "bench": ("Bench", .bench),
        "tvmonitor": ("TV", .television), "tv": ("TV", .television),
        "pottedplant": ("Plant", .plant), "potted plant": ("Plant", .plant),
        "refrigerator": ("Fridge", .appliance),
        "microwave": ("Microwave", .appliance),
        "oven": ("Oven", .appliance),
        "toaster": ("Toaster", .appliance),
        "sink": ("Sink", .other),
        "toilet": ("Toilet", .other),
        // Electronics
        "laptop": ("Laptop", .other),
        "keyboard": ("Keyboard", .other),
        "mouse": ("Mouse", .other),
        "remote": ("Remote", .other),
        "cell phone": ("Phone", .other),
        "clock": ("Clock", .other),
        "hair drier": ("Hair dryer", .other),
        // Kitchen things
        "cup": ("Cup", .other),
        "bottle": ("Bottle", .other),
        "wine glass": ("Wine glass", .other),
        "bowl": ("Bowl", .other),
        "fork": ("Fork", .other), "knife": ("Knife", .other), "spoon": ("Spoon", .other),
        // Bags and everyday things
        "backpack": ("Backpack", .other),
        "handbag": ("Handbag", .other),
        "suitcase": ("Suitcase", .other),
        "umbrella": ("Umbrella", .other),
        "tie": ("Tie", .other),
        "book": ("Book", .other),
        "vase": ("Vase", .other),
        "scissors": ("Scissors", .other),
        "teddy bear": ("Teddy bear", .other),
        "toothbrush": ("Toothbrush", .other),
        // Sports things
        "sports ball": ("Ball", .other),
        "tennis racket": ("Tennis racket", .other),
        "baseball bat": ("Baseball bat", .other),
        "baseball glove": ("Baseball glove", .other),
        "skateboard": ("Skateboard", .other),
        "surfboard": ("Surfboard", .other),
        "skis": ("Skis", .other),
        "snowboard": ("Snowboard", .other),
        "frisbee": ("Frisbee", .other),
        "kite": ("Kite", .other),
        // A vehicle, but usually kept indoors and moved with everything else.
        "bicycle": ("Bicycle", .other),
    ]

    /// Classifier labels that describe a scene, a material or a broad group rather than one thing
    /// ("structure", "textile", "living_room"). Skipped when picking a name.
    static let genericClassifierLabels: Set<String> = [
        "structure", "material", "textile", "wood_natural", "wood_processed", "raw_glass", "liquid",
        "interior_room", "living_room", "bedroom", "dining_room", "kitchen", "kitchen_room", "bathroom",
        "bathroom_room", "classroom", "interior_shop", "building", "outdoor", "sky", "light", "art",
        "document", "screenshot", "container", "tableware", "furniture", "consumer_electronics",
    ]
    /// Classifier labels that map to a room thing's kind.
    static let classifierCategories: [String: ItemCategory] = [
        "chair": .chair, "chair_other": .chair, "folding_chair": .chair, "swivel_chair": .chair,
        "high_chair": .chair, "armchair": .armchair, "sofa": .sofa, "bed": .bed, "table": .table,
        "desk": .desk, "bench": .bench, "bookshelf": .bookshelf, "cabinet": .cabinet, "lamp": .lamp,
        "plant": .plant, "decorative_plant": .plant, "guitar": .guitar, "television": .television,
        "appliance": .appliance,
    ]
    /// Classifier labels whose words don't read as a name on their own.
    static let classifierNames: [String: String] = [
        "chair_other": "Chair", "decorative_plant": "Plant", "basket_container": "Basket",
        "iron_clothing": "Iron", "straw_drinking": "Straw", "drinking_glass": "Glass", "tea_drink": "Tea",
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
            let kept = labels.filter { belongingLabels[$0] != nil }
            let dropped = labels.filter { belongingLabels[$0] == nil }
            detectLog.notice("[Detect] model loaded: \(modelName, privacy: .public), \(labels.count) labels, inputs: \(inputs, privacy: .public)")
            detectLog.notice("[Detect] labels suggested (\(kept.count)): \(kept.joined(separator: ", "), privacy: .public)")
            detectLog.notice("[Detect] labels never suggested (\(dropped.count)): \(dropped.joined(separator: ", "), privacy: .public)")
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

    // MARK: Detection

    /// Finds things in `image`. Runs off the main thread; on-device only.
    static func detect(in image: UIImage) async throws -> [DetectedObject] {
        // Every step works on one upright copy, so YOLOv3's boxes, the instance mask and the crops
        // share the same pixels, and pins land where they're drawn. Room photos are saved upright
        // already; a photo straight from the camera may carry an EXIF rotation, drawn in here.
        let upright = image.normalisedUp()
        guard let cgImage = upright.cgImage else {
            detectLog.error("[Detect] photo has no CGImage")
            throw PhotoDetectionError.unreadableImage
        }
        detectLog.notice("[Detect] photo \(cgImage.width)×\(cgImage.height) px (UIImage orientation \(image.imageOrientation.rawValue)\(image.imageOrientation == .up ? "" : ", redrawn upright", privacy: .public))")
        return try await Task.detached(priority: .userInitiated) {
            let named = try findWithObjectModel(in: cgImage)
            let others = findOtherObjects(in: cgImage, besides: named)
            let classified = others.filter { $0.source == .classifier }.count
            detectLog.notice("[Detect] total \(named.count + others.count): \(named.count) named by YOLOv3, \(classified) named by the classifier, \(others.count - classified) for you to name")
            return named + others
        }.value
    }

    /// Step 1: YOLOv3. Logs every raw detection before any filtering.
    private static func findWithObjectModel(in cgImage: CGImage) throws -> [DetectedObject] {
        let vnModel = try model.get()
        let request = VNCoreMLRequest(model: vnModel)
        // Fit the whole photo into the model's 416×416 square without stretching. Vision maps the
        // boxes back onto the full photo.
        request.imageCropAndScaleOption = .scaleFit
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
        let started = Date()
        do { try handler.perform([request]) } catch {
            detectLog.error("[Detect] YOLOv3 request failed: \(error.localizedDescription, privacy: .public)")
            throw PhotoDetectionError.failed(error)
        }
        let observations = request.results as? [VNRecognizedObjectObservation] ?? []
        detectLog.notice("[Detect] YOLOv3: \(observations.count) raw detections in \(ms(since: started)) ms (box threshold \(boxThreshold))")

        var candidates: [DetectedObject] = []
        for (i, observation) in observations.enumerated() {
            guard let top = observation.labels.first else { continue }
            // Vision's boxes are normalised with the origin bottom left; pins use top left, so flip y.
            let b = observation.boundingBox
            let box = CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height)
            let runnerUp = observation.labels.dropFirst().prefix(2)
                .map { "\($0.identifier) \(f($0.confidence))" }.joined(separator: ", ")
            let raw = "YOLOv3 raw #\(i): \(top.identifier) \(f(top.confidence)) box \(describe(box)) next: \(runnerUp)"
            guard let mapped = belongingLabels[top.identifier] else {
                detectLog.notice("[Detect] \(raw, privacy: .public) → dropped: never a belonging")
                continue
            }
            let small = box.width * box.height < smallObjectArea
            let needed = small ? smallObjectConfidence : minimumConfidence
            guard top.confidence >= needed else {
                detectLog.notice("[Detect] \(raw, privacy: .public) → dropped: below \(f(needed)) (\(small ? "small" : "large", privacy: .public) object)")
                continue
            }
            detectLog.notice("[Detect] \(raw, privacy: .public) → candidate \(mapped.name, privacy: .public)")
            candidates.append(DetectedObject(name: mapped.name, category: mapped.category, box: box,
                                             confidence: top.confidence, source: .objectModel))
        }

        // Non-max suppression across labels, so one thing isn't suggested twice under two names.
        var kept: [DetectedObject] = []
        for candidate in candidates.sorted(by: { $0.confidence > $1.confidence }) {
            if let twin = kept.first(where: { iou($0.box, candidate.box) > duplicateOverlap }) {
                detectLog.notice("[Detect] YOLOv3 \(candidate.name, privacy: .public) \(f(candidate.confidence)) → dropped: same box as \(twin.name, privacy: .public) \(f(twin.confidence))")
                continue
            }
            kept.append(candidate)
            detectLog.notice("[Detect] YOLOv3 \(candidate.name, privacy: .public) \(f(candidate.confidence)) → kept, pin at \(describe(candidate.center), privacy: .public)")
        }
        detectLog.notice("[Detect] YOLOv3: \(kept.count) of \(observations.count) kept")
        return kept
    }

    /// Steps 2 and 3: every separate object Vision can cut out, minus those YOLOv3 already named,
    /// named by the classifier where it's confident. A failure here only loses these extras.
    private static func findOtherObjects(in cgImage: CGImage, besides named: [DetectedObject]) -> [DetectedObject] {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
        let started = Date()
        do { try handler.perform([request]) } catch {
            detectLog.error("[Detect] instance masks failed: \(error.localizedDescription, privacy: .public). Showing YOLOv3's results only.")
            return []
        }
        guard let observation = request.results?.first else {
            detectLog.notice("[Detect] instances: none found in \(ms(since: started)) ms")
            return []
        }
        let boxes = instanceBoxes(observation)
        detectLog.notice("[Detect] instances: \(boxes.count) found in \(ms(since: started)) ms")

        var found: [DetectedObject] = []
        for (instance, box) in boxes.sorted(by: { $0.key < $1.key }) {
            let raw = "instance #\(instance) box \(describe(box))"
            guard box.width * box.height >= minimumInstanceArea else {
                detectLog.notice("[Detect] \(raw, privacy: .public) → dropped: too small")
                continue
            }
            if let same = named.first(where: { isSameObject(named: $0.box, instance: box) }) {
                detectLog.notice("[Detect] \(raw, privacy: .public) → skipped: YOLOv3 already found it (\(same.name, privacy: .public))")
                continue
            }
            if let label = classify(cgImage, box: box, instance: instance) {
                detectLog.notice("[Detect] \(raw, privacy: .public) → named \(label.name, privacy: .public), pin at \(describe(CGPoint(x: box.midX, y: box.midY)), privacy: .public)")
                found.append(DetectedObject(name: label.name, category: label.category, box: box,
                                            confidence: label.confidence, source: .classifier))
            } else {
                detectLog.notice("[Detect] \(raw, privacy: .public) → for you to name, pin at \(describe(CGPoint(x: box.midX, y: box.midY)), privacy: .public)")
                found.append(DetectedObject(name: "", category: .other, box: box, confidence: 0, source: .unnamed))
            }
        }
        return found
    }

    /// An instance is the thing YOLOv3 already named when their boxes mostly coincide. A cup inside
    /// a table's box is not the table: the table's box is many times bigger, so the cup is kept.
    static func isSameObject(named a: CGRect, instance b: CGRect) -> Bool {
        if iou(a, b) > 0.5 { return true }
        let smaller = min(area(a), area(b)), larger = max(area(a), area(b))
        guard smaller > 0 else { return false }
        return area(a.intersection(b)) / smaller > 0.8 && larger / smaller < 2.5
    }

    /// Each instance's box, as fractions of the photo with the origin top left. The mask spans the
    /// whole (upright) photo and its rows run top to bottom, so unlike `boundingBox` there's no
    /// y flip here.
    private static func instanceBoxes(_ observation: VNInstanceMaskObservation) -> [Int: CGRect] {
        let mask = observation.instanceMask
        let format = CVPixelBufferGetPixelFormatType(mask)
        guard format == kCVPixelFormatType_OneComponent8 else {
            detectLog.error("[Detect] instance mask has unexpected pixel format \(format)")
            return [:]
        }
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(mask) else { return [:] }
        let width = CVPixelBufferGetWidth(mask), height = CVPixelBufferGetHeight(mask)
        let rowBytes = CVPixelBufferGetBytesPerRow(mask)
        var minX = [Int](repeating: .max, count: 256), minY = minX
        var maxX = [Int](repeating: -1, count: 256), maxY = maxX
        for y in 0..<height {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width {
                let v = Int(row[x])   // 0 is background, otherwise the instance number
                guard v != 0 else { continue }
                if x < minX[v] { minX[v] = x }
                if x > maxX[v] { maxX[v] = x }
                if y < minY[v] { minY[v] = y }
                if y > maxY[v] { maxY[v] = y }
            }
        }
        detectLog.notice("[Detect] instance mask \(width)×\(height), instances \(observation.allInstances.map(String.init).joined(separator: ", "), privacy: .public)")
        let w = CGFloat(width), h = CGFloat(height)
        var boxes: [Int: CGRect] = [:]
        for i in observation.allInstances where i < 256 && maxX[i] >= 0 {
            boxes[i] = CGRect(x: CGFloat(minX[i]) / w, y: CGFloat(minY[i]) / h,
                              width: CGFloat(maxX[i] - minX[i] + 1) / w, height: CGFloat(maxY[i] - minY[i] + 1) / h)
        }
        return boxes
    }

    /// Names one object from a crop around its box, if the classifier is confident. The crop only
    /// lives in memory for this call.
    private static func classify(_ cgImage: CGImage, box: CGRect, instance: Int) -> (name: String, category: ItemCategory, confidence: Float)? {
        let w = CGFloat(cgImage.width), h = CGFloat(cgImage.height)
        // CGImage cropping uses pixels with the origin top left, like `box`. A small margin lets
        // the classifier see the object's edges.
        let pixels = CGRect(x: box.minX * w, y: box.minY * h, width: box.width * w, height: box.height * h)
        let margin = max(pixels.width, pixels.height) * 0.1
        let rect = pixels.insetBy(dx: -margin, dy: -margin).intersection(CGRect(x: 0, y: 0, width: w, height: h)).integral
        guard let crop = cgImage.cropping(to: rect) else { return nil }
        let request = VNClassifyImageRequest()
        do { try VNImageRequestHandler(cgImage: crop, orientation: .up).perform([request]) } catch {
            detectLog.error("[Detect] classifier failed on instance #\(instance): \(error.localizedDescription, privacy: .public)")
            return nil
        }
        let labels = (request.results ?? []).sorted { $0.confidence > $1.confidence }
        let top = labels.prefix(5).map { "\($0.identifier) \(f($0.confidence))" }.joined(separator: ", ")
        detectLog.notice("[Detect] classifier on instance #\(instance) (\(Int(rect.width))×\(Int(rect.height)) px crop): \(top, privacy: .public)")
        guard let best = labels.first(where: { !genericClassifierLabels.contains($0.identifier) }),
              best.confidence > classifierConfidence else { return nil }
        let name = classifierNames[best.identifier]
            ?? best.identifier.replacingOccurrences(of: "_", with: " ").capitalizedFirst
        return (name, classifierCategories[best.identifier] ?? .other, best.confidence)
    }

    // MARK: Geometry and log helpers

    static func area(_ r: CGRect) -> CGFloat { r.isNull || r.isEmpty ? 0 : r.width * r.height }

    static func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let shared = area(a.intersection(b))
        let union = area(a) + area(b) - shared
        return union > 0 ? shared / union : 0
    }

    private static func ms(since start: Date) -> Int { Int(Date().timeIntervalSince(start) * 1000) }
    private static func f(_ x: Float) -> String { String(format: "%.2f", x) }
    private static func describe(_ r: CGRect) -> String {
        String(format: "(x %.2f, y %.2f, w %.2f, h %.2f, top-left origin)", r.minX, r.minY, r.width, r.height)
    }
    private static func describe(_ p: CGPoint) -> String { String(format: "x %.2f, y %.2f", p.x, p.y) }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
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
    let source: DetectedObject.Source
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
    /// * a small object that isn't from YOLOv3 is skipped when anything is already pinned inside
    ///   its box: its tight outline means that pin is this object, whatever the person called it
    ///   (an "AirPod" the classifier would call "Headphones");
    /// * otherwise a new thing.
    static func suggestions(from detections: [DetectedObject], existing: [ExistingThing]) -> (suggestions: [DetectionSuggestion], skipped: Int, merged: Int) {
        let unique = mergeDuplicates(detections)
        var skipped = 0
        var available = existing.filter { $0.scanned && $0.pin == nil && !$0.pinnedAnywhere }
        var result: [DetectionSuggestion] = []
        for d in unique {   // best named first
            let grown = d.box.insetBy(dx: -0.03, dy: -0.03)
            let tightOutline = d.source != .objectModel && PhotoDetector.area(d.box) < 0.1
            if existing.contains(where: { thing in
                guard let pin = thing.pin else { return false }
                if tightOutline { return d.box.contains(pin) }
                return grown.contains(pin) && sameKind(thing.category, d.category, thing.name, d.name)
            }) {
                skipped += 1
                continue
            }
            var suggestion = DetectionSuggestion(name: d.name, category: d.category, pin: d.center, box: d.box,
                                                 confidence: d.confidence, source: d.source)
            if !d.name.isEmpty, let i = available.firstIndex(where: { sameKind($0.category, d.category, $0.name, d.name) }) {
                suggestion.match = available.remove(at: i)
                suggestion.name = suggestion.match!.name
            }
            suggestion.suggestedName = suggestion.name
            result.append(suggestion)
        }
        // Read top to bottom, left to right, like the photo.
        result.sort { ($0.pin.y, $0.pin.x) < ($1.pin.y, $1.pin.x) }
        return (result, skipped, detections.count - unique.count)
    }

    /// One suggestion per object. Two finds are the same object when their pins nearly touch, or
    /// when one box sits almost entirely inside a box that isn't many times bigger (two pins on
    /// one bottle). A cup on a table is kept apart: the table's box is far bigger than the cup's.
    /// The one kept is the best named: YOLOv3, then the classifier, then unnamed; then confidence.
    static func mergeDuplicates(_ detections: [DetectedObject]) -> [DetectedObject] {
        func rank(_ s: DetectedObject.Source) -> Int { s == .objectModel ? 0 : s == .classifier ? 1 : 2 }
        let ordered = detections.sorted { (rank($0.source), -$0.confidence) < (rank($1.source), -$1.confidence) }
        var kept: [DetectedObject] = []
        for d in ordered {
            if let twin = kept.first(where: { sameObject($0, d) }) {
                detectLog.notice("[Detect] merged \(d.name.isEmpty ? "unnamed" : d.name, privacy: .public) (\(d.source.rawValue, privacy: .public)) into \(twin.name.isEmpty ? "unnamed" : twin.name, privacy: .public) (\(twin.source.rawValue, privacy: .public)): same object")
                continue
            }
            kept.append(d)
        }
        return kept
    }

    static func sameObject(_ a: DetectedObject, _ b: DetectedObject) -> Bool {
        let dx = a.center.x - b.center.x, dy = a.center.y - b.center.y
        if (dx * dx + dy * dy).squareRoot() < 0.03 { return true }
        let small = min(PhotoDetector.area(a.box), PhotoDetector.area(b.box))
        let large = max(PhotoDetector.area(a.box), PhotoDetector.area(b.box))
        guard small > 0 else { return false }
        return PhotoDetector.area(a.box.intersection(b.box)) / small > 0.7 && large / small < 6
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
