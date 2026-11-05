import AppKit
import SwiftUI
import ScreenplayDomain

/// A local-only first step from an authored storyboard to a production-image
/// brief. The approval is intentionally session-scoped until project-persistent,
/// revision-aware approval records exist. No provider requests are possible here.
struct ProductionImagePlanningSheet: View {
    let shot: Shot
    let board: BoardFrame
    let dismiss: () -> Void

    @State private var approvedInSession = false
    @State private var direction = "Preserve the approved storyboard composition and screen direction."
    @State private var style = ""
    @State private var brief: ProductionImageBrief?
    @State private var problem: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Production Image — Storyboard Review").font(.headline)
                    Spacer()
                    Button("Close", action: dismiss)
                }
                Text("Review the selected board before planning a production image. This screen is local-only; it cannot upload images or send paid generation requests.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Shot: \(shot.label)").font(.subheadline.weight(.medium))
                Text("Board: \(board.label)")
                if let selected = board.selectedImage {
                    Text("Selected board image: \(selected.id.uuidString)")
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                } else {
                    Label("Choose a board image in Board Details first.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                Toggle("I approve this selected storyboard for production-image planning in this session", isOn: $approvedInSession)
                    .onChange(of: approvedInSession) { _ in brief = nil }
                Text("Direction").font(.subheadline.weight(.medium))
                TextEditor(text: $direction)
                    .frame(height: 100)
                    .border(.secondary.opacity(0.35))
                    .onChange(of: direction) { _ in brief = nil }
                Text("Visual style").font(.subheadline.weight(.medium))
                TextField("Style reference or art direction", text: $style)
                    .onChange(of: style) { _ in brief = nil }
                HStack {
                    Button("Prepare production-image brief") { prepare() }
                        .disabled(!approvedInSession || board.selectedImage == nil)
                    Spacer()
                    if let problem { Text(problem).foregroundStyle(.orange).font(.caption) }
                }
                if let brief {
                    Divider()
                    Text("Prepared local brief").font(.headline)
                    Text(brief.promptPreview)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Prompt fingerprint: \(brief.promptSHA256)").font(.caption.monospaced())
                    Text("No provider has been selected, no image has been transmitted, and no production Take has been created.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .frame(minWidth: 620, idealWidth: 740, minHeight: 540)
    }

    private func prepare() {
        do {
            brief = try ProductionImagePlanning.prepare(
                shot: shot, board: board,
                approvedBoardIDs: approvedInSession ? [board.id] : [],
                directingInstruction: direction, styleInstruction: style)
            problem = nil
        } catch {
            brief = nil
            problem = "The board or image is not ready for this step. Check selection, duration and direction."
        }
    }
}

struct ProductionImagePlanningLauncher: View {
    let shot: Shot
    let board: BoardFrame
    @State private var showing = false

    var body: some View {
        Button("Review for production image…") { showing = true }
            .disabled(board.selectedImage == nil)
            .sheet(isPresented: $showing) {
                ProductionImagePlanningSheet(shot: shot, board: board) {
                    showing = false
                }
            }
    }
}
