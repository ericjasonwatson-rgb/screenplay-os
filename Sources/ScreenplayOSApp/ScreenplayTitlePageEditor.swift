import SwiftUI
import PDFKit

/// A separate document section. Title-page editing never appends screenplay paragraphs.
struct ScreenplayTitlePageEditor: View {
    @ObservedObject var model: ScreenplayViewModel
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Title Page").font(.headline)
                Text("Separate from script page 1").foregroundStyle(.secondary)
                Spacer()
                Button("Done") { model.titlePagePresented = false }.keyboardShortcut(.cancelAction)
            }.padding(16)
            Divider()
            HStack(alignment: .top, spacing: 20) {
                Form {
                    TextField("Title", text: model.titlePageBinding(.title), axis: .vertical)
                    TextField("Subtitle / additional credits", text: model.titlePageBinding(.subtitle), axis: .vertical).lineLimit(4...10)
                    TextField("Written by", text: model.titlePageBinding(.author))
                    TextField("Contact", text: model.titlePageBinding(.contact), axis: .vertical).lineLimit(2...4)
                    TextField("Draft date", text: model.titlePageBinding(.draftDate))
                    if model.hasImportedTitlePageTail {
                        Text("An older import left six title-template lines at the end of this script.")
                        Button("Move Imported Title Text") { model.moveImportedTitlePageTail() }
                        Text("Keeps a safety snapshot and supports Undo.").font(.caption)
                    }
                }.frame(width: 290)
                TitlePageExportPreview(model: model)
                    .frame(width: 460, height: 620)
            }.padding(20)
        }.frame(width: 810, height: 740)
        .background(ScreenplayOSTokens.Palette.workspaceBackground)
    }
}


/// Debounced title-only PDF rendering keeps the fields responsive and shares the
/// exact export layout. A failed render replaces the preview with its explanation.
private struct TitlePageExportPreview: View {
    @ObservedObject var model: ScreenplayViewModel
    @State private var document: PDFDocument?
    @State private var error: String?
    @State private var updating = true

    var body: some View {
        VStack(spacing: 8) {
            Text(updating ? "Updating export preview…" : "Export preview")
                .font(.caption).foregroundStyle(.secondary)
            if let error {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Title page needs adjustment", systemImage: "exclamationmark.triangle")
                    Text(error)
                }
                .padding().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .accessibilityElement(children: .combine)
            } else if let document {
                TitlePagePDFView(document: document)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: model.titlePage) { _ in
            // Clear only when the *source changes*, not on the first render.
            // A previous export page must not remain visible while an
            // overflowing or edited title page awaits its debounced render.
            document = nil
            error = nil
            updating = true
        }
        .task(id: model.titlePage) {
            updating = true
            do {
                try await Task.sleep(nanoseconds: 150_000_000)
                try Task.checkCancellation()
                let data = try model.makeTitlePagePDF()
                guard let rendered = PDFDocument(data: data) else { throw PrintPDFError.renderFailed }
                document = rendered
                error = nil
                updating = false
            } catch is CancellationError {
                // A newer field value or closing the editor cancels this render.
            } catch {
                document = nil
                self.error = error.localizedDescription
                updating = false
            }
        }
    }
}

private struct TitlePagePDFView: NSViewRepresentable {
    let document: PDFDocument
    func makeNSView(context: Context) -> TitlePagePDFCanvas {
        let view = TitlePagePDFCanvas()
        view.document = document
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.image)
        view.setAccessibilityLabel("Title page export preview")
        return view
    }
    func updateNSView(_ view: TitlePagePDFCanvas, context: Context) {
        if view.document !== document { view.document = document }
    }
}

/// Draw a single export page directly; no asynchronous PDFView tile lifecycle.
final class TitlePagePDFCanvas: NSView {
    var document: PDFDocument? { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        guard let page = document?.page(at: 0)?.pageRef,
              let context = NSGraphicsContext.current?.cgContext else { return }
        let box = page.getBoxRect(.mediaBox)
        guard box.width > 0, box.height > 0 else { return }
        let scale = min(bounds.width / box.width, bounds.height / box.height)
        let rect = CGRect(x: (bounds.width - box.width * scale) / 2,
                          y: (bounds.height - box.height * scale) / 2,
                          width: box.width * scale, height: box.height * scale)
        context.saveGState()
        context.setFillColor(NSColor.white.cgColor)
        context.fill(rect)
        context.translateBy(x: rect.minX, y: rect.minY)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -box.minX, y: -box.minY)
        context.drawPDFPage(page)
        context.restoreGState()
    }
}
