import PencilKit
import SwiftUI

struct NoteEditor: View {
    @Environment(NoteStore.self) private var store
    let note: Note
    @State private var title: String
    @State private var paper: PaperStyle
    @State private var analyzer: NoteAnalyzer
    @State private var showsLines = false
    @State private var selectedLineID: MathLine.ID?
    @State private var exported: ExportedFile?
    @State private var exportError = ""
    @State private var showsExportError = false

    init(note: Note, store: NoteStore) {
        self.note = note
        _title = State(initialValue: note.title)
        _paper = State(initialValue: note.paper)
        _analyzer = State(initialValue: NoteAnalyzer(noteID: note.id, store: store))
    }

    var body: some View {
        CanvasView(
            drawingData: note.drawingData,
            paper: note.paper,
            markers: markers,
            onDrawingChange: { [store, analyzer, id = note.id] drawing in
                store.updateDrawing(drawing.dataRepresentation(), for: id)
                analyzer.drawingDidChange(drawing)
            },
            onMarkerTap: { lineID in
                selectedLineID = lineID
                showsLines = true
            }
        )
        .ignoresSafeArea(.container, edges: .bottom)
        .overlay(alignment: .top) { statusBanner }
        // Tap the title in the navigation bar to rename the note.
        .navigationTitle($title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarRole(.editor)
        .toolbar { toolbar }
        .inspector(isPresented: $showsLines) {
            LinesPanel(analyzer: analyzer, selectedLineID: $selectedLineID)
                .inspectorColumnWidth(min: 280, ideal: 340, max: 480)
        }
        .sheet(item: $exported) { file in
            ShareSheet(url: file.url)
        }
        .alert("Export impossible", isPresented: $showsExportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError)
        }
        .onChange(of: title) { store.rename(note.id, to: title) }
        .onChange(of: paper) { store.setPaper(paper, for: note.id) }
        .onAppear { analyzer.refreshVerdicts() }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Picker("Papier", selection: $paper) {
                    ForEach(PaperStyle.allCases) { style in
                        Label(style.label, systemImage: style.symbolName).tag(style)
                    }
                }
            } label: {
                Label("Papier", systemImage: paper.symbolName)
            }

            Button {
                analyzer.analyzeNow()
            } label: {
                Label("Analyser", systemImage: "sparkles")
            }
            .disabled(analyzer.isAnalyzing)

            Menu {
                ForEach(ExportFormat.allCases) { format in
                    Button(format.label) { export(as: format) }
                }
            } label: {
                Label("Exporter", systemImage: "square.and.arrow.up")
            }

            Button {
                showsLines.toggle()
            } label: {
                Label("Lignes", systemImage: "list.bullet.rectangle")
            }
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        if let message = analyzer.errorMessage {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.callout)
                Button {
                    analyzer.errorMessage = nil
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .padding(.top, 8)
        } else if analyzer.isAnalyzing {
            HStack(spacing: 8) {
                ProgressView()
                Text("Lecture de ton écriture…")
                    .font(.callout)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .padding(.top, 8)
        }
    }

    private var markers: [LineMarker] {
        note.lines.compactMap { line -> LineMarker? in
            let state: LineMarker.State
            if !line.recognized {
                guard analyzer.isAnalyzing else { return nil }
                state = .pending
            } else {
                switch analyzer.verdicts[line.id] {
                case .valid?: state = .valid
                case .invalid?: state = .invalid
                case .unreadable?: state = .unreadable
                default: return nil
                }
            }
            return LineMarker(id: line.id, rect: line.rect, state: state)
        }
    }

    private func export(as format: ExportFormat) {
        guard let current = store.note(id: note.id) else { return }
        do {
            exported = ExportedFile(url: try NoteExporter.export(current, as: format))
        } catch {
            exportError = error.localizedDescription
            showsExportError = true
        }
    }
}
