import AppKit
import Foundation
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

extension CampaignPanelLifecycleTests {
    /// Hosted acceptance through the real sheet, native text editor and public
    /// accessibility/control actions. Seed/race writers only establish context;
    /// no model/session call substitutes for an approval action under test.
    @Suite("Campaign baseline-bound approval review", .serialized)
    @MainActor
    struct CampaignApprovalPanelTests {
        @Test func switchingIdenticalBaselinesDiscardsTypedAndPreviewedEvidence() async throws {
            let fixture = try CampaignPanelFixture()
            defer { fixture.close() }
            let seed = try seed(fixture)
            _ = try await fixture.open()
            try await fixture.selectTab("Baseline & Changes")
            for previewFirst in [false, true] {
                try await selectBaseline(seed.second, fixture: fixture)
                try await prepare(fixture, evidence: "Evidence belongs only to synthetic baseline B")
                if previewFirst { try await preview(fixture) }
                try await selectBaseline(seed.first, fixture: fixture)
                try await expectBlank(fixture)
                #expect(try fixture.ledger() == seed.ledger)
                #expect(try bytes(fixture) == seed.bytes)
                try await prepare(fixture, evidence: "Fresh evidence for synthetic baseline A")
                try await preview(fixture)
                #expect(try await text(fixture, "campaign.approval.preview.baseline.id").contains(seed.first.id.uuidString))
                try await selectBaseline(seed.second, fixture: fixture)
                try await expectBlank(fixture)
            }
            #expect(try bytes(fixture) == seed.bytes)
            #expect(fixture.model.document == seed.document)
        }

        @Test func creativeAndSpendRequireExplicitPreviewPersistExactScopeAndSurviveDraftUndo() async throws {
            let fixture = try CampaignPanelFixture()
            defer { fixture.close() }
            let seed = try seed(fixture)
            _ = try await fixture.open()
            try await fixture.selectTab("Baseline & Changes")
            try await expectBlank(fixture)
            let creativeEvidence = "Synthetic creative-only approval: message C-17. No spending authority."
            try await prepare(fixture, evidence: creativeEvidence)
            try await expectAbsent(fixture, "campaign.approval.confirm")
            try await preview(fixture)
            try await expectPreview(fixture, baseline: seed.second, scope: "Creative", evidence: creativeEvidence)
            #expect(try bytes(fixture) == seed.bytes, "Preview must not save a decision.")
            try await expectDisabled(fixture, "campaign.undo")
            try await fixture.press("campaign.approval.confirm")
            try await fixture.expectLedger { $0.decisions.count == 1 }
            let creative = try #require(try fixture.ledger().decisions.first)
            #expect(creative.baselineID == seed.second.id && creative.scope == .creative)
            #expect(creative.approver == "Synthetic Client" && creative.evidence == creativeEvidence)
            #expect(creative.spendCeilingMinorUnits == nil && creative.currencyCode == nil)
            #expect(try await text(fixture, "campaign.approval.history.\(creative.id).evidence") == creativeEvidence)
            try await expectBlank(fixture)
            try await expectDisabled(fixture, "campaign.undo")

            try await selectScope("Additional spend", fixture: fixture)
            try await expectBlank(fixture)
            let spendEvidence = "Synthetic ceiling-only approval: message S-18. No provider request."
            try await prepare(fixture, evidence: spendEvidence)
            try await fixture.replaceText("campaign.approval.ceiling", with: "12500")
            try await fixture.replaceText("campaign.approval.currency", with: "USD")
            try await preview(fixture)
            try await expectPreview(fixture, baseline: seed.second, scope: "Spend", evidence: spendEvidence)
            let ceiling = try await text(fixture, "campaign.approval.preview.ceiling")
            #expect(ceiling == "Ceiling: 12500 minor units · USD",
                    "Preview must show the exact raw minor-unit ceiling and currency; actual text: \(ceiling)")
            #expect(try fixture.ledger().decisions == [creative])
            try await fixture.press("campaign.approval.confirm")
            try await fixture.expectLedger { $0.decisions.count == 2 }
            let recorded = try fixture.ledger()
            let spend = try #require(recorded.decisions.last)
            #expect(spend.baselineID == seed.second.id && spend.scope == .spend)
            #expect(spend.approver == "Synthetic Client" && spend.evidence == spendEvidence)
            #expect(spend.spendCeilingMinorUnits == 12500 && spend.currencyCode == "USD")
            #expect(recorded.baselines == seed.ledger.baselines && recorded.draft == seed.ledger.draft)
            try await expectAbsent(fixture, "campaign.approval.confirm")
            try await expectDisabled(fixture, "campaign.undo")
            try await fixture.selectTab("Brief & Deliverables")
            try await fixture.replaceText("campaign.field.Brand", with: "Synthetic changed draft")
            try await fixture.expectLedger { $0.draft.brief.brand == "Synthetic changed draft" }
            try await fixture.press("campaign.undo")
            try await fixture.expectLedger { $0 == recorded }
            try await expectDisabled(fixture, "campaign.undo")
            try await fixture.press("campaign.close")
            try await fixture.expectDismissed()
            _ = try await fixture.open()
            try await fixture.selectTab("Baseline & Changes")
            #expect(try fixture.ledger() == recorded)
            #expect(try await text(fixture, "campaign.approval.history.\(spend.id).evidence") == spendEvidence)
            try await selectBaseline(seed.first, fixture: fixture)
            try await expectAbsent(fixture, "campaign.approval.history.\(creative.id).evidence")
            try await expectAbsent(fixture, "campaign.approval.history.\(spend.id).evidence")
            #expect(fixture.model.document == seed.document)
        }

