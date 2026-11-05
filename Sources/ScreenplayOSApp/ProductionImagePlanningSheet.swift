import AppKit
import SwiftUI
import ScreenplayDomain

/// Local-only storyboard approval and production-image planning. A saved approval
/// is valid only for the exact shot and board revision that was approved.
/// Provider consent and production-image generation remain separate steps.
struct ProductionImagePlanningSheet: View {
    @ObservedObject var model: ScreenplayViewModel
    let boardID: UUID
    let dismiss: () -> Void

    @State private var approval: ProductionBoardApproval?
    @State private var direction = "Preserve the approved storyboard composition and screen direction."
    @State private var style = ""
    @State private var brief: ProductionImageBrief?
    @State private var problem: String?
    @State private var referencePreview: LocalReferencePreview?

    private struct LocalReferencePreview: Identifiable {
        let id = UUID()
        let review: ProductionImageReferenceReview
    }

    private var board: BoardFrame? { model.boardFrames.first(where: { $0.id == boardID }) }
    private var shot: Shot? { board.flatMap { b in model.shots.first(where: { $0.id == b.shotID }) } }
    private var projectID: UUID? { model.document?.screenplay.id }
    private var approvalIsCurrent: Bool {
        guard let approval, let projectID, let shot, let board else { return false }
        return (try? ProductionBoardApprovals.validate(
            approval, projectID: projectID, shot: shot, board: board)) != nil
    }
    private func storageURL(_ projectID: UUID) throws -> URL {
        guard let root = TakeWorkflow.applicationSupportRoot else {
            throw ProductionBoardApprovalError.invalidFile
        }
        return root.appendingPathComponent(
            "ScreenplayOS/Approvals/\(projectID.uuidString)/\(boardID.uuidString).json")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Production Image — Storyboard Review").font(.headline)
                    Spacer()
                    Button("Close", action: dismiss)
                }
                Text("Approval is stored locally for the exact board revision. This window cannot upload images or make paid generation requests.")
                    .font(.caption).foregroundStyle(.secondary)
                if let shot, let board {
                    Text("Shot: \(shot.label)").font(.subheadline.weight(.medium))
                    Text("Board: \(board.label)")
                    if let selected = board.selectedImage {
                        Text("Selected board image: \(selected.id.uuidString)")
                            .font(.caption.monospaced()).textSelection(.enabled)
                    } else {
                        Label("Select a board image first.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    HStack {
                        Button(approvalIsCurrent ? "Approved for this revision" : "Approve selected board locally") {
                            approve()
                        }
                        .disabled(approvalIsCurrent || board.selectedImage == nil || projectID == nil || model.saveURL == nil)
                        if approvalIsCurrent {
                            Label("Local approval verified", systemImage: "checkmark.seal")
                                .foregroundStyle(.green)
                        } else if approval != nil {
                            Label("Board changed; reapproval required", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                    }
                    Text("Direction").font(.subheadline.weight(.medium))
                    TextEditor(text: $direction)
                        .frame(height: 100).border(.secondary.opacity(0.35))
                        .onChange(of: direction) { _ in brief = nil }
                    Text("Visual style").font(.subheadline.weight(.medium))
                    TextField("Style reference or art direction", text: $style)
                        .onChange(of: style) { _ in brief = nil }
                    Button("Prepare production-image brief") { prepare() }
                        .disabled(!approvalIsCurrent)
                    Button("Inspect exact storyboard image and request…") { prepareLocalPreview() }
                        .disabled(!approvalIsCurrent || brief == nil)
                } else {
                    Text("The storyboard or shot is no longer available.")
                        .foregroundStyle(.orange)
                }
                if let problem { Text(problem).foregroundStyle(.orange).font(.caption) }
                if let brief {
                    Divider()
                    Text("Prepared local brief").font(.headline)
                    Text(brief.promptPreview)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Prompt fingerprint: \(brief.promptSHA256)").font(.caption.monospaced())
                    Text("No provider has been selected, no media has been sent, and no production Take has been created.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .frame(minWidth: 620, idealWidth: 740, minHeight: 540)
        .onAppear(perform: restoreApproval)
        .sheet(item: $referencePreview) { preview in
            ProductionImageReviewSheet(review: preview.review) {
                referencePreview = nil
            }
        }
    }

    private func restoreApproval() {
        guard let projectID, let path = try? storageURL(projectID) else { return }
        approval = try? ProductionBoardApprovals.load(at: path)
        brief = nil
    }

    private func approve() {
        guard let projectID, let shot, let board, model.saveURL != nil else {
            problem = "Save the screenplay and select an existing board before approving."
            return
        }
        do {
            let next = try ProductionBoardApprovals.approve(projectID: projectID, shot: shot, board: board)
            try ProductionBoardApprovals.store(next, at: storageURL(projectID))
            approval = next
            brief = nil
            problem = nil
        } catch {
            approval = nil
            brief = nil
            problem = "The approval could not be stored locally. No approval was recorded."
        }
    }

    private func prepareLocalPreview() {
        guard let projectID, let shot, let board, let approval,
              let brief, let documentURL = model.saveURL,
              let selected = board.selectedImage else {
            problem = "Prepare and approve the current storyboard first."
            return
        }
        do {
            try ProductionBoardApprovals.validate(
                approval, projectID: projectID, shot: shot, board: board)
            try ProductionImagePlanning.validateCurrent(
                brief, shot: shot, board: board, approvedBoardIDs: [board.id])
            let projectRoot = documentURL.deletingLastPathComponent().standardizedFileURL
            let imageFolder = projectRoot.appendingPathComponent(BoardImageStorage.folder)
            guard selected.fileURL.isFileURL,
                  selected.fileURL.deletingLastPathComponent().standardizedFileURL == imageFolder,
                  selected.fileURL.pathExtension.lowercased() == "png" else {
                problem = "The selected image must be stored in this project's Board Images folder."
                return
            }
            let relativePath = BoardImageStorage.folder + "/" + selected.fileURL.lastPathComponent
            // Local-only rendering supports a PNG reference; the fake provider
            // metadata is never considered an external provider capability.
            // Sending remains unavailable until a real adapter is verified.
            let staged = try ApprovedProductionImageFlow.prepare(
                approval: approval, projectID: projectID, shot: shot, board: board,
                instruction: brief.directingInstruction, style: brief.styleInstruction,
                boardRelativePath: relativePath, projectRoot: projectRoot,
                providerID: "local-preview-only", modelID: "not-selected",
                providerAcceptsReferenceImages: true,
                jobID: UUID(), at: Date())
            referencePreview = LocalReferencePreview(review: staged.reference)
            problem = nil
        } catch {
            referencePreview = nil
            problem = "Cannot verify the approved reference. Recheck the current board and locally stored PNG."
        }
    }

    private func prepare() {
        guard let projectID, let shot, let board, let approval else {
            problem = "An approved board is required."
            return
        }
        do {
            try ProductionBoardApprovals.validate(approval, projectID: projectID, shot: shot, board: board)
            brief = try ProductionImagePlanning.prepare(
                shot: shot, board: board, approvedBoardIDs: [board.id],
                directingInstruction: direction, styleInstruction: style)
            problem = nil
        } catch {
            brief = nil
            problem = "The board has changed or is not ready. Approve its current revision before proceeding."
        }
    }
}

struct ProductionImagePlanningLauncher: View {
    @ObservedObject var model: ScreenplayViewModel
    let boardID: UUID
    @State private var showing = false

    var body: some View {
        Button("Review for production image…") { showing = true }
            .disabled(model.boardFrames.first(where: { $0.id == boardID })?.selectedImage == nil)
            .sheet(isPresented: $showing) {
                ProductionImagePlanningSheet(model: model, boardID: boardID) {
                    showing = false
                }
            }
    }
}
