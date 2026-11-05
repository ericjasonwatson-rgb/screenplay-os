import Foundation

public enum CampaignSourceKind: String, Codable, CaseIterable { case brief, deliverable, assumption, script, shot, board }

/// Narrow local snapshot. No media URL, prompt-provider payload, or estimated/actual generation cost is captured.
public struct CampaignSourceSnapshot: Codable, Equatable, Identifiable {
    public let sourceKind: CampaignSourceKind
    public let sourceID: UUID
    public let fields: [String: String]
    public let linkedShotIDs: [UUID]
    public let linkedElementIDs: [UUID]
    public var id: String { sourceKind.rawValue + ":" + sourceID.uuidString }
    public var summary: String {
        var rows = fields.keys.sorted().map { "\($0): \(fields[$0] ?? "")" }
        if !linkedShotIDs.isEmpty { rows.append("Shot IDs: " + linkedShotIDs.map(\.uuidString).joined(separator: ", ")) }
        if !linkedElementIDs.isEmpty { rows.append("Script IDs: " + linkedElementIDs.map(\.uuidString).joined(separator: ", ")) }
        return rows.joined(separator: "\n")
    }

    static func validate(_ sources: [Self]) throws {
        guard Set(sources.map(\.id)).count == sources.count else { throw CampaignError.invalid("Duplicate source identifiers.") }
        for source in sources {
            guard [.script, .shot, .board].contains(source.sourceKind) else { throw CampaignError.invalid("Unexpected baseline source kind.") }
            try campaignUnique(source.linkedShotIDs, "source shot links")
            try campaignUnique(source.linkedElementIDs, "source screenplay links")
            guard let order = source.fields["Order"].flatMap(Int.init), order > 0 else {
                throw CampaignError.invalid("Source order must be a positive integer.")
            }
            if source.sourceKind == .script {
                guard let type = source.fields["Type"], ElementType(rawValue: type) != nil,
                      source.fields["Text"] != nil, source.fields["Text style"] != nil,
                      source.linkedElementIDs.isEmpty else { throw CampaignError.invalid("Malformed screenplay snapshot.") }
            } else {
                guard source.linkedShotIDs.count == 1,
                      let ranges = source.fields["Source ranges"],
                      let data = ranges.data(using: .utf8) else { throw CampaignError.invalid("Malformed source links.") }
                let refs = try JSONDecoder().decode([ShotSourceRef].self, from: data)
                guard Set(refs.map(\.screenplayElementID)) == Set(source.linkedElementIDs),
                      source.sourceKind != .shot || source.linkedShotIDs == [source.sourceID] else {
                    throw CampaignError.invalid("Source reference identities do not match.")
                }
            }
            if source.sourceKind == .board {
                guard let imageID = source.fields["Selected image ID"],
                      imageID.isEmpty || UUID(uuidString: imageID) != nil,
                      ["yes", "no"].contains(source.fields["Selected image unresolved"] ?? "") else {
                    throw CampaignError.invalid("Malformed selected image identity.")
                }
                guard let raw = source.fields["Duration seconds"], let seconds = Double(raw), seconds.isFinite, seconds > 0, seconds <= 86400 else {
                    throw CampaignError.invalid("Board duration must be finite and greater than zero, up to 86400 seconds.")
                }
            }
        }
    }

