import SwiftUI
import ScreenplayDomain

/// Manage locally staged, queued and completed production-image jobs.
/// A completed image can be restored from the local result vault without
/// contacting OpenAI or selecting the image in the edit.
struct ProductionImagePendingJobsSheet: View {
    @ObservedObject var model: ScreenplayViewModel
    let dismiss: () -> Void

    @State private var pending: [GenerationJobRecord] = []
    @State private var recoverable: [GenerationJobRecord] = []
    @State private var unresolved: [GenerationJobRecord] = []
    @State private var working = false
    @State private var message = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Production Image Jobs & Recovery").font(.title2.weight(.semibold))
                Spacer()
                Button("Refresh") { Task { await refresh() } }.disabled(working)
                Button("Close", action: dismiss)
            }
            Text("Unsent requests remain local. Saved results can be restored without another API charge. Submitted requests with no saved result are shown separately; their provider outcome may be unknown and they are never retried automatically.")
                .font(.caption).foregroundStyle(.secondary)
            if working { ProgressView().controlSize(.small) }
            if pending.isEmpty && recoverable.isEmpty && unresolved.isEmpty && !working {
                Text("No unsent or recoverable production-image jobs were found for this project.")
                    .foregroundStyle(.secondary)
            }
            List {
                if !pending.isEmpty {
                    Section("Unsent requests") {
                        ForEach(pending) { job in
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(job.providerID) · \(job.modelID)").font(.headline)
                                Text(job.status == .queued
                                     ? "Authorized locally — not submitted"
                                     : "Awaiting consent — not submitted")
                                    .foregroundStyle(.secondary)
                                Text("Board: \(job.target.id.uuidString)")
                                    .font(.caption.monospaced()).textSelection(.enabled)
                                Text("Job: \(job.id.uuidString)")
                                    .font(.caption.monospaced()).textSelection(.enabled)
                                Button("Cancel this unsent request") {
                                    Task { await cancel(jobID: job.id) }
                                }
                                .disabled(working)
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
                if !unresolved.isEmpty {
                    Section("Submitted requests — outcome unconfirmed") {
                        ForEach(unresolved) { job in
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(job.providerID) · \(job.modelID)").font(.headline)
                                Text("Submission may have reached the provider. No saved result was found.")
                                    .foregroundStyle(.orange)
                                Text("Job: \(job.id.uuidString)")
                                    .font(.caption.monospaced()).textSelection(.enabled)
                                if let submittedAt = job.submittedAt {
                                    Text("Submitted: \(submittedAt.formatted(date: .abbreviated, time: .standard))")
                                        .font(.caption).textSelection(.enabled)
                                }
                                Text("Request SHA-256: \(job.requestSHA256)")
                                    .font(.caption.monospaced()).textSelection(.enabled)
                                Text(ProductionImageUncertainSubmission.guidance)
                                    .font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 6)
                        }
                    }
                }
                if !recoverable.isEmpty {
                    Section("Saved images awaiting project recovery") {
                        ForEach(recoverable) { job in
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(job.providerID) · \(job.modelID)").font(.headline)
                                Text(job.status == .running
                                     ? "Saved output found; completion was not recorded. Review and reconcile locally."
                                     : "Generated image preserved locally — no new request needed")
                                    .foregroundStyle(.secondary)
                                Text("Board: \(job.target.id.uuidString)")
                                    .font(.caption.monospaced()).textSelection(.enabled)
                                Text("Job: \(job.id.uuidString)")
                                    .font(.caption.monospaced()).textSelection(.enabled)
                                Button(job.status == .running
                                       ? "Reconcile saved output and restore (no send)"
                                       : "Restore as unselected Take (no send)") {
                                    Task { await recover(jobID: job.id) }
                                }
                                .disabled(working)
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            }
            if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.orange) }
        }
        .padding(20)
        .frame(minWidth: 620, idealWidth: 760, minHeight: 440)
        .task { await refresh() }
    }

    private func refresh() async {
        guard !working else { return }
        working = true
        defer { working = false }
        guard let projectID = model.document?.screenplay.id else {
            pending = []; recoverable = []; unresolved = []
            message = "No project is open."
            return
        }
        do {
            try await loadJobs(for: projectID)
            message = ""
        } catch {
            pending = []; recoverable = []
            message = "Could not read the locally saved production-image jobs."
        }
    }

    private func loadJobs(for projectID: UUID) async throws {
        let controller = try model.generationJobController(for: projectID)
        let ledger = try await controller.snapshot().validated()
        guard let document = model.document,
              document.screenplay.id == projectID else {
            pending = []; recoverable = []
            return
        }
        let jobs = ledger.jobs.filter {
            $0.capability == .image &&
            $0.target.kind == .board &&
            $0.request.parameters["workflow"] == "production_image_from_approved_board"
        }
        pending = jobs.filter {
            [.awaitingConsent, .queued].contains($0.status) && $0.submittedAt == nil
        }.sorted { $0.createdAt > $1.createdAt }

        let recoveryRoot = try ProductionImageResultVault.defaultRoot()
        unresolved = jobs.filter { job in
            let hasSavedResult = (try? ProductionImageResultVault.load(
                projectID: projectID, jobID: job.id, root: recoveryRoot)) != nil
            return ProductionImageUncertainSubmission.isUnresolved(
                job, hasPreservedImage: hasSavedResult)
        }.sorted { $0.createdAt > $1.createdAt }
        recoverable = jobs.filter { job in
            guard [.succeeded, .running].contains(job.status),
                  job.consentedAt != nil, job.submittedAt != nil,
                  (job.status == .running || job.completedAt != nil),
                  let board = document.boardFrames.first(where: { $0.id == job.target.id }),
                  !board.imageVersions.contains(where: { $0.generationJobID == job.id }) else {
                return false
            }
            return (try? ProductionImageResultVault.load(
                projectID: projectID, jobID: job.id, root: recoveryRoot)) != nil
        }.sorted { $0.createdAt > $1.createdAt }
    }

    private func cancel(jobID: UUID) async {
        guard !working, let projectID = model.document?.screenplay.id else { return }
        working = true
        defer { working = false }
        do {
            let controller = try model.generationJobController(for: projectID)
            try await controller.cancel(jobID: jobID, at: Date())
            try await loadJobs(for: projectID)
            message = "The unsent request was cancelled. No provider was contacted."
        } catch {
            message = "Could not cancel the request. Refresh and check its state."
        }
    }

    private func recover(jobID: UUID) async {
        guard !working,
              model.requireEntitlement(.takes),
              let projectID = model.document?.screenplay.id,
              let documentURL = model.saveURL else { return }
        working = true
        defer { working = false }
        do {
            let controller = try model.generationJobController(for: projectID)
            let ledger = try await controller.snapshot().validated()
            guard let job = ledger.jobs.first(where: { $0.id == jobID }),
                  [.running, .succeeded].contains(job.status),
                  job.request.parameters["workflow"] == "production_image_from_approved_board",
                  let board = model.boardFrames.first(where: { $0.id == job.target.id }),
                  let shot = model.shots.first(where: { $0.id == board.shotID }) else {
                message = "The completed job or original storyboard is no longer available."
                return
            }
            let approvalRoot = try ProductionImageResultVault.defaultRoot()
            let approvalFile = approvalRoot.appendingPathComponent(
                "ScreenplayOS/Approvals/\(projectID.uuidString)/\(board.id.uuidString).json")
            let approval = try ProductionBoardApprovals.load(at: approvalFile)
            try ProductionBoardApprovals.validate(
                approval, projectID: projectID, shot: shot, board: board)
            if job.status == .running {
                // The filmmaker explicitly requested local reconciliation.
                // No outgoing provider request occurs; only an already saved
                // image can advance the persistent job to succeeded.
                try await ProductionImageInterruptedCompletionRecovery.completeFromVault(
                    controller: controller, jobID: jobID, approval: approval,
                    shot: shot, board: board, recoveryRoot: approvalRoot, at: Date())
            }
            let take = try await ProductionImageCompletedResultRecovery.candidate(
                controller: controller, jobID: jobID, approval: approval,
                shot: shot, board: board, documentURL: documentURL,
                recoveryRoot: approvalRoot, takeID: UUID())
            // The local filesystem and project may change during an await.
            guard model.document?.screenplay.id == projectID,
                  model.saveURL == documentURL,
                  model.boardFrames.first(where: { $0.id == board.id }) == board,
                  model.shots.first(where: { $0.id == shot.id }) == shot,
                  (try? ProductionBoardApprovals.load(at: approvalFile)) == approval else {
                message = "The project or approval changed. No Take was inserted."
                return
            }
            guard try model.appendProductionImageCandidate(take) else {
                message = "The project could not accept this Take."
                return
            }
            try await loadJobs(for: projectID)
            message = "Saved image restored as an unselected Take in Boards. No provider was contacted."
        } catch {
            message = "Recovery was not completed. The original approval, image, or job may have changed; no new request was sent."
        }
    }
}
