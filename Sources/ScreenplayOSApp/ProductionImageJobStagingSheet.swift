import AppKit
import SwiftUI
import ScreenplayDomain

/// A durable, review-only production-image job in the existing project ledger.
/// There is deliberately no Send button. Staging is not consent.
struct ProductionImageJobStagingSheet: View {
    @ObservedObject var model: ScreenplayViewModel
    let boardID: UUID
    let dismiss: () -> Void

    @State private var modelID = "gpt-image-1.5"
    @State private var direction = "Preserve the approved storyboard composition and screen direction."
    @State private var style = ""
    @State private var preview: ProductionImageReferenceReview?
    @State private var stagedPreview: GenerationConsentPreview?
    @State private var stagedRequest: ApprovedProductionImageReview?
    @State private var stagedApproval: ProductionBoardApproval?
    @State private var authorization: ProductionImageSendAuthorization?
    @State private var showingConsentReview = false
    @State private var showingPendingJobs = false
    @State private var busy = false
    @State private var message = ""

    private var board: BoardFrame? { model.boardFrames.first(where: { $0.id == boardID }) }
    private var shot: Shot? { board.flatMap { b in model.shots.first(where: { $0.id == b.shotID }) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Production Image — Request Review").font(.headline)
                    Spacer()
                    Button("Close", action: dismiss)
                }
                Text("Offline staging only. No image will be uploaded and no API charges can occur here.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Provider: OpenAI")
                TextField("Image edit model", text: $modelID)
                    .disabled(busy || stagedPreview != nil)
                Text("Direction").font(.subheadline.weight(.semibold))
                TextEditor(text: $direction).frame(height: 110)
                    .disabled(busy || stagedPreview != nil)
                TextField("Visual style", text: $style)
                    .disabled(busy || stagedPreview != nil)
                Button("Manage saved unsent requests…") { showingPendingJobs = true }
                Button("Stage exact request for review (no send)") {
                    Task { await stage() }
                }
                .disabled(busy || stagedPreview != nil || model.saveURL == nil)
                if busy { ProgressView().controlSize(.small) }
                if let preview, let image = NSImage(data: preview.imageBytes) {
                    Divider()
                    Text("Frozen approved storyboard reference").font(.headline)
                    Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 220)
                    Text("Provider: \(preview.providerID) · Model: \(preview.modelID)")
                    Text("Reference SHA-256: \(preview.imageSHA256)")
                        .font(.caption.monospaced()).textSelection(.enabled)
                    Text("Exact request").font(.headline)
                    Text(preview.prompt).font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                    Text(preview.costDisclosure).foregroundStyle(.orange).font(.caption)
                }
                if let stagedPreview {
                    Label(authorization == nil
                          ? "Request saved locally — awaiting consent; not sent"
                          : "Request authorized locally — queued; not sent",
                          systemImage: "doc.badge.clock")
                        .font(.callout)
                    Text("Job: \(stagedPreview.jobID.uuidString)").font(.caption.monospaced())
                        .textSelection(.enabled)
                    if authorization == nil {
                        Button("Review separate consent…") { showingConsentReview = true }
                            .disabled(busy || stagedRequest == nil || stagedApproval == nil || preview == nil)
                    }
                    Button("Cancel staged request") { Task { await cancel() } }
                        .disabled(busy)
                }
                if !message.isEmpty {
                    Text(message).foregroundStyle(.orange).font(.caption)
                }
            }
            .padding(20)
        }
        .frame(minWidth: 640, idealWidth: 760, minHeight: 560)
        .sheet(isPresented: $showingPendingJobs) {
            ProductionImagePendingJobsSheet(model: model) {
                showingPendingJobs = false
            }
        }
        .sheet(isPresented: $showingConsentReview) {
            if let stagedPreview, let preview {
                ProductionImageConsentDecisionSheet(
                    consent: stagedPreview, imageReview: preview,
                    approveForQueue: {
                        showingConsentReview = false
                        Task { await authorizeLocally() }
                    },
                    dismiss: { showingConsentReview = false }
                )
            }
        }
    }

    private func stage() async {
        guard !busy, stagedPreview == nil else { return }
        busy = true
        defer { busy = false }
        guard let board, let shot, let projectID = model.document?.screenplay.id,
              let documentURL = model.saveURL, let selected = board.selectedImage else {
            message = "Save the screenplay and select a valid board image first."
            return
        }
        do {
            let approvalRoot = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true)
            let approvalURL = approvalRoot.appendingPathComponent(
                "ScreenplayOS/Approvals/\(projectID.uuidString)/\(board.id.uuidString).json")
            let approval = try ProductionBoardApprovals.load(at: approvalURL)
            try ProductionBoardApprovals.validate(
                approval, projectID: projectID, shot: shot, board: board)
            let projectRoot = documentURL.deletingLastPathComponent().resolvingSymlinksInPath()
            let selectedFile = selected.fileURL.standardizedFileURL
            let folder = projectRoot.appendingPathComponent(BoardImageStorage.folder)
            guard selectedFile.isFileURL,
                  selectedFile.deletingLastPathComponent() == folder,
                  selectedFile.pathExtension.lowercased() == "png",
                  OpenAIReferenceImageRequest.supportedModels.contains(modelID) else {
                message = "Use a supported edit model and a local project Board Images PNG."
                return
            }
            let staged = try ApprovedProductionImageFlow.prepare(
                approval: approval, projectID: projectID, shot: shot, board: board,
                instruction: direction, style: style,
                boardRelativePath: BoardImageStorage.folder + "/" + selectedFile.lastPathComponent,
                projectRoot: projectRoot, providerID: "openai", modelID: modelID,
                providerAcceptsReferenceImages: true,
                jobID: UUID(), at: Date())
            // Check again before persisting: window and app state can change.
            guard model.document?.screenplay.id == projectID,
                  let currentBoard = model.boardFrames.first(where: { $0.id == board.id }),
                  let currentShot = model.shots.first(where: { $0.id == shot.id }) else {
                message = "The project changed; reopen the review."
                return
            }
            try ProductionBoardApprovals.validate(
                approval, projectID: projectID, shot: currentShot, board: currentBoard)
            let controller = try model.generationJobController(for: projectID)
            let coordinator = ProductionImageConsentCoordinator(controller: controller)
            let consent = try await coordinator.stage(staged)
            preview = staged.reference
            stagedPreview = consent
            stagedRequest = staged
            stagedApproval = approval
            authorization = nil
            message = "The request is only saved for future review. Sending is disabled."
        } catch {
            message = "Could not stage the current approved image. Check the board, approval and local image."
        }
    }

    /// Explicit user action from the separate consent sheet. This persists
    /// queued state but never creates an authenticated transport or sends media.
    private func authorizeLocally() async {
        guard !busy, authorization == nil,
              let projectID = model.document?.screenplay.id,
              let stagedPreview, let stagedRequest, let stagedApproval,
              let board = model.boardFrames.first(where: { $0.id == boardID }),
              let shot = model.shots.first(where: { $0.id == board.shotID }),
              let documentURL = model.saveURL else {
            message = "The project or staged request has changed. Review again."
            return
        }
        busy = true
        defer { busy = false }
        do {
            let approvalRoot = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true)
            let approvalURL = approvalRoot.appendingPathComponent(
                "ScreenplayOS/Approvals/\(projectID.uuidString)/\(boardID.uuidString).json")
            let storedApproval = try ProductionBoardApprovals.load(at: approvalURL)
            guard storedApproval == stagedApproval,
                  projectID == stagedRequest.job.projectID else {
                message = "Storyboard approval changed. Re-stage this request."
                return
            }
            let projectRoot = documentURL.deletingLastPathComponent().resolvingSymlinksInPath()
            let controller = try model.generationJobController(for: projectID)
            let coordinator = ProductionImageConsentCoordinator(controller: controller)
            let proof = try await coordinator.authorize(
                staged: stagedRequest, displayedPreview: stagedPreview,
                explicitSendApproval: true, approval: storedApproval,
                shot: shot, board: board, projectRoot: projectRoot,
                providerAcceptsReferenceImages: true, at: Date())
            authorization = proof
            message = "Consent saved locally. Request is queued but cannot send from this screen. Cancel if you do not want to retain it."
        } catch {
            message = "Consent was not recorded. The board, image or stored job may have changed."
        }
    }

    private func cancel() async {
        guard let stagedPreview, let projectID = model.document?.screenplay.id else { return }
        busy = true
        defer { busy = false }
        do {
            let controller = try model.generationJobController(for: projectID)
            try await controller.cancel(jobID: stagedPreview.jobID, at: Date())
            self.stagedPreview = nil
            stagedRequest = nil
            stagedApproval = nil
            authorization = nil
            preview = nil
            message = "Staged request cancelled; nothing was sent."
        } catch {
            message = "Unable to cancel the staged request. Review its status in generation activity."
        }
    }
}
