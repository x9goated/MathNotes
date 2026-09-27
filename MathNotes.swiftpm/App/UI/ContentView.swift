import SwiftUI

struct ContentView: View {
    @Environment(NoteStore.self) private var store
    @State private var selection: Note.ID?
    @State private var query = ""
    @State private var showsSettings = false

    private var visibleNotes: [Note] {
        query.isEmpty ? store.notes : store.notes.filter { $0.matches(query) }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(visibleNotes) { note in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(note.title)
                            .font(.headline)
                        Text(note.updatedAt, format: .dateTime.day().month().hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { offsets in
                    let deleted = offsets.map { visibleNotes[$0] }
                    for note in deleted {
                        store.delete(note)
                    }
                }
            }
            .navigationTitle("Notes")
            .searchable(text: $query, prompt: "Titres et formules")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showsSettings = true
                    } label: {
                        Label("Réglages", systemImage: "gearshape")
                    }
                }
                ToolbarItem {
                    Button {
                        query = ""
                        selection = store.createNote().id
                    } label: {
                        Label("Nouvelle note", systemImage: "square.and.pencil")
                    }
                }
            }
        } detail: {
            if let id = selection, let note = store.note(id: id) {
                NoteEditor(note: note, store: store)
                    .id(id)
            } else {
                ContentUnavailableView(
                    "Aucune note ouverte",
                    systemImage: "pencil.and.scribble",
                    description: Text("Crée une note avec le bouton en haut de la liste.")
                )
            }
        }
        .sheet(isPresented: $showsSettings) {
            SettingsView()
        }
    }
}
