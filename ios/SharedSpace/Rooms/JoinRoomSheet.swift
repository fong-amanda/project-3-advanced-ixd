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
                VStack(alignment: .leading, spacing: 20) {
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
                .padding(20)
            }
            .background(Color.ssBg)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .task {
                if code.count == 5 { await find() } else { codeFocused = true }
            }
        }
    }

    private var enterCode: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Join a room").font(.display(32))
            Text("Enter the five-letter code from your invite.").foregroundStyle(Color.ssInk2)
            TextField("K7M2Q", text: $code)
                .font(.system(size: 34, weight: .semibold, design: .serif))
                .kerning(6)
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($codeFocused)
                .padding(.vertical, 12)
                .background(Color.ssSurface, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.ssLine, lineWidth: 1.5))
                .onChange(of: code) { _, new in
                    let normal = RoomCode.normalize(new)
                    if normal != new { code = normal }
                    error = nil
                }
                .onSubmit { Task { await find() } }
            if let error { Text(error).foregroundStyle(Color.ssLetGo).fontWeight(.semibold) }
            Button { Task { await find() } } label: {
                if busy { ProgressView() } else { Text("Find room") }
            }
            .buttonStyle(.pill)
            .disabled(code.count < 5 || busy)
        }
    }

    private func found(_ peek: RoomPeek) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if peek.isHost {
                Text("This is your room").font(.display(32))
                Text("You created \(peek.name). Open it from your rooms.").foregroundStyle(Color.ssInk2)
                Button("Open \(peek.name)") { dismiss(); onJoined(peek.id) }.buttonStyle(.pill)
            } else {
                Text("\(peek.hostName) invited you").font(.display(32))
                Text("\(peek.hostName) is turning the \(peek.name.lowercased()) into a \(peek.futureUse.lowercased()) and wants your say on a few things.")
                    .foregroundStyle(Color.ssInk2)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your first name").font(.subheadline.weight(.semibold))
                    TextField("Your name", text: $name)
                        .textContentType(.givenName)
                        .padding(14)
                        .background(Color.ssSurface, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.ssLine, lineWidth: 1.5))
                }
                if let error { Text(error).foregroundStyle(Color.ssLetGo).fontWeight(.semibold) }
                Button { Task { await join(peek) } } label: {
                    if busy { ProgressView() } else { Text("Join the room") }
                }
                .buttonStyle(.pill)
                .disabled(name.trimmed.isEmpty || busy)
                Button("Use a different code") { self.peek = nil; code = "" }
                    .buttonStyle(.pill(.secondary))
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