        @Test func fieldAndScopeChangesRevokePreviewIncludingNormalizationOnlyEdits() async throws {
            let fixture = try CampaignPanelFixture()
            defer { fixture.close() }
            let seed = try seed(fixture)
            _ = try await fixture.open()
            try await fixture.selectTab("Baseline & Changes")
            try await prepare(fixture, evidence: "Synthetic exact evidence")
            for (field, value) in [("approver", "Synthetic Client "), ("evidence", "Synthetic revised evidence")] {
                try await preview(fixture)
                try await fixture.replaceText("campaign.approval.\(field)", with: value)
                try await expectAbsent(fixture, "campaign.approval.confirm")
                #expect(try bytes(fixture) == seed.bytes)
            }
            // Canonically equivalent Strings must still revoke a byte-bound
            // preview when the native editor changes the actual UTF-8 evidence.
            let composed = "Synthetic caf\u{00E9} approval"
            let decomposed = "Synthetic cafe\u{0301} approval"
            #expect(composed == decomposed && Data(composed.utf8) != Data(decomposed.utf8))
            try await fixture.replaceText("campaign.approval.evidence", with: composed)
            try await preview(fixture)
            let composedPreview = try await readOnly(fixture, "campaign.approval.preview.evidence")
            #expect(Data(composedPreview.utf8) == Data(composed.utf8))
            try await fixture.replaceText("campaign.approval.evidence", with: decomposed)
            try await expectAbsent(fixture, "campaign.approval.confirm")
            let edited = try await fixture.control("campaign.approval.evidence")
            let editedValue = try #require(try campaignAXValue(edited) as? String)
            #expect(Data(editedValue.utf8) == Data(decomposed.utf8))
            #expect(try bytes(fixture) == seed.bytes)
            try await preview(fixture)
            let decomposedPreview = try await readOnly(fixture, "campaign.approval.preview.evidence")
            #expect(Data(decomposedPreview.utf8) == Data(decomposed.utf8))
            try await selectScope("Additional spend", fixture: fixture)
            try await expectAbsent(fixture, "campaign.approval.confirm")
            try await expectBlank(fixture)
            try await prepare(fixture, evidence: "Synthetic revised evidence")
            try await fixture.replaceText("campaign.approval.ceiling", with: "100")
            try await fixture.replaceText("campaign.approval.currency", with: "USD")
            try await preview(fixture)
            try await fixture.replaceText("campaign.approval.ceiling", with: "101")
            try await expectAbsent(fixture, "campaign.approval.confirm")
            try await preview(fixture)
            try await fixture.replaceText("campaign.approval.currency", with: "EUR")
            try await expectAbsent(fixture, "campaign.approval.confirm")
            try await preview(fixture)
            try await selectScope("Production approach", fixture: fixture)
            try await expectBlank(fixture)
            try await prepare(fixture, evidence: "Synthetic revised evidence")
            try await preview(fixture)
            try await fixture.press("campaign.approval.confirm")
            try await fixture.expectLedger { $0.decisions.count == 1 }
            let decision = try #require(try fixture.ledger().decisions.first)
            #expect(decision.scope == .production)
            #expect(decision.spendCeilingMinorUnits == nil && decision.currencyCode == nil)
            #expect(decision.approver == "Synthetic Client" && decision.evidence == "Synthetic revised evidence")
        }

