import SwiftUI

/// Side panel listing each handwritten line, its transcription and the verdict on the step.
struct LinesPanel: View {
    let analyzer: NoteAnalyzer
    @Binding var selectedLineID: MathLine.ID?
    @State private var editedLine: MathLine?

    var body: some View {
        ScrollViewReader { proxy in
            List(selection: $selectedLineID) {
                if analyzer.lines.isEmpty {
                    Text("Écris au Pencil : chaque ligne apparaîtra ici, transcrite et vérifiée.")
                        .foregroundStyle(.secondary)
                }
                ForEach(analyzer.lines) { line in
                    LineRow(line: line, verdict: analyzer.verdicts[line.id])
                        .id(line.id)
                        .contextMenu {
                            Button {
                                editedLine = line
                            } label: {
                                Label("Corriger la transcription", systemImage: "pencil")
                            }
                            Button {
                                analyzer.toggleNewBlock(line.id)
                            } label: {
                                if line.startsNewBlock {
                                    Label("Continuer le calcul précédent", systemImage: "arrow.uturn.up")
                                } else {
                                    Label("Nouveau calcul à partir d'ici", systemImage: "arrow.turn.down.right")
                                }
                            }
                        }
                }
            }
            .navigationTitle("Lignes")
            .onChange(of: selectedLineID) {
                if let selectedLineID {
                    withAnimation { proxy.scrollTo(selectedLineID, anchor: .center) }
                }
            }
        }
        .sheet(item: $editedLine) { line in
            LineEditor(line: line) { kind, latex, expression in
                analyzer.correct(line.id, kind: kind, latex: latex, expression: expression)
            }
        }
    }
}

private struct LineRow: View {
    let line: MathLine
    let verdict: StepVerdict?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if line.startsNewBlock {
                Label("Nouveau calcul", systemImage: "arrow.turn.down.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                verdictIcon
                if !line.recognized {
                    Text("Pas encore lue")
                        .foregroundStyle(.secondary)
                } else if line.kind == .text {
                    Text(line.latex)
                        .italic()
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        MathView(latex: line.latex, fontSize: 18)
                            .fixedSize()
                            .padding(.vertical, 4)
                    }
                }
            }
            if case .invalid(let message)? = verdict {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else if verdict == .unreadable {
                Text("Transcription non vérifiable : corrige-la avec un appui long.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var verdictIcon: some View {
        switch verdict {
        case .valid?:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .invalid?:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .unreadable?:
            Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
        default:
            Image(systemName: line.kind == .text ? "text.alignleft" : "function").foregroundStyle(.secondary)
        }
    }
}

/// Manual correction of a transcription.
private struct LineEditor: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (MathLine.Kind, String, String) -> Void
    @State private var kind: MathLine.Kind
    @State private var latex: String
    @State private var expression: String

    init(line: MathLine, onSave: @escaping (MathLine.Kind, String, String) -> Void) {
        self.onSave = onSave
        _kind = State(initialValue: line.kind)
        _latex = State(initialValue: line.latex)
        _expression = State(initialValue: line.expression)
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $kind) {
                    Text("Maths").tag(MathLine.Kind.math)
                    Text("Texte").tag(MathLine.Kind.text)
                }
                .pickerStyle(.segmented)

                Section("LaTeX") {
                    TextField("x^2 + 1", text: $latex, axis: .vertical)
                        .font(.body.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if kind == .math && !latex.isEmpty {
                        MathView(latex: latex)
                    }
                }

                if kind == .math {
                    Section {
                        TextField("x^2+1", text: $expression)
                            .font(.body.monospaced())
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } header: {
                        Text("Pour la vérification")
                    } footer: {
                        Text("Syntaxe de calculatrice : 2*x+3=7, sqrt(x), x^2, pi…")
                    }
                }
            }
            .navigationTitle("Corriger la ligne")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        onSave(kind, latex, kind == .math ? expression : "")
                        dismiss()
                    }
                }
            }
        }
    }
}
