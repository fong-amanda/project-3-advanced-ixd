import SwiftUI

/// "Which room are we changing?" Size and contents come later from the scan (or by hand).
struct NewRoomSheet: View {
    var onCreate: (Room) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(SyncEngine.self) private var sync
    @State private var myName = Identity.name
    @State private var currentUse = ""
    @State private var futureUse = ""
    @State private var roomName = ""
    private let askName = Identity.name.isEmpty

    static let currentOptions = ["Home office", "Spare bedroom", "Kid’s old room", "Storage room", "Hobby room"]
    static let futureOptions = ["Guest room", "Nursery", "Home office", "Hobby room", "Home gym", "Reading room"]

    private var canCreate: Bool {
        !currentUse.trimmed.isEmpty && !futureUse.trimmed.isEmpty && !myName.trimmed.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Which room are we changing?").font(.display(24))
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 0, trailing: 4))
                }
                if askName {
                    Section {
                        TextField("For example, Maya", text: $myName)
                            .textContentType(.givenName)
                    } header: {
                        Text("Your first name")
                    } footer: {
                        Text("So the people you invite know who it’s from.")
                    }
                }
                Section("Right now it’s a") {
                    choices(Self.currentOptions, selection: $currentUse)
                    TextField("Or type your own", text: $currentUse)
                }
                Section("We want it to become a") {
                    choices(Self.futureOptions, selection: $futureUse)
                    TextField("Or type your own", text: $futureUse)
                }
                Section("Name the room") {
                    TextField(currentUse.isEmpty ? "Upstairs office" : currentUse, text: $roomName)
                }
            }
            .navigationTitle("New room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }.disabled(!canCreate)
                }
            }
        }
    }

    private func choices(_ options: [String], selection: Binding<String>) -> some View {
        FlowLayout {
            ForEach(options, id: \.self) { option in
                Chip(title: option, isOn: selection.wrappedValue == option) { selection.wrappedValue = option }
            }
        }
        .padding(.vertical, 4)
    }

    private func create() {
        if askName { Identity.name = myName }
        let name = roomName.trimmed.isEmpty ? currentUse.trimmed : roomName.trimmed
        let room = sync.createRoom(name: name, currentUse: currentUse.trimmed, futureUse: futureUse.trimmed,
                                   hostName: Identity.name)
        dismiss()
        onCreate(room)
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