        @Test func cancelTabCloseAndEscapeDiscardUnconfirmedEntry() async throws {
            let fixture = try CampaignPanelFixture()
            defer { fixture.close() }
            let seed = try seed(fixture)
            _ = try await fixture.open()
            try await fixture.selectTab("Baseline & Changes")
            for dismissal in [Dismissal.cancel, .tab, .close, .escape] {
                try await prepare(fixture, evidence: "Unconfirmed synthetic entry: \(dismissal)")
                try await preview(fixture)
                switch dismissal {
                case .cancel: try await fixture.press("campaign.approval.cancel")
                case .tab:
                    try await fixture.selectTab("Brief & Deliverables")
                    try await fixture.selectTab("Baseline & Changes")
                case .close, .escape:
                    if dismissal == .close {
                        try await fixture.press("campaign.close")
                    } else {
                        let sheet = try #require(fixture.window.attachedSheet)
                        let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
                            modifierFlags: [], timestamp: 0, windowNumber: sheet.windowNumber, context: nil,
                            characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
                        #expect(sheet.performKeyEquivalent(with: escape))
                    }
                    try await fixture.expectDismissed()
                    _ = try await fixture.open()
                    try await fixture.selectTab("Baseline & Changes")
                }
                try await expectBlank(fixture)
                #expect(try fixture.ledger() == seed.ledger)
                #expect(try bytes(fixture) == seed.bytes)
                try await expectDisabled(fixture, "campaign.undo")
            }
            #expect(fixture.model.document == seed.document)
        }

        @Test func concurrentSavedChangeCannotBeOverwrittenByNativeConfirm() async throws {
            let fixture = try CampaignPanelFixture()
            defer { fixture.close() }
            let seed = try seed(fixture)
            _ = try await fixture.open()
            try await fixture.selectTab("Baseline & Changes")
            try await prepare(fixture, evidence: "Synthetic preview before concurrent draft change")
            try await preview(fixture)
            // Race setup only: the first sheet's actual Confirm remains the
            // action under test. This writer never records an approval.
            let writer = CampaignWorkspaceSession(projectID: seed.ledger.projectID, root: fixture.root)
            try #require(writer.problem == nil)
            writer.updateDraft { $0.brief.objective = "Synthetic concurrent objective" }
            try #require(writer.problem == nil)
            let concurrent = writer.ledger
            let saved = try bytes(fixture)
            try await fixture.press("campaign.approval.confirm")
            #expect(try fixture.ledger() == concurrent)
            #expect(try bytes(fixture) == saved)
            #expect(try fixture.ledger().decisions.isEmpty)
            let problem = try await text(fixture, "campaign.approval.problem")
            #expect(!problem.isEmpty)
            try await fixture.press("campaign.close")
            try await fixture.expectDismissed()
            _ = try await fixture.open()
            try await fixture.selectTab("Baseline & Changes")
            try await expectAbsent(fixture, "campaign.approval.confirm")
            #expect(try fixture.ledger() == concurrent)
        }

        @Test func projectReplacementDiscardsApprovalWithoutTouchingEitherProject() async throws {
            let fixture = try CampaignPanelFixture()
            defer { fixture.close() }
            let seed = try seed(fixture)
            let originalURL = try #require(fixture.model.saveURL)
            _ = try await fixture.open()
            try await fixture.selectTab("Baseline & Changes")
            try await prepare(fixture, evidence: "Synthetic entry bound to the first project")
            try await preview(fixture)
            // External project lifecycle event, not a substitute approval action.
            fixture.model.newDocument()
            let replacementID = try #require(fixture.model.document?.project.id)
            #expect(replacementID != seed.ledger.projectID)
            try await fixture.expectDismissed()
            #expect(try Data(contentsOf: fixture.campaignURL(projectID: seed.ledger.projectID)) == seed.bytes)
            #expect(!FileManager.default.fileExists(atPath: try fixture.campaignURL(projectID: replacementID).path))
            fixture.model.loadScreenplayOSDocument(at: originalURL)
            _ = try await fixture.open()
            try await fixture.selectTab("Baseline & Changes")
            try await expectBlank(fixture)
            #expect(try bytes(fixture) == seed.bytes)
        }

