import SwiftUI

@main
struct MathNotesApp: App {
    @State private var store = NoteStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
    }
}
