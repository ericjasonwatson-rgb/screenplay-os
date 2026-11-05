import SwiftUI
import ScreenplayDomain

/// Local management of staged-but-unsent production-image jobs. These records
/// remain visible after the originating consent sheet is closed or app restarts.
/// Reading and cancelling these jobs never contacts the provider.
struct ProductionImagePendingJobsSheet: View {
    @ObservedObject var model: ScreenplayViewModel
    let dismiss: () -> Void

    @State private var pending: [GenerationJobRecord] = []
    @State private var working = false
    @State private var message = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Unsent Production Image Requests").font(.title2.weight(.semibold))
                Spacer()
                Button("Refresh") { Task { await refresh() } }.disabled(working)
                Button("Close", action: dismiss)
            }
            Text("These requests are stored on this Mac. Awaiting-consent and queued jobs cannot send themselves. A recovered queued job requires review before any future Send action.")
                .font(.caption).foregroundStyle(.secondary)
            if working { ProgressView().controlSize(.small) }
            if pending.isEmpty && !working {
                Text("No unsent production-image requests were found for this project.")
                    .foregroundStyle(.secondary)
            }
            List(pending) { job in
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(job.providerID) · \(job.modelID)").font(.headline)
                    Text(job.status == .queued ? "Authorized locally — not submitted" : "Awaiting consent — not submitted")
                        .foregroundStyle(.secondary)
                    Text("Board: \(job.target.id.uuidString)")
                        .font(.caption.monospaced()).textSelection(.enabled)
                    Text("Job: \(job.id.uuidString)")
                        .font(.caption.monospaced()).textSelection(.enabled)
                    Text("Request SHA-256: \(job.requestSHA256)")
                        .font(.caption.monospaced()).textSelection(.enabled)
                    Button("Cancel this unsent request") {
                        Task { await cancel(jobID: job.id) }
                    }
                    .disabled(working)
                }
                .padding(.vertical, 6)
            }
            if !message.isEmpty {
                Text(message).font(.caption).foregroundStyle(.orange)
            }
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
            pending = []
            message = "No project is open."
            return
        }
        do {
            let controller = try model.generationJobController(for: projectID)
            let ledger = await controller.snapshot()
            pending = ledger.jobs
                .filter {
                    $0.capability == .image &&
                    $0.target.kind == .board &&
                    $0.request.parameters["workflow"] == "production_image_from_approved_board" &&
                    [.awaitingConsent, .queued].contains($0.status) &&
                    $0.submittedAt == nil
                }
                .sorted { $0.createdAt > $1.createdAt }
            message = ""
        } catch {
            pending = []
            message = "Could not read saved production-image requests."
        }
    }

    private func cancel(jobID: UUID) async {
        guard !working, let projectID = model.document?.screenplay.id else { return }
        working = true
        defer { working = false }
        do {
            let controller = try model.generationJobController(for: projectID)
            try await controller.cancel(jobID: jobID, at: Date())
            let ledger = await controller.snapshot()
            pending = ledger.jobs.filter {
                $0.capability == .image &&
                $0.target.kind == .board &&
                $0.request.parameters["workflow"] == "production_image_from_approved_board" &&
                [.awaitingConsent, .queued].contains($0.status) &&
                $0.submittedAt == nil
            }.sorted { $0.createdAt > $1.createdAt }
            message = "The unsent request was cancelled. No provider was contacted."
        } catch {
            message = "Could not cancel the request. Refresh and check its current state."
        }
    }
}