        @Test func repeatedImmediateProjectReplacementReopensCorrectSessionWithoutApprovalTab() async throws {
            let fixture = try CampaignPanelFixture()
            defer { fixture.close() }
            _ = try await fixture.scriptEditor()
            let originalID = try #require(fixture.model.document?.project.id)
            let originalURL = try #require(fixture.model.saveURL)
            _ = try await fixture.open()
            let originalBrand = "Synthetic original project"
            try await fixture.replaceText("campaign.field.Brand", with: originalBrand)
            try await fixture.expectLedger { $0.projectID == originalID && $0.draft.brief.brand == originalBrand }
            let originalLedger = try fixture.ledger()
            let originalBytes = try bytes(fixture)
            var replacementBytes: [UUID: Data] = [:]

            // Deliberately never select Baseline & Changes. The regression is
            // ancestor-sheet teardown and an old session observing a project
            // replacement, even when no approval editor was ever mounted.
            for cycle in 1...3 {
                #expect(fixture.model.document?.project.id == originalID)
                fixture.model.newDocument()
                let replacementID = try #require(fixture.model.document?.project.id)
                #expect(replacementID != originalID)
                try await fixture.expectDismissed()
                #expect(try Data(contentsOf: fixture.campaignURL(projectID: originalID)) == originalBytes)
                #expect(!FileManager.default.fileExists(atPath: try fixture.campaignURL(projectID: replacementID).path))

                _ = try await fixture.open()
                let blank = try await fixture.control("campaign.field.Brand")
                #expect(try campaignAXValue(blank) as? String == "")
                #expect(fixture.model.document?.project.id == replacementID)
                let replacementBrand = "Synthetic replacement project \(cycle)"
                try await fixture.replaceText("campaign.field.Brand", with: replacementBrand)
                try await fixture.expectLedger {
                    $0.projectID == replacementID && $0.draft.brief.brand == replacementBrand
                }
                let replacementLedger = try fixture.ledger()
                replacementBytes[replacementID] = try bytes(fixture)
                try await fixture.press("campaign.close")
                try await fixture.expectDismissed()
                // No delay or re-presentation retry between native dismissal,
                // loading the earlier project and its single reopen attempt.
                fixture.model.loadScreenplayOSDocument(at: originalURL)
                #expect(fixture.model.document?.project.id == originalID)
                _ = try await fixture.open()
                let restored = try await fixture.control("campaign.field.Brand")
                #expect(try campaignAXValue(restored) as? String == originalBrand)
                #expect(try fixture.ledger() == originalLedger)
                #expect(try bytes(fixture) == originalBytes)
                #expect(try fixture.ledger(projectID: replacementID) == replacementLedger)
                for (id, saved) in replacementBytes {
                    #expect(try Data(contentsOf: fixture.campaignURL(projectID: id)) == saved)
                }
            }
        }

        private enum Dismissal { case cancel, tab, close, escape }
        private struct Seed {
            let first: CampaignBaseline
            let second: CampaignBaseline
            let ledger: CampaignLedger
            let bytes: Data
            let document: ScreenplayOSDocument
        }

        private func seed(_ fixture: CampaignPanelFixture) throws -> Seed {
            let document = try #require(fixture.model.document)
            let session = CampaignWorkspaceSession(projectID: document.project.id, root: fixture.root)
            try #require(session.problem == nil)
            session.updateDraft {
                $0.brief = .init(brand: "Synthetic approval campaign", objective: "Offline approval acceptance")
                $0.deliverables = [.init(name: "Synthetic hero", durationSeconds: 30, aspectRatio: "16:9")]
            }
            let firstID = try #require(session.freeze(name: "Synthetic baseline A", document: document))
            let secondID = try #require(session.freeze(name: "Synthetic baseline B", document: document))
            let first = try #require(session.ledger.baselines.first { $0.id == firstID })
            let second = try #require(session.ledger.baselines.first { $0.id == secondID })
            #expect(first.id != second.id && first.draft == second.draft && first.sources == second.sources)
            #expect(session.ledger.decisions.isEmpty)
            return Seed(first: first, second: second, ledger: session.ledger,
                        bytes: try bytes(fixture), document: document)
        }

