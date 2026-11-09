import SwiftUI

/// Enter a five-letter code (or arrive from an invite link), confirm your name, join as the guest.
struct JoinRoomSheet: View {
    var onJoined: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(SyncEngine.self) private var sync
    @State private var code: String
    @State private var peek: RoomPeek?
    @State private var name = Identity.name
    @State private var error: String?
    @State private var busy = false
    @FocusState private var codeFocused: Bool

    init(initialCode: String, onJoined: @escaping (UUID) -> Void) {
        _code = State(initialValue: RoomCode.normalize(initialCode))
        self.onJoined = onJoined
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    if !sync.isShared {
                        ContentUnavailableView("Joining needs sharing turned on",
                                               systemImage: "icloud.slash",
                                               description: Text("This build has no Supabase keys yet. Add them to Supabase.plist."))
                    } else if let peek {
                        found(peek)
                    } else {
                        enterCode
                    }
                }
                .padding(Space.xl)
            }
            .background(Color.pageBackground)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .task {
                if code.count == 5 { await find() } else { codeFocused = true }
            }
        }
    }

    private var enterCode: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text("Join a room").font(.screenTitle)
            Text("Five letters and numbers, from the person who shared the room.").foregroundStyle(Color.textSecondary)
            TextField("K7M2Q", text: $code)
                .font(.code)
                .kerning(Tracking.code)
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($codeFocused)
                .padding(.vertical, Space.m)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.control))
                .overlay(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(Color.outline, lineWidth: Stroke.regular))
                .onChange(of: code) { _, new in
                    let normal = RoomCode.normalize(new)
                    if normal != new { code = normal }
                    error = nil
                }
                .onSubmit { Task { await find() } }
            if let error { Text(error).foregroundStyle(Color.letGo).fontWeight(.semibold) }
            Button { Task { await find() } } label: {
                if busy { ProgressView() } else { Text("Find room") }
            }
            .buttonStyle(.app)
            .disabled(code.count < 5 || busy)
        }
    }

    private func found(_ peek: RoomPeek) -> some View {
        VStack(alignment: .leading, spacing: Space.l) {
            if peek.isHost {
                Text("This is your room").font(.screenTitle)
                Text("You created \(peek.name). Open it from your rooms.").foregroundStyle(Color.textSecondary)
                Button("Open \(peek.name)") { dismiss(); onJoined(peek.id) }.buttonStyle(.app)
            } else {
                Text("Join room").font(.screenTitle)
                HStack(spacing: Space.m) {
                    Avatar(name: peek.hostName, role: .host)
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        Text(peek.name).font(.bodyStrong)
                        Text("Shared by \(peek.hostName)").textRole(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                VStack(alignment: .leading, spacing: Space.s) {
                    Text("Your first name").font(.detailStrong)
                    TextField("Your name", text: $name)
                        .textContentType(.givenName)
                        .textFieldStyle(.app)
                }
                if let error { Text(error).foregroundStyle(Color.letGo).fontWeight(.semibold) }
                Button { Task { await join(peek) } } label: {
                    if busy { ProgressView() } else { Text("Join the room") }
                }
                .buttonStyle(.app)
                .disabled(name.trimmed.isEmpty || busy)
                Button("Use a different code") { self.peek = nil; code = "" }
                    .buttonStyle(.link)
            }
        }
    }

    private func find() async {
        guard code.count == 5 else {
            error = "Room codes have five letters and numbers."
            return
        }
        busy = true
        defer { busy = false }
        do {
            let result = try await sync.peekRoom(code: code)
            if name.trimmed.isEmpty, let guest = result.guestName { name = guest }
            peek = result
        } catch {
            self.error = SyncError.describe(error)
        }
    }

    private func join(_ peek: RoomPeek) async {
        busy = true
        defer { busy = false }
        do {
            let id = try await sync.joinRoom(code: code, name: name.trimmed)
            dismiss()
            onJoined(id)
        } catch {
            self.error = SyncError.describe(error)
        }
    }
}
