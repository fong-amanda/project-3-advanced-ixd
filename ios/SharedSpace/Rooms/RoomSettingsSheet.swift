import SwiftUI

/// Room details: name, current and planned use, units, size, and whether the size is measured.
struct RoomSettingsSheet: View {
    let room: Room
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncEngine.self) private var sync

    @State private var name = ""
    @State private var currentUse = ""
    @State private var futureUse = ""
    @State private var units: UnitSystem = .feet
    @State private var width = 340.0
    @State private var length = 380.0
    @State private var height = 250.0
    @State private var measured = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    field("Name", text: $name, placeholder: "Room name")
                    field("Current use", text: $currentUse, placeholder: "Bedroom")
                    field("Planned use", text: $futureUse, placeholder: "Study")
                    VStack(alignment: .leading, spacing: Space.s) {
                        SectionLabel("Units")
                        ChipPicker(options: UnitSystem.allCases.map { .init(value: $0, title: $0.label) },
                                         selection: $units)
                    }
                    VStack(alignment: .leading, spacing: Space.s) {
                        SectionLabel("Size")
                        LengthStepper(label: "Width", value: $width, range: 150...800, units: units)
                        LengthStepper(label: "Length", value: $length, range: 150...800, units: units)
                        LengthStepper(label: "Ceiling", value: $height, range: 200...400, units: units)
                    }
                    ToggleRow(title: "These are measured, not estimates",
                              subtitle: "Turns on fit checks in the room plan", isOn: $measured)
                    Button("Save", action: save)
                        .buttonStyle(.app)
                        .disabled(name.trimmed.isEmpty)
                }
                .padding(Space.page)
            }
            .appSheet()
            .appNavigation("Room details")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onAppear {
                name = room.name
                currentUse = room.currentUse
                futureUse = room.futureUse
                units = room.unitSystem
                width = Double(room.widthCm)
                length = Double(room.lengthCm)
                height = Double(room.heightCm)
                measured = room.measured
            }
        }
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionLabel(label)
            TextField(placeholder, text: text).textFieldStyle(.app).accessibilityLabel(label)
        }
    }

    private func save() {
        room.name = name.trimmed
        room.currentUse = currentUse.trimmed
        room.futureUse = futureUse.trimmed
        room.unitSystem = units
        if Int(width.rounded()) != room.widthCm || Int(length.rounded()) != room.lengthCm {
            room.resize(width: width.rounded(), length: length.rounded())
        }
        room.heightCm = Int(height.rounded())
        room.measured = measured
        sync.save(room)
        dismiss()
    }
}
