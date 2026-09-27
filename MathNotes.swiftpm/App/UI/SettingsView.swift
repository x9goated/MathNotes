import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey = Keychain.read(Keychain.apiKeyAccount) ?? ""
    @AppStorage("autoAnalyze") private var autoAnalyze = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("sk-ant-…", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Link("Créer une clé sur console.anthropic.com",
                         destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                } header: {
                    Text("Clé API Claude")
                } footer: {
                    Text("Sert à lire ton écriture. L'API est payante à l'usage (de l'ordre d'un centime par ligne). La clé reste sur cet iPad, dans le trousseau.")
                }

                Section {
                    Toggle("Analyser pendant que j'écris", isOn: $autoAnalyze)
                } footer: {
                    Text("Sinon, touche ✨ pour analyser la note. Seules les lignes nouvelles ou modifiées sont envoyées.")
                }
            }
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") {
                        Keychain.save(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), for: Keychain.apiKeyAccount)
                        dismiss()
                    }
                }
            }
        }
    }
}