    public static func capture(_ document: ScreenplayOSDocument) throws -> [Self] {
        guard document.project.screenplayID == document.screenplay.id else {
            throw CampaignError.invalid("Project screenplay identity does not match its screenplay.")
        }
        try campaignUnique(document.screenplay.elements.map(\.id), "screenplay elements")
        try campaignUnique(document.shots.map(\.id), "shots")
        try campaignUnique(document.boardFrames.map(\.id), "boards")
        var result: [Self] = []
        for (index, element) in document.screenplay.elements.enumerated() {
            let directShots = document.shots.filter { $0.sourceRefs.contains { $0.screenplayElementID == element.id } }.map(\.id)
            let boardShots = document.boardFrames.filter { $0.sourceRefs.contains { $0.screenplayElementID == element.id } }.map(\.shotID)
            let shots = Array(Set(directShots + boardShots))
            result.append(Self(sourceKind: .script, sourceID: element.id, fields: [
                "Order": String(index + 1), "Type": element.type.rawValue, "Text": element.text,
                "Scene ID": element.spineID ?? "", "Text style": try campaignJSON(element.runs)
            ], linkedShotIDs: shots.sorted(by: uuidOrder), linkedElementIDs: []))
        }
        for (index, shot) in document.shots.enumerated() {
            result.append(Self(sourceKind: .shot, sourceID: shot.id, fields: [
                "Order": String(index + 1), "Label": shot.label, "Scene ID": shot.sceneSpineID,
                "Shot number": String(shot.shotNumber), "Setup": shot.setup.rawValue,
                "Status": shot.status.rawValue, "Notes": shot.notes, "Source ranges": try campaignJSON(shot.sourceRefs),
                "Source range review": rangeWarnings(shot.sourceRefs).joined(separator: "\n")
            ], linkedShotIDs: [shot.id], linkedElementIDs: Array(Set(shot.sourceRefs.map(\.screenplayElementID))).sorted(by: uuidOrder)))
        }
        for (index, board) in document.boardFrames.enumerated() {
            try campaignUnique(board.imageVersions.map(\.id), "board image versions")
            result.append(Self(sourceKind: .board, sourceID: board.id, fields: [
                "Order": String(index + 1), "Label": board.label, "Scene ID": board.sceneSpineID,
                "Frame number": String(board.frameNumber), "Prompt": board.prompt,
                "Duration seconds": String(board.durationSeconds), "Status": board.status.rawValue,
                "Notes": board.notes, "Source ranges": try campaignJSON(board.sourceRefs),
                "Source range review": rangeWarnings(board.sourceRefs).joined(separator: "\n"),
                "Selected image ID": board.selectedImageID?.uuidString ?? "",
                "Selected image SHA256": board.selectedImage?.sha256 ?? "",
                "Selected image unresolved": (board.selectedImageID != nil && board.selectedImage == nil) ? "yes" : "no"
            ], linkedShotIDs: [board.shotID], linkedElementIDs: Array(Set(board.sourceRefs.map(\.screenplayElementID))).sorted(by: uuidOrder)))
        }
        try validate(result)
        return result.sorted { $0.id < $1.id }
    }

    /// Legacy ShotSourceRef offsets have no verified coordinate-unit contract. Preserve
    /// them verbatim, but do not treat an apparently bounded range as verified evidence.
    /// Current authoring uses whole-element refs (both offsets nil), which remain valid.
    private static func rangeWarnings(_ refs: [ShotSourceRef]) -> [String] {
        refs.compactMap { ref in
            if ref.startOffset == nil && ref.endOffset == nil { return nil }
            guard let start = ref.startOffset, let end = ref.endOffset,
                  start >= 0, end >= start else {
                return "Invalid source range for script element " + ref.screenplayElementID.uuidString
            }
            return "Unverified legacy source range (offset units unspecified) for script element " + ref.screenplayElementID.uuidString
        }
    }

    static func campaign(_ draft: CampaignDraft, projectID: UUID) throws -> [Self] {
        var rows = [Self(sourceKind: .brief, sourceID: projectID, fields: [
            "Brand": draft.brief.brand, "Objective": draft.brief.objective, "Audience": draft.brief.audience,
            "Key message": draft.brief.keyMessage, "Mandatory requirements": draft.brief.mandatoryRequirements
        ], linkedShotIDs: [], linkedElementIDs: [])]
        for (index, item) in draft.deliverables.enumerated() {
            rows.append(Self(sourceKind: .deliverable, sourceID: item.id, fields: [
                "Order": String(index + 1), "Name": item.name, "Duration seconds": String(item.durationSeconds),
                "Aspect ratio": item.aspectRatio, "Market": item.market, "Language": item.language,
                "Linked shots": item.linkedShotIDs.sorted(by: uuidOrder).map(\.uuidString).joined(separator: ", ")
            ], linkedShotIDs: item.linkedShotIDs.sorted(by: uuidOrder), linkedElementIDs: []))
        }
        for (index, item) in draft.assumptions.enumerated() {
            rows.append(Self(sourceKind: .assumption, sourceID: item.id, fields: [
                "Order": String(index + 1), "Assumption": item.text, "Source label": item.sourceLabel, "Source reference": item.sourceReference
            ], linkedShotIDs: [], linkedElementIDs: []))
        }
        return rows
    }
}

