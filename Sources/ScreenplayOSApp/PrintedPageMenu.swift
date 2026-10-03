import AppKit
import SwiftUI

/// Populate page navigation only when opened, not once per page per keystroke.
struct PrintedPageMenu: NSViewRepresentable {
    @ChromeObserved var model: ScreenplayViewModel
    func makeCoordinator() -> Coordinator { Coordinator(model) }
    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: true)
        button.controlSize = .small
        button.font = .systemFont(ofSize: 11)
        button.addItem(withTitle: model.currentPrintedPageStatus)
        button.setAccessibilityLabel("Go to printed page")
        button.target = context.coordinator
        button.action = #selector(Coordinator.choose(_:))
        button.menu?.delegate = context.coordinator
        button.menu?.autoenablesItems = false
        return button
    }
    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.model = model
        let title = model.currentPrintedPageStatus
        if button.item(at: 0)?.title != title { button.item(at: 0)?.title = title }
    }
    @MainActor final class Coordinator: NSObject, NSMenuDelegate {
        var model: ScreenplayViewModel
        init(_ model: ScreenplayViewModel) { self.model = model }
        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            let heading = NSMenuItem(title: model.currentPrintedPageStatus, action: nil, keyEquivalent: "")
            heading.tag = -1
            menu.addItem(heading)
            let projection = model.printedLayout
            for (index, page) in projection.pages.enumerated() {
                let item = NSMenuItem(title: "PDF page \(page.label)", action: nil, keyEquivalent: "")
                item.tag = index
                item.isEnabled = projection.firstSourceCaret(onPage: index) != nil
                menu.addItem(item)
            }
        }
        @objc func choose(_ sender: NSPopUpButton) {
            guard let item = sender.selectedItem, item.tag >= 0 else { return }
            model.navigateToPrintedPage(item.tag)
        }
    }
}
