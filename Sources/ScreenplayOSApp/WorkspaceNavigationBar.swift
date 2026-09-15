import SwiftUI

/// These controls belong to the application shell, outside collapsible document panels.
struct WorkspaceNavigationBar: View {
    @ObservedObject var model: ScreenplayViewModel
    var body: some View {
        HStack(spacing: 16) {
            Button {
                if model.focusMode {
                    model.focusMode = false
                    model.navigationVisible = true
                } else { model.navigationVisible.toggle() }
            } label: {
                Image(systemName: "sidebar.left")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(model.visibleWorkspaceRegions.contains(.navigation) ? "Hide Document Panel" : "Show Document Panel")
            .help("Show or hide document information and navigation")

            Picker("Mode", selection: Binding(get: { model.workflowMode }, set: model.setWorkflowMode)) {
                ForEach(WorkflowMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
            }
            .frame(width: 180)
            Picker("Workspace", selection: $model.sidebarMode) {
                ForEach(model.sidebarModesForCurrentWorkflow) { mode in Text(mode.rawValue).tag(mode) }
            }
            .frame(width: 240)
            Spacer(minLength: 0)
        }
        .pickerStyle(.menu)
        .controlSize(.small)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// Minimal packages currently have one supported work surface. Keep their context
/// visible without routing controls into a different, underlying legacy document.
struct PackageNavigationBar: View {
    var body: some View {
        HStack(spacing: 16) {
            HStack { Text("Mode").foregroundStyle(.secondary); Text("Script") }
            HStack { Text("Workspace").foregroundStyle(.secondary); Text("Editor") }
            Spacer()
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        .help("This package currently supports the Script editor.")
    }
}
