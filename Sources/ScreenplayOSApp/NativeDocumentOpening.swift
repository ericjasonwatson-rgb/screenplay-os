import AppKit
import Combine
import SwiftUI

/// The native lifecycle is an adapter to the existing, save-protected Open command.
/// Only the latest launch/reopen request may wait for a document window. Requests received
/// during a review, sheet or file picker are rejected, never replayed after dismissal.
@MainActor
final class NativeDocumentOpening: ObservableObject {
    @Published private(set) var notice: String?
    private(set) weak var model: ScreenplayViewModel?
    private(set) weak var window: NSWindow?
    private var pendingURL: URL?
    private let windows = NSHashTable<NSWindow>.weakObjects()
    private var hasHadWindow = false
    private var windowRequested = false
    var reopenWindow: (() -> Void)?
    private var opening = false
    private var documentChanges: AnyCancellable?
    private var boundModelID: ObjectIdentifier?

    func bind(_ newModel: ScreenplayViewModel?) {
        let newID = newModel.map(ObjectIdentifier.init)
        guard boundModelID != newID || model !== newModel else { return }
        if boundModelID != nil { cancelPendingRequest() }
        boundModelID = newID
        windowRequested = false
        documentChanges = nil
        model = newModel
        window = nil
        windows.removeAllObjects()
        // New/Open/Recover or an edit after launch is newer user intent, even if
        // the native window has not finished attaching yet.
        documentChanges = newModel?.$document.dropFirst().sink { [weak self] _ in
            self?.cancelPendingRequest()
        }
    }

    func attach(window newWindow: NSWindow, model newModel: ScreenplayViewModel) {
        bind(newModel)
        windows.add(newWindow)
        window = newWindow
        hasHadWindow = true
        windowRequested = false
        // Never publish an opened document during SwiftUI's view update. The
        // identities and pending slot are rechecked at the actual handoff.
        DispatchQueue.main.async { [weak self, weak newModel, weak newWindow] in
            guard let self, let newModel, let newWindow, self.model === newModel, self.window === newWindow,
                  let url = self.pendingURL else { return }
            self.pendingURL = nil
            self.open([url])
        }
    }

    func activate(window newWindow: NSWindow, model newModel: ScreenplayViewModel) {
        guard model === newModel, windows.contains(newWindow) else { return }
        attach(window: newWindow, model: newModel)
    }

    func detach(window oldWindow: NSWindow, model oldModel: ScreenplayViewModel) {
        guard model === oldModel else { return }
        windows.remove(oldWindow)
        guard window === oldWindow else { return }
        window = windows.allObjects.first(where: \.isKeyWindow)
            ?? windows.allObjects.first(where: \.isVisible)
        cancelPendingRequest()
    }

    func cancelPendingRequest() { pendingURL = nil }
    func dismissNotice() { notice = nil }

