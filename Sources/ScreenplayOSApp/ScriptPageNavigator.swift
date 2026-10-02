import SwiftUI

/// Navigation uses the existing print-to-source mapping, including locked page labels.
/// This is presentation state only; browsing pages never edits the document.
@MainActor
final class ScriptViewportState: ObservableObject {
    @Published var pageLabel: String?
}

struct ScriptPageNavigator: View {
    @ObservedObject var model: ScreenplayViewModel
    var didNavigate: () -> Void = {}
    @ObservedObject private var viewport: ScriptViewportState

    init(model: ScreenplayViewModel, didNavigate: @escaping () -> Void = {}) {
        self.model = model
        self.viewport = model.scriptViewport
        self.didNavigate = didNavigate
    }

    @State private var pageLabel = ""
    @State private var invalidPage = false

    var body: some View {
        let projection = model.printedLayout
        VStack(alignment: .leading, spacing: 8) {
            Text("Script Pages").font(.headline)
            if let label = viewport.pageLabel {
                Text("Viewing page \(label)").font(.caption).foregroundStyle(.secondary)
            }
            TextField("Page number", text: $pageLabel)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Go to script page number")
                .onSubmit {
                    let label = pageLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let index = projection.pages.firstIndex(where: { $0.label.caseInsensitiveCompare(label) == .orderedSame }),
                       projection.firstSourceCaret(onPage: index) != nil {
                        invalidPage = false
                        model.navigateToPrintedPage(index)
                        didNavigate()
                    } else {
                        invalidPage = true
                    }
                }
            if invalidPage {
                Text("Enter an available page label from the list.").font(.caption).foregroundStyle(.secondary)
            }
            ScrollViewReader { reader in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(projection.pages.indices, id: \.self) { index in
                            Button {
                                model.navigateToPrintedPage(index)
                                didNavigate()
                            } label: {
                                Label("Page \(projection.pages[index].label)", systemImage: "doc.text")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 5)
                                    .padding(.horizontal, 6)
                                    .background(viewport.pageLabel == projection.pages[index].label ? Color.accentColor.opacity(0.2) : Color.clear)
                                    .contentShape(Rectangle())
                            }
                            .id(projection.pages[index].label)
                            .accessibilityValue(viewport.pageLabel == projection.pages[index].label ? "Current visible page" : "")
                            .buttonStyle(.plain)
                            .disabled(projection.firstSourceCaret(onPage: index) == nil)
                        }
                    }
                }
                .onChange(of: viewport.pageLabel) { label in
                    if let label { reader.scrollTo(label, anchor: .center) }
                }
            }
            Text("Title page excluded").font(.caption).foregroundStyle(.secondary)
        }
        .padding(10)
    }
}
