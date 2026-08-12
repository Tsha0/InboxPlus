import SwiftUI
import PalloCore

struct LinkPersonSheet: View {
    let people: [PalloPerson]
    let onSelect: (String) -> Void
    let onCreate: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Link to person")
                .font(.title2.bold())
            List(people) { person in
                Button(person.displayName) {
                    onSelect(person.id)
                    dismiss()
                }
            }
            .frame(minHeight: 120)
            Divider()
            TextField("New person’s name", text: $newName)
            Button("Create and link") {
                onCreate(newName)
                dismiss()
            }
            .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(20)
        .frame(width: 360)
    }
}