    @discardableResult
    func open(_ urls: [URL]) -> Bool {
        // Every later command supersedes an earlier launch request, including a
        // rejected batch or unsupported URL. There is no hidden command queue.
        cancelPendingRequest()
        guard urls.count == 1, let url = urls.first else {
            return reject("Open one ScreenplayOS document at a time. No files were opened; choose one file and try again.")
        }
        guard url.isFileURL, (url.host ?? "").isEmpty || url.host == "localhost",
              url.query == nil, url.fragment == nil,
              url.pathExtension.lowercased() == "json" else {
            return reject("Open a local ScreenplayOS JSON document. For FDX, PDF, DOCX, text or experimental packages, use File > Open to review the file.")
        }
        guard !opening, !isBusy else {
            return reject("Document not opened. Finish or close the current panel, review or file picker, then try opening the file again.")
        }
        guard let model, let window else {
            guard !hasHadWindow || reopenWindow != nil else {
                return reject("Document not opened. Reopen the ScreenplayOS document window, then try opening the file again.")
            }
            pendingURL = url
            if hasHadWindow, !windowRequested {
                windowRequested = true
                reopenWindow?()
            }
            return true
        }
        // A repeated Finder callback must not reload, autosave, reset selection,
        // clear Undo, or overwrite a newer on-disk version of the active file.
        if model.document != nil, let active = model.saveURL ?? model.sourceURL,
           sameFile(active, url) {
            notice = nil
            focus(window)
            return true
        }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let resolved = url.resolvingSymlinksInPath()
            guard try resolved.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                return reject("Document not opened. Choose an existing ScreenplayOS JSON file, not a folder or package.")
            }
        } catch {
            return reject("Document not opened. The file is missing, unreadable, or not a supported ScreenplayOS JSON document. Choose another file or use File > Open.")
        }
        opening = true
        defer { opening = false }
        model.legacyWindow = window
        guard model.loadScreenplayOSDocument(at: url) else {
            return reject("Document not opened. " + (model.errorMessage ?? "Save the current screenplay successfully, then try again."))
        }
        notice = nil
        focus(window)
        return true
    }

    private var isBusy: Bool {
        let application = NSApplication.shared
        if application.modalWindow != nil || application.windows.contains(where: { $0.attachedSheet != nil }) {
            return true
        }
        guard let model else { return false }
        return model.campaignPresented || model.packageSheetOpen || model.titlePagePresented
            || model.dialogueAssistantPresented || model.continuityBiblePresented
            || model.boardGenerationSnapshot != nil || model.generationConsentPreview != nil
            || model.generationCostLedger != nil || model.convertedCopyReceipt != nil
            || model.convertedCopyInProgress || model.portableExportInProgress
            || model.commandPaletteVisible || model.sourceNavigationProblem != nil
    }

    private func sameFile(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.resolvingSymlinksInPath() == rhs.standardizedFileURL.resolvingSymlinksInPath()
    }

    private func focus(_ window: NSWindow) {
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func reject(_ message: String) -> Bool {
        notice = message
        model?.errorMessage = message
        return false
    }
}

/// View attachment, not onAppear or a timer, establishes native-window readiness.
struct NativeDocumentWindow: NSViewRepresentable {
    static let sceneID = "screenplay-document"
    @Environment(\.openWindow) private var openWindow
    let model: ScreenplayViewModel
    let opening: NativeDocumentOpening

    func makeNSView(context: Context) -> Probe {
        let action = openWindow
        opening.reopenWindow = { action(id: Self.sceneID) }
        return Probe(model: model, opening: opening)
    }
    func updateNSView(_ view: Probe, context: Context) { view.update(model: model, opening: opening) }
    static func dismantleNSView(_ view: Probe, coordinator: ()) { view.disconnect() }

    final class Probe: NSView {
        private var model: ScreenplayViewModel
        private var opening: NativeDocumentOpening
        private weak var attachedWindow: NSWindow?

        init(model: ScreenplayViewModel, opening: NativeDocumentOpening) {
            self.model = model
            self.opening = opening
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        func update(model: ScreenplayViewModel, opening: NativeDocumentOpening) {
            guard self.model !== model || self.opening !== opening else { return }
            disconnect()
            self.model = model
            self.opening = opening
            connect()
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard attachedWindow !== window else { return }
            disconnect()
            connect()
        }
        private func connect() {
            guard let window else { return }
            attachedWindow = window
            opening.attach(window: window, model: model)
            NotificationCenter.default.addObserver(self, selector: #selector(becameKey),
                name: NSWindow.didBecomeKeyNotification, object: window)
            NotificationCenter.default.addObserver(self, selector: #selector(willClose),
                name: NSWindow.willCloseNotification, object: window)
        }
        func disconnect() {
            NotificationCenter.default.removeObserver(self)
            if let attachedWindow { opening.detach(window: attachedWindow, model: model) }
            attachedWindow = nil
        }
        @objc private func becameKey(_ notification: Notification) {
            if let attachedWindow { opening.activate(window: attachedWindow, model: model) }
        }
        @objc private func willClose(_ notification: Notification) { disconnect() }
    }
}

/// A nonmodal, dismissible result in every workspace. It never replaces a review
/// or steals the editor's first responder; the user explicitly retries the open.
struct NativeDocumentOpenNotice: View {
    @ObservedObject var opening: NativeDocumentOpening
    var body: some View {
        if let notice = opening.notice {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                Text(notice).font(.callout).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("native-document-open.notice")
                Spacer(minLength: 8)
                Button("Dismiss") { opening.dismissNotice() }
            }.padding(10).background(.regularMaterial)
        }
    }
}
