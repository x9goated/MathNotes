import SwiftUI

struct ContentView: View {
    @Environment(NoteStore.self) private var store
    @State private var selection: Note.ID?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(store.notes) { note in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(note.title)
                            .font(.headline)
                        Text(note.updatedAt, format: .dateTime.day().month().hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { offsets in
                    let deleted = offsets.map { store.notes[$0] }
                    for note in deleted {
                        store.delete(note)
                    }
                }
            }
            .navigationTitle("Notes")
            .toolbar {
                ToolbarItem {
                    Button {
                        selection = store.createNote().id
                    } label: {
                        Label("Nouvelle note", systemImage: "square.and.pencil")
                    }
                }
            }
        } detail: {
            if let id = selection, let note = store.note(id: id) {
                NoteEditor(note: note)
                    .id(id)
            } else {
                ContentUnavailableView(
                    "Aucune note ouverte",
                    systemImage: "pencil.and.scribble",
                    description: Text("Crée une note avec le bouton en haut de la liste.")
                )
            }
        }
    }
}

struct NoteEditor: View {
    @Environment(NoteStore.self) private var store
    let note: Note
    @State private var title: String

    init(note: Note) {
        self.note = note
        _title = State(initialValue: note.title)
    }

    var body: some View {
        CanvasView(drawingData: note.drawingData) { [store, id = note.id] data in
            store.updateDrawing(data, for: id)
        }
        .ignoresSafeArea(.container, edges: .bottom)
        // Tap the title in the navigation bar to rename the note.
        .navigationTitle($title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarRole(.editor)
        .onChange(of: title) {
            store.rename(note.id, to: title)
        }
    }
}
