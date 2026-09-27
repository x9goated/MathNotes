import Foundation
import Observation

/// Keeps the notes in memory and saves each one as a JSON file in the app's Documents folder.
@MainActor
@Observable
final class NoteStore {
    private(set) var notes: [Note] = []

    private let folder: URL = {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = documents.appendingPathComponent("Notes", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()

    init() {
        load()
    }

    func note(id: Note.ID) -> Note? {
        notes.first { $0.id == id }
    }

    @discardableResult
    func createNote() -> Note {
        let note = Note(title: "Note \(notes.count + 1)")
        notes.insert(note, at: 0)
        save(note)
        return note
    }

    func rename(_ id: Note.ID, to title: String) {
        update(id) { $0.title = title }
    }

    func updateDrawing(_ data: Data, for id: Note.ID) {
        update(id) { $0.drawingData = data }
    }

    func updateLines(_ lines: [MathLine], for id: Note.ID) {
        update(id) { $0.lines = lines }
    }

    func setPaper(_ paper: PaperStyle, for id: Note.ID) {
        update(id) { $0.paper = paper }
    }

    func delete(_ note: Note) {
        notes.removeAll { $0.id == note.id }
        try? FileManager.default.removeItem(at: fileURL(for: note.id))
    }

    func update(_ id: Note.ID, _ change: (inout Note) -> Void) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        var note = notes[index]
        change(&note)
        guard note != notes[index] else { return }
        note.updatedAt = Date()
        notes[index] = note
        save(note)
    }

    private func fileURL(for id: Note.ID) -> URL {
        folder.appendingPathComponent("\(id.uuidString).json")
    }

    private func save(_ note: Note) {
        do {
            let data = try JSONEncoder().encode(note)
            try data.write(to: fileURL(for: note.id), options: .atomic)
        } catch {
            print("Could not save note \(note.id): \(error)")
        }
    }

    private func load() {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        notes = files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(Note.self, from: Data(contentsOf: $0)) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
}