public struct CampaignChange: Codable, Equatable, Identifiable {
    public let id: String
    public let sourceKind: CampaignSourceKind
    public let sourceID: UUID
    public let title: String
    public let before: String
    public let after: String
    public let affectedDeliverableIDs: [UUID]
    public let unresolved: Bool
    public var requiresHumanReview: Bool { true }

    static func compare(baseline: CampaignBaseline, draft: CampaignDraft, sources: [CampaignSourceSnapshot], projectID: UUID) throws -> [Self] {
        let old = baseline.sources + (try CampaignSourceSnapshot.campaign(baseline.draft, projectID: projectID))
        let new = sources + (try CampaignSourceSnapshot.campaign(draft, projectID: projectID))
        let oldMap = Dictionary(uniqueKeysWithValues: old.map { ($0.id, $0) })
        let newMap = Dictionary(uniqueKeysWithValues: new.map { ($0.id, $0) })
        let deliverables = baseline.draft.deliverables + draft.deliverables
        func affected(_ snapshots: [CampaignSourceSnapshot]) -> [UUID] {
            if snapshots.contains(where: { $0.sourceKind == .brief || $0.sourceKind == .assumption }) {
                return Array(Set(deliverables.map(\.id))).sorted(by: uuidOrder)
            }
            let shotIDs = Set(snapshots.flatMap(\.linkedShotIDs))
            let directIDs = Set(snapshots.filter { $0.sourceKind == .deliverable }.map(\.sourceID))
            return Array(Set(deliverables.filter { directIDs.contains($0.id) || !shotIDs.isDisjoint(with: $0.linkedShotIDs) }.map(\.id))).sorted(by: uuidOrder)
        }
        var changes: [Self] = []
        for key in Set(oldMap.keys).union(newMap.keys).sorted() {
            let previous = oldMap[key], current = newMap[key]
            // Compare encoded UTF-8 rather than Swift's canonically equivalent String equality.
            let oldBytes = try campaignJSON(previous)
            let newBytes = try campaignJSON(current)
            guard !oldBytes.utf8.elementsEqual(newBytes.utf8) else { continue }
            guard let source = current ?? previous else { continue }
            changes.append(Self(id: key, sourceKind: source.sourceKind, sourceID: source.sourceID,
                title: "\(source.sourceKind.rawValue.capitalized) \(previous == nil ? "added" : current == nil ? "removed" : "changed")",
                before: previous?.summary ?? "Not present", after: current?.summary ?? "Not present",
                affectedDeliverableIDs: affected([previous, current].compactMap { $0 }), unresolved: false))
        }
        let shotIDs = Set(sources.filter { $0.sourceKind == .shot }.map(\.sourceID))
        let elementIDs = Set(sources.filter { $0.sourceKind == .script }.map(\.sourceID))
        for source in new.sorted(by: { $0.id < $1.id }) {
            var missing = source.linkedShotIDs.filter { !shotIDs.contains($0) }.map { "Missing shot \($0.uuidString)" }
            missing += source.linkedElementIDs.filter { !elementIDs.contains($0) }.map { "Missing script element \($0.uuidString)" }
            if let ranges = source.fields["Source range review"], !ranges.isEmpty { missing.append(ranges) }
            if source.fields["Selected image unresolved"] == "yes" { missing.append("Selected board image is missing") }
            guard !missing.isEmpty else { continue }
            changes.append(Self(id: source.id + ":unresolved", sourceKind: source.sourceKind, sourceID: source.sourceID,
                title: "Unresolved source links", before: oldMap[source.id]?.summary ?? "Not present", after: missing.sorted().joined(separator: "\n"),
                affectedDeliverableIDs: affected([oldMap[source.id], source].compactMap { $0 }), unresolved: true))
        }
        return changes.sorted { $0.id < $1.id }
    }
}

private func uuidOrder(_ lhs: UUID, _ rhs: UUID) -> Bool { lhs.uuidString < rhs.uuidString }
