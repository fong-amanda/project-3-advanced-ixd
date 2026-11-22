import ARKit
import RoomPlan
import SwiftUI

/// What the scan can and can't do, said plainly. RoomPlan finds walls, doors, windows and large
/// furniture; it doesn't see small things or know what anything is worth.
enum ScanCopy {
    /// Shown before a scan starts (on the "Scan with LiDAR" tiles) and while scanning.
    static let before = "We’ll detect large furniture like beds, desks and shelves. Small things, and things we don’t recognize, won’t appear. You can add them by hand."

    /// Shown above the list of what the scan found.
    static func found(_ count: Int) -> String {
        switch count {
        case 0: "We didn’t find any furniture. Add what’s in the room by hand."
        case 1: "We found 1 thing. Check it and add what we missed."
        default: "We found \(count) things. Check each one and add what we missed."
        }
    }
}

/// Scan a room with LiDAR (RoomPlan): walk around, tap Done, check what was found, use it.
/// Hands back the walls, doors, windows, ceiling height and furniture in room coordinates.
struct ScanFlowView: View {
    var onUse: (ScanResult, CapturedRoom) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .scanning
    @State private var stopRequest = 0

    private enum Phase {
        case scanning, processing
        case review(ScanResult, CapturedRoom)
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .scanning, .processing:
            ZStack(alignment: .bottom) {
                RoomCaptureRepresentable(stopRequest: stopRequest) { result in
                    switch result {
                    case .success(let capture):
                        let room = capture.room
                        if var converted = ScanImporter.convert(room) {
                            converted.worldMap = capture.worldMap
                            phase = .review(converted, room)
                        }
                        else { phase = .failed("We couldn’t find enough walls. Try scanning again, slowly, along every wall.") }
                    case .failure(let error):
                        phase = .failed(error.localizedDescription)
                    }
                }
                .ignoresSafeArea()
                VStack(spacing: Space.s) {
                    if case .processing = phase {
                        ProgressView("Putting the room together…").tint(.accent).foregroundStyle(Color.textPrimary)
                    } else {
                        Text("Walk slowly around the room and point at every wall, door and window.")
                            .textRole(.body).multilineTextAlignment(.center)
                        Text(ScanCopy.before)
                            .textRole(.secondary).multilineTextAlignment(.center)
                        Button("Done scanning") { phase = .processing; stopRequest += 1 }
                            .buttonStyle(.app(.primary))
                    }
                }
                .padding(Space.l)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.cardLarge, style: .continuous))
                .elevation(.floating)
                .padding(Space.page)
            }
            .navigationTitle("Scan the room")
        case .review(let result, let room):
            ScanReview(result: result) {
                onUse(result, room)
                dismiss()
            } onRescan: {
                phase = .scanning
            }
            .navigationTitle("Check the scan")
        case .failed(let message):
            ContentUnavailableView {
                Label("The scan didn’t work", systemImage: "viewfinder")
            } description: {
                Text(message)
            } actions: {
                Button("Scan again") { phase = .scanning }.buttonStyle(.app(.primary, width: .hug))
            }
            .navigationTitle("Scan the room")
        }
    }
}

/// What the scan found, before it's used.
private struct ScanReview: View {
    let result: ScanResult
    var onUse: () -> Void
    var onRescan: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                Canvas { c, size in
                    let b = result.shape.bounds
                    let t = PlanTransform(fitting: size, width: b.maxX, length: b.maxZ)
                    ShapeDrawing.drawFloor(result.shape, t, fill: .surface, in: &c)
                    for o in result.objects {
                        let f = RoomGeometry.footprint(x: o.x, z: o.z, w: o.w, d: o.d, yawDeg: o.yawDeg)
                        let r = t.rect(f)
                        c.fill(Path(roundedRect: r, cornerRadius: Radius.drawing), with: .color(.surfaceMuted))
                        c.stroke(Path(roundedRect: r, cornerRadius: Radius.drawing), with: .color(.outlineStrong), lineWidth: Stroke.regular)
                    }
                    ShapeDrawing.drawWalls(result.shape, t, in: &c)
                    ShapeDrawing.drawOpenings(result.shape, t, in: &c)
                }
                .aspectRatio(max(result.shape.bounds.maxX, 1) / max(result.shape.bounds.maxZ, 1), contentMode: .fit)
                .padding(Space.m)
                .card()
                .accessibilityLabel("Scanned floor plan with \(result.objects.count) things")

