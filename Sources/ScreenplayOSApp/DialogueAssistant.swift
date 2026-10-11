import SwiftUI
import ScreenplayDomain

struct DialogueSnapshot {
    let screenplayID: UUID
    let elements: [ScreenplayElement]
    let targetID: UUID
    let context: String
    @MainActor static func capture(_ model: ScreenplayViewModel) -> DialogueSnapshot? {
        guard let document = model.document, let index = model.elements.firstIndex(where: { $0.id == model.selectedElementID }),
              model.elements[index].type == .dialogue else { return nil }
        let elements = model.elements
        let sceneStart = elements[...index].lastIndex(where: { $0.type == .sceneHeading }) ?? 0
        let sceneEnd = elements[(index + 1)...].firstIndex(where: { $0.type == .sceneHeading }) ?? elements.count
        let speaker = elements[sceneStart...index].last(where: { $0.type == .character })?.text ?? "Unknown speaker"
        let nearby = elements[max(sceneStart, index - 6)..<min(sceneEnd, index + 4)]
        let context = "Speaker: \(speaker.prefix(200))\nSelected dialogue: \(elements[index].text.prefix(2000))\nNearby scene excerpt (may be shortened):\n" + nearby.map { "\($0.type.rawValue): \($0.text.prefix(1000))" }.joined(separator: "\n")
        return .init(screenplayID: document.screenplay.id, elements: elements, targetID: elements[index].id, context: context)
    }
    @MainActor func isCurrent(_ model: ScreenplayViewModel) -> Bool {
        model.document?.screenplay.id == screenplayID && model.elements == elements && model.packageEditor == nil
    }
    @MainActor func accept(_ line: String, model: ScreenplayViewModel, insert: Bool) -> Bool {
        guard isCurrent(model), let index = model.elements.firstIndex(where: { $0.id == targetID }), !line.isEmpty, !line.contains(where: \.isNewline) else { return false }
        let range = model.writingRanges[index]
        if insert {
            model.insertSuggestedDialogue(line, after: targetID)
        } else {
            _ = model.replaceWritingText(in: NSRange(location: range.location, length: (model.elements[index].text as NSString).length), with: line)
        }
        return true
    }
}

@MainActor final class DialogueConnection: ObservableObject {
    @Published var provider: DialogueProvider
    @Published var modelID: String
    @Published var key = ""
    @Published var status = ""
    @Published var busy = false
    @Published var models: [String] = []
    @Published var alternatives: [String] = []
    private var task: Task<Void, Never>?
    private var generation = UUID()
    let keys = ProviderKeychain()
    let defaults: UserDefaults
    let adapter: (DialogueProvider) -> any TextAssist
    init(defaults: UserDefaults = .standard,
         adapter: @escaping (DialogueProvider) -> any TextAssist = { DialogueTextAdapter(provider: $0) }) {
        self.adapter = adapter
        self.defaults = defaults
        let selected = DialogueProvider(rawValue: defaults.string(forKey: "dialogue.provider") ?? "") ?? .openai
        provider = selected
        modelID = defaults.string(forKey: "dialogue.model.\(selected.rawValue)") ?? ""
    }
    func changeProvider() {
        cancel(); key = ""; alternatives = []; models = []; status = ""
        modelID = defaults.string(forKey: "dialogue.model.\(provider.rawValue)") ?? ""
    }
    func cancel() { generation = UUID(); task?.cancel(); task = nil; busy = false }
    func disconnect() {
        cancel()
        do { try keys.remove(provider); key = ""; alternatives = []; status = "Disconnected. The saved key was removed from this Mac." }
        catch { status = error.localizedDescription }
    }
    func loadModels() {
        cancel(); busy = true; status = ""
        let token = generation, provider = provider, entered = key.trimmingCharacters(in: .whitespacesAndNewlines)
        task = Task {
            do {
                guard let credential = entered.isEmpty ? try keys.read(provider) : entered, !credential.isEmpty else {
                    throw DialogueServiceError(message: "Paste an API key to load your available models.")
                }
                let found = try await adapter(provider).models(key: credential)
                guard generation == token, !Task.isCancelled else { return }
                models = found
                status = "Choose a text-generation model, then Test & Connect. Other model types may appear in your account list."
            } catch { if generation == token && !Task.isCancelled { status = "Could not load models. Check your key and connection, or enter a model ID manually." } }
            if generation == token { busy = false }
        }
    }
    func run(context: String?, direction: String = "") {
        cancel(); alternatives = []; status = ""; busy = true
        let token = generation, provider = provider, model = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let entered = key.trimmingCharacters(in: .whitespacesAndNewlines)
        task = Task {
            do {
                guard let credential = entered.isEmpty ? try keys.read(provider) : entered, !credential.isEmpty else {
                    throw DialogueServiceError(message: "Paste your provider API key first. Do not paste it into chat.")
                }
                let prompt = context.map { "Writer direction: \(direction.prefix(1000))\n\($0)" } ?? "Connection test: provide three brief greetings for an imaginary character. No screenplay is supplied."
                let result = try await adapter(provider).suggest(key: credential, model: model, prompt: prompt)
                guard !Task.isCancelled, generation == token else { return }
                if context == nil {
                    try keys.save(credential, provider: provider)
                    defaults.set(provider.rawValue, forKey: "dialogue.provider")
                    defaults.set(model, forKey: "dialogue.model.\(provider.rawValue)")
                    key = ""; status = "Connected and tested. Saved as your default provider."
                } else { alternatives = result; status = "Click a suggested line to insert it after the selected dialogue." }
            } catch { if generation == token && !Task.isCancelled { status = error.localizedDescription } }
            if generation == token { busy = false }
        }
    }
}