        private func bytes(_ fixture: CampaignPanelFixture) throws -> Data {
            let projectID = try #require(fixture.model.document?.project.id)
            return try Data(contentsOf: fixture.campaignURL(projectID: projectID))
        }

        private func prepare(_ fixture: CampaignPanelFixture, evidence: String) async throws {
            try await fixture.replaceText("campaign.approval.approver", with: "Synthetic Client")
            try await fixture.replaceText("campaign.approval.evidence", with: evidence)
        }

        private func preview(_ fixture: CampaignPanelFixture) async throws {
            try await fixture.press("campaign.approval.preview")
            _ = try await fixture.control("campaign.approval.confirm")
        }

        private func expectBlank(_ fixture: CampaignPanelFixture) async throws {
            let content = try #require(fixture.window.attachedSheet?.contentView)
            let cleared = try await waitForNativeUI(content) {
                // SwiftUI may replace AX nodes after the native picker action.
                // Resolve both editable fields anew on every run-loop turn.
                ["approver", "evidence"].allSatisfy { field in
                    guard let control = campaignAXElement(in: content, matching: {
                        $0.accessibilityIdentifier?() == "campaign.approval.\(field)"
                    }) else { return false }
                    let getter: (() -> Any?)? = control.accessibilityValue
                    return getter?() as? String == ""
                }
            }
            #expect(cleared, "Both approval fields must visibly clear after the native action.")
            try await expectAbsent(fixture, "campaign.approval.confirm")
            try await expectDisabled(fixture, "campaign.approval.preview")
        }