                let doors = result.shape.openings.filter { $0.kind == .door }.count
                let windows = result.shape.openings.count - doors
                Text("\(UnitSystem.feet.roomLength(result.shape.bounds.maxX)) × \(UnitSystem.feet.roomLength(result.shape.bounds.maxZ)), ceiling \(UnitSystem.feet.roomLength(result.heightCm)) · \(result.shape.corners.count) walls, \(doors) door\(doors == 1 ? "" : "s"), \(windows) window\(windows == 1 ? "" : "s")")
                    .textRole(.secondary)
                Text(ScanCopy.found(result.objects.count)).textRole(.body)
                if !result.objects.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(result.objects) { o in
                            HStack(spacing: Space.m) {
                                CategoryGlyph(category: o.category, side: Size.iconCircle)
                                    .frame(width: Size.iconCircle, height: Size.iconCircle)
                                    .clipShape(RoundedRectangle(cornerRadius: Radius.thumb))
                                Text(o.name).textRole(.body)
                                Spacer()
                                Text(UnitSystem.feet.dims(o.w, o.d, o.h)).textRole(.secondary)
                            }
                            .padding(.horizontal, Space.m)
                            .frame(minHeight: Size.tapTarget + Space.s)
                            .accessibilityElement(children: .combine)
                            Hairline(inset: Space.m)
                        }
                    }
                    .listGroup()
                    Text("Next you can rename them and say whose they are. Things the scan didn’t pick up, like boxes or a guitar, you add from the photo or by hand.")
                        .textRole(.hint)
                }
                Button("Use this scan", action: onUse).buttonStyle(.app(.primary))
                Button("Scan again", action: onRescan).buttonStyle(.app(.primary, size: .compact)).frame(maxWidth: .infinity)
            }
            .pagePadding()
        }
        .pageBackground()
    }
}

/// Apple's RoomCaptureView: live scanning with its own coaching.
private struct RoomCaptureRepresentable: UIViewRepresentable {
    let stopRequest: Int
    var onFinish: (Result<ScanCapture, Error>) -> Void

    struct ScanCapture {
        let room: CapturedRoom
        let worldMap: ARWorldMap?
    }

    func makeUIView(context: Context) -> RoomCaptureView {
        let view = RoomCaptureView(frame: .zero)
        view.delegate = context.coordinator
        view.captureSession.run(configuration: RoomCaptureSession.Configuration())
        return view
    }

    func updateUIView(_ view: RoomCaptureView, context: Context) {
        context.coordinator.onFinish = onFinish
        if stopRequest != context.coordinator.stopRequest {
            context.coordinator.stopRequest = stopRequest
            // Keep ARKit's map of the room (on this phone only) so AR can line up with it later,
            // then finish the scan. A map that isn't ready is simply skipped.
            let coordinator = context.coordinator
            view.captureSession.arSession.getCurrentWorldMap { map, _ in
                DispatchQueue.main.async {
                    coordinator.worldMap = map
                    view.captureSession.stop()
                }
            }
        }
    }

    static func dismantleUIView(_ view: RoomCaptureView, coordinator: Coordinator) {
        view.captureSession.stop()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    @objc(SSRoomCaptureCoordinator)
    final class Coordinator: NSObject, RoomCaptureViewDelegate {
        var onFinish: (Result<ScanCapture, Error>) -> Void
        var stopRequest = 0
        var worldMap: ARWorldMap?

        init(onFinish: @escaping (Result<ScanCapture, Error>) -> Void) { self.onFinish = onFinish }

        // RoomCaptureViewDelegate requires NSCoding; the coordinator is never archived.
        required init?(coder: NSCoder) { nil }
        func encode(with coder: NSCoder) {}

        func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: (any Error)?) -> Bool { true }

        func captureView(didPresent processedResult: CapturedRoom, error: (any Error)?) {
            let finish = onFinish
            DispatchQueue.main.async { [weak self] in
                if let error { finish(.failure(error)) }
                else { finish(.success(ScanCapture(room: processedResult, worldMap: self?.worldMap))) }
            }
        }
    }
}
