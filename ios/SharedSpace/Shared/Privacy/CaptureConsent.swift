import SwiftUI

// "Before you scan": a short notice shown before the first scan or room photo in a room, so the
// host knows who will see what the camera captures. Shown once per room (remembered on this
// phone); "Who can see this?" on the Room plan tab opens it again at any time.

/// Which rooms this phone has already shown the notice for.
enum CaptureConsent {
    private static let key = "ss.captureConsent"

    static func hasAgreed(_ roomId: UUID) -> Bool {
        (UserDefaults.standard.stringArray(forKey: key) ?? []).contains(roomId.uuidString)
    }

    static func agree(_ roomId: UUID) {
        var ids = UserDefaults.standard.stringArray(forKey: key) ?? []
        guard !ids.contains(roomId.uuidString) else { return }
        ids.append(roomId.uuidString)
        UserDefaults.standard.set(ids, forKey: key)
    }

    /// Called when a room is deleted or left.
    static func forget(_ roomId: UUID) {
        let ids = (UserDefaults.standard.stringArray(forKey: key) ?? []).filter { $0 != roomId.uuidString }
        UserDefaults.standard.set(ids, forKey: key)
    }
}

/// Handed down the view tree. Buttons that open the camera, the photo library or the scanner call
/// `ask { … }`; the action runs straight away once the notice has been seen for this room.
struct CaptureConsentGate {
    var ask: (@escaping () -> Void) -> Void = { $0() }
    /// Opens the notice on its own ("Who can see this?").
    var show: () -> Void = {}

    func callAsFunction(_ action: @escaping () -> Void) { ask(action) }
}

private struct CaptureConsentKey: EnvironmentKey {
    static let defaultValue = CaptureConsentGate()
}

extension EnvironmentValues {
    var captureConsent: CaptureConsentGate {
        get { self[CaptureConsentKey.self] }
        set { self[CaptureConsentKey.self] = newValue }
    }
}

private struct CaptureConsentModifier: ViewModifier {
    var isAgreed: () -> Bool
    var onAgree: () -> Void
    var isHost: Bool

    @State private var presented = false
    @State private var pending: (() -> Void)?
    /// Runs once the notice has finished closing, so the camera or scanner can present.
    @State private var afterDismiss: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .environment(\.captureConsent, CaptureConsentGate(
                ask: { action in
                    if isAgreed() { action() } else { pending = action; presented = true }
                },
                show: { pending = nil; presented = true }))
            .sheet(isPresented: $presented, onDismiss: {
                let next = afterDismiss
                afterDismiss = nil
                pending = nil
                next?()
            }) {
                CaptureConsentSheet(isHost: isHost) {
                    onAgree()
                    afterDismiss = pending
                    presented = false
                } onNotNow: {
                    presented = false
                }
            }
    }
}

extension View {
    /// Shows "Before you scan" before the first scan or photo, then remembers the answer.
    func captureConsent(isAgreed: @escaping () -> Bool, isHost: Bool = true, onAgree: @escaping () -> Void) -> some View {
        modifier(CaptureConsentModifier(isAgreed: isAgreed, onAgree: onAgree, isHost: isHost))
    }

    /// The notice for one room.
    func captureConsent(for room: Room, isHost: Bool) -> some View {
        let id = room.id
        return captureConsent(isAgreed: { CaptureConsent.hasAgreed(id) }, isHost: isHost) { CaptureConsent.agree(id) }
    }
}

/// The notice itself: calm, short, two buttons.
struct CaptureConsentSheet: View {
    var isHost = true
    var onContinue: () -> Void
    var onNotNow: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    IconCircle(symbol: "person.2", tone: .sage)
                    Text("Before you scan").textRole(.screenTitle).accessibilityAddTraits(.isHeader)
                    Text("Anyone you invite to this room can see the scan, photo and items.")
                        .textRole(.body)
                    Text("Try to leave people, mail, screens and anything private out of view.")
                        .textRole(.body)
                    Text(isHost ? "You can delete the room and everything in it at any time from the room menu."
                                : "The person who made the room can delete it and everything in it at any time.")
                        .textRole(.body)
                    Button("Continue", action: onContinue)
                        .buttonStyle(.app(.primary))
                        .padding(.top, Space.s)
                    Button("Not now", action: onNotNow)
                        .buttonStyle(.app(.neutral, size: .compact))
                        .frame(maxWidth: .infinity)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(Space.page)
            }
            .appSheet()
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
    }
}

/// "Who can see this?": a small link that opens the notice again.
struct WhoCanSeeThisLink: View {
    @Environment(\.captureConsent) private var consent

    var body: some View {
        Button { consent.show() } label: {
            Label("Who can see this?", systemImage: "person.2")
        }
        .buttonStyle(.app(.neutral, size: .compact))
        .accessibilityHint("Explains who can see the scan, photos and items in this room")
    }
}

/// A button whose action waits for the notice (for screens that set up the notice themselves).
struct ConsentGatedButton<Label: View>: View {
    var action: () -> Void
    @ViewBuilder var label: Label
    @Environment(\.captureConsent) private var consent

    var body: some View {
        Button { consent(action) } label: { label }
    }
}
