import SwiftUI

/// Rename the room, change what it is / will be, and set its size by hand (non-LiDAR phones).
struct RoomSettingsSheet: View {
    let room: Room
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncEngine.self) private var sync

    @State private var name = ""
    @State private var currentUse = ""
    @State private var futureUse = ""
    @State private var width = 340
    @State private var length = 380
    @State private var height = 250

    private struct Preset: Identifiable {
        let name: String, width: Int, length: Int
        var id: String { name }
    }

    private static let presets = [
        Preset(name: "Box room", width: 240, length: 280),
        Preset(name: "Small bedroom", width: 300, length: 340),
        Preset(name: "Double bedroom", width: 340, length: 380),
        Preset(name: "Large room", width: 420, length: 460),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") { TextField("Room name", text: $name) }
                Section("Right now it’s a") { TextField("Home office", text: $currentUse) }
                Section("We want it to become a") { TextField("Guest room", text: $futureUse) }
                Section {
                    FlowLayout {
                        ForEach(Self.presets) { preset in
                            Chip(title: preset.name, isOn: width == preset.width && length == preset.length) {
                                width = preset.width
                                length = preset.length
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    Stepper("Width \(metres(width))", value: $width, in: 150...800, step: 10)
                    Stepper("Length \(metres(length))", value: $length, in: 150...800, step: 10)
                    Stepper("Ceiling \(metres(height))", value: $height, in: 200...400, step: 10)
                } header: {
                    Text("Size")
                } footer: {
                    Text(room.isScanned
                         ? "Set by your scan. Scanning again will replace these numbers."
                         : "Rough is fine. Redesign and the furniture search use these numbers.")
                }
            }
            .navigationTitle("Room details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(name.trimmed.isEmpty)
                }
            }
            .onAppear {
                name = room.name
                currentUse = room.currentUse
                futureUse = room.futureUse
                width = room.widthCm
                length = room.lengthCm
                height = room.heightCm
            }
        }
    }

    private func metres(_ cm: Int) -> String {
        (Double(cm) / 100).formatted(.number.precision(.fractionLength(0...2))) + " m"
    }

    private func save() {
        room.name = name.trimmed
        room.currentUse = currentUse.trimmed
        room.futureUse = futureUse.trimmed
        room.widthCm = width
        room.lengthCm = length
        room.heightCm = height
        sync.save(room)
        dismiss()
    }
}
