import AppKit
import PDFKit
import SwiftUI

enum PrintPDFError: LocalizedError {
    case noDocument, renderFailed, titlePageOverflow
    var errorDescription: String? {
        switch self {
        case .noDocument: return "Open a screenplay to preview its printed pages."
        case .renderFailed: return "Could not create the print preview."
        case .titlePageOverflow: return "The title-page text does not fit on one page. Shorten the title, credits, or contact details in Title Page, then preview again. Your screenplay has not been changed."
        }
    }
}

struct PrintPreviewSnapshot: Identifiable {
    let id = UUID()
    let data: Data
    let document: PDFDocument
    let pageLabels: [String]
    let hasTitlePage: Bool
    init(data: Data, pageLabels: [String] = [], hasTitlePage: Bool = true) throws {
        self.hasTitlePage = hasTitlePage
        guard let document = PDFDocument(data: data), document.pageCount > 0 else { throw PrintPDFError.renderFailed }
        self.data = data
        self.document = document
        self.pageLabels = pageLabels
    }
}

struct PrintPreviewSheet: View {
    let snapshot: PrintPreviewSnapshot
    let export: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0
    @State private var zoom: CGFloat? = nil

    private var pageDescription: String {
        if !snapshot.hasTitlePage { return "Script page \(page + 1)" }
        if page == 0 { return "Title page" }
        return "Script page " + (snapshot.pageLabels.indices.contains(page - 1) ? snapshot.pageLabels[page - 1] : String(page))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Print Preview").font(.headline)
                Spacer()
                Button("Export PDF", action: export)
                Button("Back to Writing") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding()
            Divider()
            HStack {
                Button { page -= 1 } label: { Image(systemName: "chevron.left") }
                    .disabled(page == 0).accessibilityLabel("Previous page")
                Text("Page \(page + 1) of \(snapshot.document.pageCount)").monospacedDigit()
                Button { page += 1 } label: { Image(systemName: "chevron.right") }
                    .disabled(page + 1 >= snapshot.document.pageCount).accessibilityLabel("Next page")
                Text(pageDescription).foregroundStyle(.secondary)
                Spacer()
                Button("Fit Page") { zoom = nil }
                Button("100%") { zoom = 1 }
            }.padding(10)
            PrintedPDFView(document: snapshot.document, page: $page, zoom: zoom)
        }
        .frame(minWidth: 620, idealWidth: 760, minHeight: 520, idealHeight: 680)
    }
}

private struct PrintedPDFView: NSViewRepresentable {
    let document: PDFDocument
    @Binding var page: Int
    let zoom: CGFloat?

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.displayMode = .singlePage
        view.displayBox = .mediaBox
        view.displaysPageBreaks = true
        view.backgroundColor = .windowBackgroundColor
        view.document = document
        view.autoScales = true
        context.coordinator.observer = NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: view, queue: .main) { [weak coordinator = context.coordinator] _ in
            MainActor.assumeIsolated {
                guard let coordinator, !coordinator.updating, let current = view.currentPage else { return }
                coordinator.parent.page = document.index(for: current)
            }
        }
        return view
    }
    func updateNSView(_ view: PDFView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updating = true
        defer { context.coordinator.updating = false }
        if let target = document.page(at: page), view.currentPage !== target { view.go(to: target) }
        if let zoom {
            view.autoScales = false
            if view.scaleFactor != zoom { view.scaleFactor = zoom }
        } else {
            view.autoScales = true
        }
    }
    final class Coordinator {
        var parent: PrintedPDFView
        var observer: NSObjectProtocol?
        var updating = false
        init(_ parent: PrintedPDFView) { self.parent = parent }
        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    }
}
