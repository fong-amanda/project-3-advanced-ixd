import SwiftUI

/// "Find things in this photo": shows what on-device detection found as numbered suggestions on the
/// photo. Nothing is added until the person confirms each one (they can rename or remove it too).
struct DetectionReviewSheet: View {
    let image: UIImage
    /// What's already listed, so things already pinned aren't suggested and scanned things are linked.
    let existing: [ExistingThing]
    /// The confirmed suggestions (renamed as the person left them).
    var onConfirm: ([DetectionSuggestion]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: Phase = .detecting
    @State private var suggestions: [DetectionSuggestion] = []
    @State private var skipped = 0
    @State private var selected: UUID?

    private enum Phase { case detecting, done, failed(PhotoDetectionError) }

    static let privacyNote = "Detection runs on your iPhone. Your photo isn’t uploaded for this."

    private var confirmed: [DetectionSuggestion] { suggestions.filter { $0.decision == .confirmed } }
    private var pending: Int { suggestions.filter { $0.decision == .pending }.count }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.l) {
                        NoteBar(text: Self.privacyNote, symbol: "lock.iphone")
                        content(proxy)
                    }
                    .padding(Space.page)
                    .padding(.bottom, Space.xl)
                }
            }
            .safeAreaInset(edge: .bottom) { if case .done = phase, !suggestions.isEmpty { footer } }
            .appSheet()
            .appNavigation("Things in this photo")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task { await detect() }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(!confirmed.isEmpty)
    }

    @ViewBuilder private func content(_ proxy: ScrollViewProxy) -> some View {
        switch phase {
        case .detecting:
            VStack(spacing: Space.m) {
                ProgressView()
                Text("Looking for furniture and other things…").textRole(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: Size.previewImageMax)
            .accessibilityElement(children: .combine)

        case .failed(let error):
            NoteBar(text: "\(error.errorDescription ?? ""). \(error.recoverySuggestion ?? "")",
                    symbol: "exclamationmark.triangle", tone: .warning)

        case .done:
            PhotoWithPins(
                image: image,
                pins: visible.map { i, s in
                    PhotoPin(id: s.id, number: i + 1, label: s.name, point: s.pin, isSelected: s.id == selected)
                },
                onTapPin: { id in
                    selected = selected == id ? nil : id
                    withMotion(reduceMotion: reduceMotion) { proxy.scrollTo(id, anchor: .center) }
                },
                onMovePin: { id, point in
                    if let i = suggestions.firstIndex(where: { $0.id == id }) { suggestions[i].pin = point }
                })
            .clipShape(RoundedRectangle(cornerRadius: Radius.cardLarge, style: .continuous))

            Text(summary).textRole(.secondary)
            if skipped > 0 {
                Text("\(skipped) \(skipped == 1 ? "thing is" : "things are") already in your list, so \(skipped == 1 ? "it isn’t" : "they aren’t") suggested again.")
                    .textRole(.hint)
            }
            ForEach(Array(suggestions.indices), id: \.self) { i in
                row($suggestions[i], number: number(of: suggestions[i].id)).id(suggestions[i].id)
            }
        }
    }

    /// Suggestions still on the photo (removed ones lose their pin), numbered in order.
    private var visible: [(Int, DetectionSuggestion)] {
        Array(suggestions.filter { $0.decision != .removed }.enumerated())
    }

    private func number(of id: UUID) -> Int? {
        visible.first { $0.1.id == id }.map { $0.0 + 1 }
    }

    private var summary: String {
        switch suggestions.count {
        case 0: "Nothing to suggest in this photo. You can still tap the photo to add things by hand."
        case 1: "Found 1 thing. Check it: confirm it, rename it, or remove it. Drag its number if it’s in the wrong place."
        default: "Found \(suggestions.count) things. Check each one: confirm it, rename it, or remove it. Drag a number if it’s in the wrong place."
        }
    }

    // MARK: Rows

    @ViewBuilder private func row(_ s: Binding<DetectionSuggestion>, number: Int?) -> some View {
        let item = s.wrappedValue
        if item.decision == .removed {
            HStack(spacing: Space.m) {
                Text("Removed: \(item.name)").textRole(.secondary).strikethrough()
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Undo") { set(s, .pending) }
                    .buttonStyle(.app(.neutral, size: .compact)).fixedSize()
            }
            .padding(.horizontal, Space.l).padding(.vertical, Space.s)
            .accessibilityElement(children: .combine)
        } else {
            VStack(alignment: .leading, spacing: Space.m) {
                HStack(alignment: .top, spacing: Space.m) {
                    NumberBadge(number: number ?? 0, isSelected: item.id == selected, size: Size.tick)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Space.s) {
                        // Renaming counts as checking it: the person has looked at this one.
                        TextField("Name", text: Binding(get: { s.wrappedValue.name }, set: { new in
                            s.wrappedValue.name = new
                            if s.wrappedValue.decision == .pending && new != s.wrappedValue.suggestedName {
                                s.wrappedValue.decision = .confirmed
                            }
                        }))
                            .font(.bodyStrong)
                            .foregroundStyle(Color.textPrimary)
                            .textInputAutocapitalization(.sentences)
                            .submitLabel(.done)
                            .frame(minHeight: Size.tapTarget)
                            .padding(.horizontal, Space.m)
                            .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                                .strokeBorder(Color.outlineStrong, lineWidth: Stroke.regular))
                            .accessibilityLabel("Name of suggestion \(number ?? 0)")
                        if item.decision == .confirmed {
                            AppTag(kind: .tone(.sage), text: "Confirmed", symbol: "checkmark")
                        } else {
                            AppTag(kind: .suggestion, text: DetectionCopy.suggestedTag, symbol: "questionmark.circle")
                        }
                        if let match = item.match {
                            Text("Looks like “\(match.name)” from your scan. Confirming puts its number here instead of adding it twice.")
                                .textRole(.hint)
                        }
                    }
                }
                AdaptiveStack(spacing: Space.s) {
                    if item.decision == .confirmed {
                        Button { set(s, .pending) } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                            .buttonStyle(.app(.neutral, size: .compact))
                    } else {
                        Button { set(s, .confirmed) } label: { Label("Confirm", systemImage: "checkmark") }
                            .buttonStyle(.app(.primary, size: .compact))
                            .accessibilityLabel("Confirm \(item.name)")
                    }
                    Button { set(s, .removed) } label: { Label("Remove", systemImage: "xmark") }
                        .buttonStyle(.app(.neutral, size: .compact))
                        .accessibilityLabel("Remove \(item.name)")
                    Spacer(minLength: 0)
                }
            }
            .card(padding: Space.l, radius: Radius.tile)
            .overlay {
                if item.id == selected {
                    RoundedRectangle(cornerRadius: Radius.tile, style: .continuous).strokeBorder(Color.accent, lineWidth: Stroke.bold)
                }
            }
        }
    }

    private func set(_ s: Binding<DetectionSuggestion>, _ decision: DetectionSuggestion.Decision) {
        withMotion(reduceMotion: reduceMotion) { s.wrappedValue.decision = decision }
        if decision == .removed, selected == s.wrappedValue.id { selected = nil }
    }

    private var footer: some View {
        VStack(spacing: Space.s) {
            Button(confirmed.isEmpty ? "Confirm things to add them" : "Add \(confirmed.count) \(confirmed.count == 1 ? "thing" : "things")") {
                var chosen = confirmed
                for i in chosen.indices { chosen[i].name = chosen[i].name.trimmingCharacters(in: .whitespaces) }
                onConfirm(chosen.filter { !$0.name.isEmpty })
                dismiss()
            }
            .buttonStyle(.app(.primary))
            .disabled(confirmed.isEmpty)
            if pending > 0 && !confirmed.isEmpty {
                Text("\(pending) not checked yet won’t be added.").textRole(.hint)
            }
        }
        .padding(.horizontal, Space.page).padding(.vertical, Space.m)
        .background(.bar)
    }

    private func detect() async {
        do {
            let found = try await PhotoDetector.detect(in: image)
            let merged = DetectionMerge.suggestions(from: found, existing: existing)
            detectLog.notice("[Detect] merge: \(merged.suggestions.count) suggested, \(merged.skipped) already in the list, \(merged.suggestions.filter { $0.match != nil }.count) linked to scanned items")
            suggestions = merged.suggestions
            skipped = merged.skipped
            phase = .done
            UIAccessibility.post(notification: .announcement, argument: summary)
        } catch let error as PhotoDetectionError {
            detectLog.error("[Detect] failed: \(error.recoverySuggestion ?? "", privacy: .public)")
            phase = .failed(error)
        } catch {
            phase = .failed(.failed(error))
        }
    }
}