struct DialogueAssistantView: View {
    @ObservedObject var model: ScreenplayViewModel
    @StateObject private var connection = DialogueConnection()
    @Environment(\.dismiss) private var dismiss
    @State private var snapshot: DialogueSnapshot?
    @State private var direction = ""
    @State private var accepted = false
    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Dialogue assistant").font(.title2); Spacer(); Button("Done") { connection.cancel(); dismiss() } }
            HStack {
                Picker("Provider", selection: $connection.provider) {
                    ForEach(DialogueProvider.allCases) { Text($0.name).tag($0) }
                }.onChange(of: connection.provider) { _ in connection.changeProvider() }
                Link("Get API key", destination: connection.provider.keyURL)
            }.disabled(connection.busy)
            SecureField("API key — leave blank to use the saved connection", text: $connection.key).disabled(connection.busy)
            HStack {
                TextField("Model ID from your provider account", text: $connection.modelID)
                Menu("Choose model") {
                    ForEach(connection.models, id: \.self) { id in Button(id) { connection.modelID = id } }
                }.disabled(connection.models.isEmpty)
                Button("Load models") { connection.loadModels() }
            }.disabled(connection.busy)
            Text("API billing applies. Keys stay in this Mac’s Keychain. Test sends only an imaginary greeting request; it does not send your script.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Test & Connect") { connection.run(context: nil) }.disabled(connection.busy || connection.modelID.isEmpty)
                Button("Disconnect") { connection.disconnect() }
                if connection.busy { ProgressView().controlSize(.small); Button("Cancel") { connection.cancel() } }
            }
            Divider()
            if let snapshot {
                Text("Context to send to \(connection.provider.name)").font(.headline)
                ScrollView { Text(snapshot.context).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 145)
                TextField("Direction (optional): more restrained, evade the question…", text: $direction).disabled(connection.busy)
                Button("Send context & suggest three lines") { connection.run(context: snapshot.context, direction: direction) }
                    .buttonStyle(StudioButtonStyle(ai: true))
                    .disabled(connection.busy || accepted || !snapshot.isCurrent(model) || connection.modelID.isEmpty)
                if !snapshot.isCurrent(model) && !accepted { Text("The script changed. Close and reopen this panel to use the current text.").foregroundStyle(.orange) }
                ForEach(Array(connection.alternatives.enumerated()), id: \.offset) { _, line in
                    VStack(alignment: .leading) {
                        Button {
                            accepted = snapshot.accept(line, model: model, insert: true)
                            if accepted { dismiss() }
                        } label: {
                            HStack(alignment: .top) {
                                Text(line).multilineTextAlignment(.leading)
                                Spacer(minLength: 12)
                                Image(systemName: "text.badge.plus")
                            }.frame(maxWidth: .infinity, alignment: .leading)
                                .padding(6).contentShape(Rectangle())
                        }
                        .buttonStyle(StudioButtonStyle(ai: true))
                        .accessibilityLabel("Insert suggested dialogue: \(line)")
                        .help("Insert this line after the selected dialogue. Undo restores the previous script.")
                        Button("Replace selected dialogue") {
                            accepted = snapshot.accept(line, model: model, insert: false)
                            if accepted { dismiss() }
                        }
                    }.disabled(accepted || !snapshot.isCurrent(model))
                    .padding(8).aiSurface()
                }
            } else { Text("Select a dialogue paragraph, then reopen Suggest dialogue line to request alternatives.") }
            if !connection.status.isEmpty { Text(connection.status).font(.callout) }
        }.padding(20).aiSurface()
        }.frame(width: 620, height: 560)
        .onAppear { snapshot = DialogueSnapshot.capture(model) }
        .onDisappear { connection.cancel(); connection.key = "" }
    }
}