        private func expectPreview(_ fixture: CampaignPanelFixture, baseline: CampaignBaseline,
                                   scope: String, evidence: String) async throws {
            #expect(try await text(fixture, "campaign.approval.preview.baseline.name").contains(baseline.name))
            #expect(try await text(fixture, "campaign.approval.preview.baseline.id").contains(baseline.id.uuidString))
            #expect(try await text(fixture, "campaign.approval.preview.baseline.date") ==
                    "Frozen: \(baseline.createdAt.formatted(date: .complete, time: .complete))")
            #expect(try await text(fixture, "campaign.approval.preview.scope").contains(scope))
            #expect(try await readOnly(fixture, "campaign.approval.preview.approver") == "Synthetic Client")
            #expect(try await readOnly(fixture, "campaign.approval.preview.evidence") == evidence)
        }

        private func text(_ fixture: CampaignPanelFixture, _ identifier: String) async throws -> String {
            let control = try await fixture.control(identifier)
            let getter: (() -> Any?)? = control.accessibilityValue
            if let value = getter?() as? String { return value }
            return try #require(control.accessibilityLabel?())
        }

        private func readOnly(_ fixture: CampaignPanelFixture, _ identifier: String) async throws -> String {
            let control = try await fixture.control(identifier)
            let view = try #require(control as? NSTextView)
            #expect(!view.isEditable && view.isSelectable && !view.isRichText)
            return view.string
        }

        private func expectAbsent(_ fixture: CampaignPanelFixture, _ identifier: String) async throws {
            let content = try #require(fixture.window.attachedSheet?.contentView)
            #expect(try await waitForNativeUI(content) {
                campaignAXElement(in: content) { $0.accessibilityIdentifier?() == identifier } == nil
            })
        }

        private func expectDisabled(_ fixture: CampaignPanelFixture, _ identifier: String) async throws {
            _ = try await fixture.control(identifier)
            let content = try #require(fixture.window.attachedSheet?.contentView)
            #expect(try await waitForNativeUI(content) {
                campaignAXElement(in: content) { $0.accessibilityIdentifier?() == identifier }?
                    .isAccessibilityEnabled?() == false
            })
        }

        private func selectBaseline(_ baseline: CampaignBaseline, fixture: CampaignPanelFixture) async throws {
            let element = try await fixture.control("campaign.baseline.picker")
            let popup: NSPopUpButton
            if let button = element as? NSPopUpButton {
                popup = button
            } else {
                let cell = try #require(element as? NSPopUpButtonCell,
                    "Baseline picker must expose its public native control association; do not guess backing views.")
                popup = try #require(cell.controlView as? NSPopUpButton)
                try #require(popup.cell === cell)
            }
            try #require(popup.window === fixture.window.attachedSheet && popup.isEnabled)
            let menu = try #require(popup.menu)
            // SwiftUI's native popup installs actions on its menu items, not
            // necessarily on the NSPopUpButton itself. Dispatch the exact item
            // through AppKit's public menu action path, including validation.
            // https://developer.apple.com/documentation/appkit/nsmenu/performactionforitem(at:)
            menu.update()
            let matches = menu.items.filter { $0.title.hasPrefix(baseline.name + " · ") }
            let item = try #require(matches.count == 1 ? matches.first : nil)
            let index = try #require(menu.items.firstIndex { $0 === item })
            try #require(popup.menu === menu && item.menu === menu && menu.item(at: index) === item)
            try #require(item.isEnabled && item.action != nil,
                "The exact baseline menu item must expose its enabled native action.")
            menu.performActionForItem(at: index)
            let content = try #require(fixture.window.attachedSheet?.contentView)
            try #require(try await waitForNativeUI(content) {
                guard let value = campaignAXElement(in: content, matching: {
                    $0.accessibilityIdentifier?() == "campaign.approval.baseline.id"
                }) else { return false }
                let getter: (() -> Any?)? = value.accessibilityValue
                return ((getter?() as? String) ?? value.accessibilityLabel?() ?? "").contains(baseline.id.uuidString)
            })
        }

        private func selectScope(_ label: String, fixture: CampaignPanelFixture) async throws {
            let element = try await fixture.control("campaign.approval.scope")
            // Resolve a named child strictly within this identified picker.
            func labeledChild(_ root: AnyObject) -> AnyObject? {
                var remaining = 60
                func search(_ node: AnyObject, depth: Int = 0) -> AnyObject? {
                    guard depth < 8, remaining > 0 else { return nil }
                    remaining -= 1
                    if node.accessibilityLabel?() == label { return node }
                    for child in node.accessibilityChildren?() ?? [] {
                        if let found = search(child as AnyObject, depth: depth + 1) { return found }
                    }
                    return nil
                }
                return search(root)
            }
            func nativeControl(_ node: AnyObject) -> NSSegmentedControl? {
                if let control = node as? NSSegmentedControl { return control }
                if let cell = node as? NSSegmentedCell,
                   let control = cell.controlView as? NSSegmentedControl,
                   control.cell === cell { return control }
                return nil
            }
            if let child = labeledChild(element), child.accessibilityPerformPress?() == true {
                // Wait below for selected state and the resulting field surface.
            } else {
                let control = try #require(nativeControl(element),
                    "Scope picker has neither an actionable named AX child nor a public native control association.")
                try #require(control.window === fixture.window.attachedSheet && control.isEnabled)
                let index = try #require((0..<control.segmentCount).first { control.label(forSegment: $0) == label })
                control.selectedSegment = index
                try #require(control.sendAction(control.action, to: control.target))
            }
            let content = try #require(fixture.window.attachedSheet?.contentView)
            let committed = try await waitForNativeUI(content) {
                guard let current = campaignAXElement(in: content, matching: {
                    $0.accessibilityIdentifier?() == "campaign.approval.scope"
                }) else { return false }
                let selected: Bool
                if let control = nativeControl(current), control.window === fixture.window.attachedSheet {
                    let index = control.selectedSegment
                    selected = index >= 0 && index < control.segmentCount && control.label(forSegment: index) == label
                } else if let child = labeledChild(current) {
                    let getter: (() -> Any?)? = child.accessibilityValue
                    selected = child.isAccessibilitySelected?() == true || (getter?() as? NSNumber)?.boolValue == true
                } else {
                    selected = false
                }
                let hasCeiling = campaignAXElement(in: content) {
                    $0.accessibilityIdentifier?() == "campaign.approval.ceiling"
                } != nil
                return selected && hasCeiling == (label == "Additional spend")
            }
            try #require(committed, "Scope selection must commit its exact selected label and expected fields.")
        }
    }
}
