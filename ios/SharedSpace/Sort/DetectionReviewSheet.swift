import SwiftUI

/// "Find things in this photo": shows what on-device detection found as numbered pins on the photo,
/// with one suggestion card at a time underneath. Nothing is added until the person confirms each
/// one (they can rename or remove it too).
///
/// * The photo and the cards fit on one screen (no vertical scrolling) at normal text sizes; the
///   photo gives up height so the card always fits. At accessibility text sizes it all scrolls.
/// * Cards swipe sideways in pin order. The card on screen highlights its pin; tapping a pin
///   brings up its card. Confirm or Remove marks the pin done and moves to the next unchecked card.
struct DetectionReviewSheet: View {
    let image: UIImage
    /// What's already listed, so things already pinned aren't suggested and scanned things are linked.
    let existing: [ExistingThing]
    /// The confirmed suggestions (renamed as the person left them).
    var onConfirm: ([DetectionSuggestion]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var phase: Phase = .detecting
    @State private var suggestions: [DetectionSuggestion] = []
    @State private var skipped = 0
    @State private var merged = 0
    /// The card on screen. Its pin is highlighted on the photo.
    @State private var current: UUID?
    @FocusState private var editing: UUID?
    /// Moves VoiceOver to a card's heading when Previous, Next or a pin brings it up.
    @AccessibilityFocusState private var spoken: UUID?

    private enum Phase { case detecting, done, failed(PhotoDetectionError) }

    static let privacyNote = "Detection runs on your iPhone. Your photo isn’t uploaded for this."
    /// How far the neighbouring cards peek in at each edge (beyond the gap between cards).
    private static let peek: CGFloat = Space.page + Space.l
    /// Pause after Confirm or Remove before moving on, so the check on the pin is seen first.
    private static let advanceDelay: Duration = .milliseconds(350)

    private var confirmed: [DetectionSuggestion] { suggestions.filter { $0.decision == .confirmed } }
    private var pending: Int { suggestions.filter { $0.decision == .pending }.count }
    private var currentIndex: Int? { suggestions.firstIndex { $0.id == current } }

    var body: some View {
        NavigationStack {
            Group {
                if typeSize.isAccessibilitySize {
                    ScrollView { content(photoHeight: Size.cardImageMax) }
                } else {
                    content(photoHeight: nil)
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

    /// `photoHeight` nil: the photo takes whatever height the card leaves.
    private func content(photoHeight: CGFloat?) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("\(Image(systemName: "lock.iphone")) \(Self.privacyNote)")
                .textRole(.hint)
                .fixedSize(horizontal: false, vertical: true)

            switch phase {
            case .detecting:
                VStack(spacing: Space.m) {
                    ProgressView()
                    Text("Looking for things in your photo…").textRole(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .combine)

            case .failed(let error):
                NoteBar(text: "\(error.errorDescription ?? ""). \(error.recoverySuggestion ?? "")",
                        symbol: "exclamationmark.triangle", tone: .warning)
                Spacer(minLength: 0)

            case .done:
                photo
                    .frame(maxWidth: .infinity, maxHeight: photoHeight ?? .infinity)
                    .layoutPriority(-1)
                if suggestions.isEmpty {
                    Text("Nothing to suggest in this photo. You can still tap the photo to add things by hand.")
                        .textRole(.secondary)
                    Spacer(minLength: 0)
                } else {
                    carousel
                    pager
                }
                if let note = leftOutNote {
                    Text(note).textRole(.hint).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, Space.page)
        .padding(.top, Space.s)
        .padding(.bottom, Space.m)
    }

    // MARK: Photo

    private var photo: some View {
        PhotoWithPins(
            image: image,
            pins: suggestions.enumerated().map { i, s in
                PhotoPin(id: s.id, number: i + 1, label: displayName(s), point: s.pin,
                         isSelected: s.id == current, mark: mark(s), spokenLabel: spokenLabel(s, i),
                         growsWhenSelected: true)
            },
            onTapPin: { id in show(id) },
            onMovePin: { id, point in
                if let i = suggestions.firstIndex(where: { $0.id == id }) { suggestions[i].pin = point }
            })
            .clipShape(RoundedRectangle(cornerRadius: Radius.cardLarge, style: .continuous))
    }

    private func mark(_ s: DetectionSuggestion) -> PhotoPin.Mark? {
        switch s.decision {
        case .pending: nil
        case .confirmed: .confirmed
        case .removed: .removed
        }
    }

    // MARK: Cards

    private var carousel: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: Space.m) {
                ForEach(Array(suggestions.enumerated()), id: \.element.id) { i, _ in
                    card(i).containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $current)
        // Run to the screen edges so the neighbouring cards peek in from them.
        .safeAreaPadding(.horizontal, Self.peek)
        .padding(.horizontal, -Space.page)
        .onChange(of: current) { _, _ in editing = nil }
    }

    private func card(_ i: Int) -> some View {
        let item = suggestions[i]
        return VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.m) {
                NumberBadge(number: i + 1, isSelected: item.decision == .pending, size: Size.pin)
                    .overlay(alignment: .bottomTrailing) { decisionMark(item) }
                    .frame(minWidth: Size.tapTarget, minHeight: Size.tapTarget)
                    // The card's heading for VoiceOver: "Item 2 of 5, Bottle, suggested".
                    .accessibilityElement()
                    .accessibilityLabel(spokenLabel(item, i))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($spoken, equals: item.id)
                if typeSize.isAccessibilitySize {
                    // Large text: the arrows go under the name.
                    VStack(alignment: .trailing, spacing: Space.s) { nameField(i); stepButtons(i) }
                } else {
                    HStack(spacing: 0) { nameField(i); stepButtons(i).fixedSize() }
                }
            }
            tag(item)
            Text(note(item))
                .textRole(.hint)
                .lineLimit(2, reservesSpace: true)
            HStack(spacing: Space.s) {
                switch item.decision {
                case .pending:
                    Button { decide(i, .confirmed) } label: { Label("Confirm", systemImage: "checkmark") }
                        .buttonStyle(.app(.primary, size: .compact))
                        .disabled(!hasName(item))
                        .accessibilityLabel("Confirm \(displayName(item))")
                        .accessibilityHint(hasName(item) ? "" : "Type a name first")
                    Button { decide(i, .removed) } label: { Label("Remove", systemImage: "xmark") }
                        .buttonStyle(.app(.neutral, size: .compact))
                        .accessibilityLabel("Remove \(displayName(item))")
                case .confirmed, .removed:
                    Button { decide(i, .pending) } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                        .buttonStyle(.app(.neutral, size: .compact))
                        .accessibilityLabel("Undo \(item.decision == .confirmed ? "confirm" : "remove") for \(displayName(item))")
                }
                Spacer(minLength: 0)
            }
        }
        .card(padding: Space.l, radius: Radius.tile)
        .overlay {
            if item.id == current {
                RoundedRectangle(cornerRadius: Radius.tile, style: .continuous).strokeBorder(Color.accent, lineWidth: Stroke.bold)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func nameField(_ i: Int) -> some View {
        let item = suggestions[i]
        return TextField(item.source == .unnamed ? "Type a name" : "Name", text: $suggestions[i].name)
            .font(.bodyStrong)
            .foregroundStyle(Color.textPrimary)
            .textInputAutocapitalization(.sentences)
            .submitLabel(.done)
            .focused($editing, equals: item.id)
            .disabled(item.decision == .removed)
            .frame(minHeight: Size.tapTarget)
            .padding(.horizontal, Space.m)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                .strokeBorder(Color.outlineStrong, lineWidth: Stroke.regular))
            .accessibilityLabel("Name of item \(i + 1)")
    }

    @ViewBuilder private func tag(_ item: DetectionSuggestion) -> some View {
        switch item.decision {
        case .pending: AppTag(kind: .suggestion, text: DetectionCopy.suggestedTag, symbol: "questionmark.circle")
        case .confirmed: AppTag(kind: .tone(.sage), text: "Confirmed", symbol: "checkmark")
        case .removed: AppTag(kind: .neutral, text: "Removed", symbol: "xmark")
        }
    }

    /// Previous and Next, for people who can't swipe. 44 × 44 each.
    private func stepButtons(_ i: Int) -> some View {
        HStack(spacing: 0) {
            IconButton(symbol: "chevron.left", label: "Previous item") { step(from: i, by: -1) }
                .disabled(i == 0)
                .opacity(i == 0 ? Opacity.disabled : 1)
            IconButton(symbol: "chevron.right", label: "Next item") { step(from: i, by: 1) }
                .disabled(i == suggestions.count - 1)
                .opacity(i == suggestions.count - 1 ? Opacity.disabled : 1)
        }
    }

    @ViewBuilder private func decisionMark(_ item: DetectionSuggestion) -> some View {
        if item.decision != .pending {
            Image(systemName: item.decision == .confirmed ? "checkmark" : "xmark")
                .font(.caption2.weight(.bold))
                .dynamicTypeSize(...DynamicTypeSize.large)
                .foregroundStyle(Color.photoBadge)
                .frame(width: Size.badgeSmall - 2, height: Size.badgeSmall - 2)
                .background(item.decision == .confirmed ? Color.keep : Color.iconNeutral, in: Circle())
                .offset(x: Space.xs, y: Space.xs)
                .accessibilityHidden(true)
        }
    }

    /// One line under the tag, the same height on every card so they line up.
    private func note(_ item: DetectionSuggestion) -> String {
        switch item.decision {
        case .confirmed: return item.match == nil ? "Will be added when you tap Add." : "Will get its number here instead of being added twice."
        case .removed: return "Won’t be added."
        case .pending:
            if let match = item.match { return "Looks like “\(match.name)” from your scan. Confirming puts its number here." }
            if !hasName(item) { return "\(DetectionCopy.unnamedPrompt) Type a name, then confirm." }
            return "Check the name, then confirm or remove it."
        }
    }

    // MARK: "2 of 5" and dots

    private var pager: some View {
        let position = (currentIndex ?? 0) + 1
        return HStack(spacing: Space.m) {
            Text("\(position) of \(suggestions.count)").font(.detailStrong).foregroundStyle(Color.textPrimary)
            if suggestions.count <= 12 {
                HStack(spacing: Space.xs) {
                    ForEach(Array(suggestions.enumerated()), id: \.element.id) { i, s in
                        Circle()
                            .fill(i + 1 == position ? Color.accent : (s.decision == .pending ? Color.outlineStrong : Color.keep.opacity(0.5)))
                            .frame(width: 7, height: 7)
                    }
                }
            }
            Text(pending == 0 ? "All checked" : "\(pending) to check").textRole(.hint)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Item \(position) of \(suggestions.count). \(pending == 0 ? "All checked" : "\(pending) left to check").")
    }

    private var leftOutNote: String? {
        var parts: [String] = []
        if skipped > 0 { parts.append("\(skipped) already in your list") }
        if merged > 0 { parts.append("\(merged) duplicate \(merged == 1 ? "pin" : "pins") merged") }
        return parts.isEmpty ? nil : "Not shown: " + parts.joined(separator: ", ") + "."
    }

    // MARK: Words

    /// The name, or a stand-in until the person names something nothing recognised.
    private func displayName(_ s: DetectionSuggestion) -> String {
        let name = s.name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? DetectionCopy.unnamedPin : name
    }

    private func hasName(_ s: DetectionSuggestion) -> Bool {
        !s.name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// "Item 2 of 5, Bottle, suggested": the card's heading and its pin, for VoiceOver.
    private func spokenLabel(_ s: DetectionSuggestion, _ i: Int) -> String {
        let state = switch s.decision {
        case .pending: hasName(s) ? "suggested" : "not named yet"
        case .confirmed: "confirmed"
        case .removed: "removed"
        }
        return "Item \(i + 1) of \(suggestions.count), \(displayName(s)), \(state)"
    }

    // MARK: Moving between cards

    /// Brings up a card (and highlights its pin). Slides, or switches at once with Reduce Motion.
    private func show(_ id: UUID) {
        editing = nil
        withMotion(Motion.standard, reduceMotion: reduceMotion) { current = id }
        if voiceOver { spoken = id }
    }

    private func step(from i: Int, by delta: Int) {
        let j = i + delta
        guard suggestions.indices.contains(j) else { return }
        show(suggestions[j].id)
    }

    private func decide(_ i: Int, _ decision: DetectionSuggestion.Decision) {
        editing = nil
        withMotion(Motion.standard, reduceMotion: reduceMotion, fade: true) { suggestions[i].decision = decision }
        guard decision != .pending else { return }
        guard let next = nextUnchecked(after: i) else {
            UIAccessibility.post(notification: .announcement,
                                 argument: confirmed.isEmpty ? "All checked." : "All checked. Add \(confirmed.count) \(confirmed.count == 1 ? "thing" : "things") is ready.")
            return
        }
        let from = suggestions[i].id
        Task {
            try? await Task.sleep(for: Self.advanceDelay)
            // Only if the person hasn't moved on themselves meanwhile.
            if current == from { show(next) }
        }
    }

    /// The next suggestion still to check after `i`, wrapping round to the start.
    private func nextUnchecked(after i: Int) -> UUID? {
        let order = Array(suggestions.indices.dropFirst(i + 1)) + Array(suggestions.indices.prefix(i))
        return order.first { suggestions[$0].decision == .pending }.map { suggestions[$0].id }
    }

    // MARK: Footer

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

    // MARK: Detection

    private func detect() async {
        #if DEBUG
        if DemoData.openFindThings {
            suggestions = DemoData.sampleSuggestions()
            current = suggestions.first?.id
            phase = .done
            return
        }
        #endif
        do {
            let found = try await PhotoDetector.detect(in: image)
            let result = DetectionMerge.suggestions(from: found, existing: existing)
            detectLog.notice("[Detect] merge: \(result.suggestions.count) suggested, \(result.merged) duplicate pins merged, \(result.skipped) already in the list, \(result.suggestions.filter { $0.match != nil }.count) linked to scanned items")
            suggestions = result.suggestions
            skipped = result.skipped
            merged = result.merged
            current = suggestions.first?.id
            phase = .done
            let count = suggestions.count
            UIAccessibility.post(notification: .announcement, argument: count == 0
                ? "Nothing to suggest in this photo."
                : "Found \(count) \(count == 1 ? "thing" : "things"). Showing item 1 of \(count).")
        } catch let error as PhotoDetectionError {
            detectLog.error("[Detect] failed: \(error.recoverySuggestion ?? "", privacy: .public)")
            phase = .failed(error)
        } catch {
            phase = .failed(.failed(error))
        }
    }
}
