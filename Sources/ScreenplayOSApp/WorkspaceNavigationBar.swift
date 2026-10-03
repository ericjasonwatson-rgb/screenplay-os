import SwiftUI

/// These controls belong to the application shell, outside collapsible document panels.
struct WorkspaceNavigationBar: View {
    @ChromeObserved var model: ScreenplayViewModel
    init(model: ScreenplayViewModel) { _model = ChromeObserved(wrappedValue: model, .navigation) }
    var body: some View {
        HStack(spacing: 10) {
            DocumentPanelButton(isVisible: model.visibleWorkspaceRegions.contains(.navigation)) {
                if model.focusMode {
                    model.focusMode = false
                    model.navigationVisible = true
                } else { model.navigationVisible.toggle() }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    Text("Mode").foregroundStyle(.secondary)
                    Picker("Mode", selection: Binding(get: { model.workflowMode }, set: model.setWorkflowMode)) {
                        ForEach(WorkflowMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                    }.labelsHidden().pickerStyle(.segmented).frame(width: 300)
                }.fixedSize()
                Picker("Mode", selection: Binding(get: { model.workflowMode }, set: model.setWorkflowMode)) {
                    ForEach(WorkflowMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                }.frame(width: 156)
            }
            Picker("Workspace", selection: Binding(get: { model.sidebarMode }, set: { model.showSidebarMode($0); model.focusMode = false; model.navigationVisible = true })) {
                ForEach(model.sidebarModesForCurrentWorkflow) { mode in Text(mode.rawValue).tag(mode) }
            }
            .frame(width: 206)
            .help("Choose what appears in the document sidebar. Mode changes the main work surface.")
            Spacer(minLength: 0)
            PageZoomControl(percent: Binding(get: { Int((model.pageZoom * 100).rounded()) },
                set: { model.pageZoom = Double($0) / 100 }),
                percentages: Array(stride(from: 80, through: 135, by: 5)), offersFitWidth: false)
        }
        .pickerStyle(.menu)
        .controlSize(.small)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .studioStrip()
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// Minimal packages currently have one supported work surface. Keep their context
/// visible without routing controls into a different, underlying legacy document.
struct PackageNavigationBar: View {
    @Binding var zoomPercent: Int
    @Binding var navigationVisible: Bool
    var body: some View {
        HStack(spacing: 10) {
            DocumentPanelButton(isVisible: navigationVisible) { navigationVisible.toggle() }
            HStack { Text("Mode").foregroundStyle(.secondary); Text("Script") }
            HStack { Text("Workspace").foregroundStyle(.secondary); Text("Editor") }
            Spacer()
            PageZoomControl(percent: $zoomPercent)

        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .studioStrip()
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// Shared shell controls; each editor retains its own document and view state.
struct DocumentPanelButton: View {
    let isVisible: Bool
    let toggle: () -> Void
    var body: some View {
        Button(action: toggle) { Image(systemName: "sidebar.left") }
            .buttonStyle(StudioButtonStyle(selected: isVisible))
            .accessibilityLabel(isVisible ? "Hide Document Panel" : "Show Document Panel")
            .help("Show or hide document information and navigation")
    }
}

struct PageZoomControl: View {
    @Binding var percent: Int
    var percentages = [50, 75, 100, 125, 150, 175, 200, 250, 300]
    var offersFitWidth = true
    var body: some View {
        Picker("Zoom", selection: $percent) {
            if offersFitWidth { Text("Fit Width").tag(0) }
            ForEach(percentages, id: \.self) { value in Text("\(value)%").tag(value) }
        }
        .pickerStyle(.menu).frame(width: 135)
        .accessibilityLabel("Page zoom")
        .help("Scale the writing view. Font sizes and printed pages stay unchanged.")
    }
}
