import Foundation

public struct OpenScreenplayDocument: Codable, Equatable {
    public var format: String
    public var formatVersion: String
    public var project: Project
    public var screenplay: Screenplay
    public var typography: DocumentTypography?
    public var titlePage: TitlePage
    public var productionContext: ProductionContext
    public var aiSettings: AISettings
    public var proposals: [AIProposal]
    public var activity: [ActivityEvent]
    public var outline: [OutlineBeat]
    public var scriptNotes: [ScriptNote]
    public var shots: [Shot]
    public var boardFrames: [BoardFrame]
    public var editorialSpine: EditorialSpine

    public init(
        format: String = "open-screenplay",
        formatVersion: String = "1.0",
        project: Project,
        screenplay: Screenplay,
        titlePage: TitlePage? = nil,
        productionContext: ProductionContext = ProductionContext(),
        aiSettings: AISettings = AISettings(),
        proposals: [AIProposal] = [],
        activity: [ActivityEvent] = [],
        outline: [OutlineBeat] = [],
        scriptNotes: [ScriptNote] = [],
        shots: [Shot] = [],
        boardFrames: [BoardFrame] = [],
        editorialSpine: EditorialSpine = EditorialSpine()
    ) {
        self.format = format
        self.formatVersion = formatVersion
        self.project = project
        self.screenplay = screenplay
        self.titlePage = titlePage ?? TitlePage(title: project.metadata.title, author: project.metadata.author)
        self.productionContext = productionContext
        self.aiSettings = aiSettings
        self.proposals = proposals
        self.activity = activity
        self.outline = outline
        self.scriptNotes = scriptNotes
        self.shots = shots
        self.boardFrames = boardFrames
        self.editorialSpine = editorialSpine
        ensureSceneSpineIDs()
        ensureEditorialSpine()
    }

    enum CodingKeys: String, CodingKey {
        case format
        case formatVersion = "format_version"
        case project
        case screenplay
        case typography
        case titlePage = "title_page"
        case productionContext = "production_context"
        case aiSettings = "ai_settings"
        case proposals
        case activity
        case outline
        case scriptNotes = "script_notes"
        case shots
        case boardFrames = "board_frames"
        case editorialSpine = "editorial_spine"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decode(String.self, forKey: .format)
        formatVersion = try container.decode(String.self, forKey: .formatVersion)
        guard format == "open-screenplay", ["1.0", "1.1", "1.2"].contains(formatVersion) else {
            throw DecodingError.dataCorruptedError(forKey: .formatVersion, in: container, debugDescription: "Unsupported legacy screenplay version")
        }
        project = try container.decode(Project.self, forKey: .project)
        typography = try container.decodeIfPresent(DocumentTypography.self, forKey: .typography)
        if let typography, typography.paper != "US_LETTER" {
            throw DecodingError.dataCorruptedError(forKey: .typography, in: container, debugDescription: "Unsupported legacy paper size")
        }
        screenplay = try container.decode(Screenplay.self, forKey: .screenplay)
        aiSettings = try container.decodeIfPresent(AISettings.self, forKey: .aiSettings) ?? AISettings()
        proposals = try container.decodeIfPresent([AIProposal].self, forKey: .proposals) ?? []
        activity = try container.decodeIfPresent([ActivityEvent].self, forKey: .activity) ?? []
        outline = try container.decodeIfPresent([OutlineBeat].self, forKey: .outline) ?? []
        scriptNotes = try container.decodeIfPresent([ScriptNote].self, forKey: .scriptNotes) ?? []
        shots = try container.decodeIfPresent([Shot].self, forKey: .shots) ?? []
        boardFrames = try container.decodeIfPresent([BoardFrame].self, forKey: .boardFrames) ?? []
        editorialSpine = try container.decodeIfPresent(EditorialSpine.self, forKey: .editorialSpine) ?? EditorialSpine()
        titlePage = try container.decodeIfPresent(TitlePage.self, forKey: .titlePage)
            ?? TitlePage(title: project.metadata.title, author: project.metadata.author)
        productionContext = try container.decodeIfPresent(ProductionContext.self, forKey: .productionContext) ?? ProductionContext()
        ensureSceneSpineIDs()
        ensureEditorialSpine()
    }

    public mutating func ensureSceneSpineIDs(prefix: String = "S") {
        let reserved = Set(
            screenplay.elements
                .filter { $0.type == .sceneHeading }
                .compactMap { element in
                    let candidate = element.spineID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    return candidate.isEmpty ? nil : candidate
                }
        )
        var used: Set<String> = []
        var nextNumber = 1

        func nextID() -> String {
            while used.contains(String(format: "\(prefix)%03d", nextNumber))
                || reserved.contains(String(format: "\(prefix)%03d", nextNumber)) {
                nextNumber += 1
            }
            let id = String(format: "\(prefix)%03d", nextNumber)
            nextNumber += 1
            used.insert(id)
            return id
        }

        for index in screenplay.elements.indices where screenplay.elements[index].type == .sceneHeading {
            let candidate = screenplay.elements[index].spineID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if candidate.isEmpty || used.contains(candidate) {
                screenplay.elements[index].spineID = nextID()
            } else {
                screenplay.elements[index].spineID = candidate
                used.insert(candidate)
            }
        }
    }

    public mutating func ensureEditorialSpine() {
        editorialSpine.ensureSceneBeats(for: screenplay.elements, preserveOrder: formatVersion == "1.2")
        editorialSpine.syncEditReferences(shots: shots, boardFrames: boardFrames)
    }
}

public struct TitlePage: Codable, Equatable {
    public var title: String
    public var subtitle: String
    public var author: String
    public var contact: String
    public var draftDate: String

    public init(
        title: String,
        subtitle: String = "",
        author: String = "",
        contact: String = "",
        draftDate: String = ""
    ) {
        self.title = title
        self.subtitle = subtitle
        self.author = author
        self.contact = contact
        self.draftDate = draftDate
    }

    enum CodingKeys: String, CodingKey {
        case title
        case subtitle
        case author
        case contact
        case draftDate = "draft_date"
    }
}

public struct Project: Codable, Equatable, Identifiable {
    public let id: UUID
    public var metadata: ProjectMetadata
    public var screenplayID: UUID

    public init(id: UUID = UUID(), metadata: ProjectMetadata, screenplayID: UUID) {
        self.id = id
        self.metadata = metadata
        self.screenplayID = screenplayID
    }

    enum CodingKeys: String, CodingKey {
        case id
        case metadata
        case screenplayID = "screenplay_id"
    }
}

public struct ProjectMetadata: Codable, Equatable {
    public var title: String
    public var author: String
    public var createdAt: Date
    public var modifiedAt: Date

    public init(title: String, author: String, createdAt: Date = Date(), modifiedAt: Date = Date()) {
        self.title = title
        self.author = author
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    enum CodingKeys: String, CodingKey {
        case title
        case author
        case createdAt = "created_at"
        case modifiedAt = "modified_at"
    }
}

public struct Screenplay: Codable, Equatable, Identifiable {
    public let id: UUID
    public var metadata: ScreenplayMetadata
    public var elements: [ScreenplayElement]
    public var revision: Int
    public var revisionSettings: RevisionSettings
    public var pageLock: ProductionPageLock?

    public init(
        id: UUID = UUID(),
        metadata: ScreenplayMetadata,
        elements: [ScreenplayElement] = [],
        revision: Int = 0,
        revisionSettings: RevisionSettings = RevisionSettings(),
        pageLock: ProductionPageLock? = nil
    ) {
        self.id = id
        self.metadata = metadata
        self.elements = elements
        self.revision = revision
        self.revisionSettings = revisionSettings
        self.pageLock = pageLock
    }

    enum CodingKeys: String, CodingKey {
        case id
        case metadata
        case elements
        case revision
        case revisionSettings = "revision_settings"
        case pageLock = "page_lock"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        metadata = try container.decode(ScreenplayMetadata.self, forKey: .metadata)
        elements = try container.decode([ScreenplayElement].self, forKey: .elements)
        revision = try container.decode(Int.self, forKey: .revision)
        revisionSettings = try container.decodeIfPresent(RevisionSettings.self, forKey: .revisionSettings) ?? RevisionSettings()
        pageLock = try container.decodeIfPresent(ProductionPageLock.self, forKey: .pageLock)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(metadata, forKey: .metadata)
        try container.encode(elements, forKey: .elements)
        try container.encode(revision, forKey: .revision)
        try container.encode(revisionSettings, forKey: .revisionSettings)
        try container.encodeIfPresent(pageLock, forKey: .pageLock)
    }
}

public struct RevisionSettings: Codable, Equatable {
    public var modeEnabled: Bool
    public var label: String
    public var color: RevisionColor

    public init(modeEnabled: Bool = false, label: String = "Blue Revision", color: RevisionColor = .blue) {
        self.modeEnabled = modeEnabled
        self.label = label
        self.color = color
    }

    enum CodingKeys: String, CodingKey {
        case modeEnabled = "mode_enabled"
        case label
        case color
    }
}

public enum RevisionColor: String, Codable, CaseIterable {
    case blue
    case pink
    case yellow
    case green
    case goldenrod
}

public struct ProductionContext: Codable, Equatable {
    public var contextEnabled: Bool
    public var entities: [ProductionEntity]
    public var notes: [ProductionNote]
    public var generatedAt: Date?

    public init(
        contextEnabled: Bool = true,
        entities: [ProductionEntity] = [],
        notes: [ProductionNote] = [],
        generatedAt: Date? = nil
    ) {
        self.contextEnabled = contextEnabled
        self.entities = entities
        self.notes = notes
        self.generatedAt = generatedAt
    }

    enum CodingKeys: String, CodingKey {
        case contextEnabled = "context_enabled"
        case entities
        case notes
        case generatedAt = "generated_at"
    }
}

public struct ProductionEntity: Codable, Equatable, Identifiable {
    public let id: UUID
    public var kind: ProductionEntityKind
    public var name: String
    public var status: ProductionEntityStatus
    public var sourceElementIDs: [UUID]
    public var notes: String

    public init(
        id: UUID = UUID(),
        kind: ProductionEntityKind,
        name: String,
        status: ProductionEntityStatus = .suggested,
        sourceElementIDs: [UUID] = [],
        notes: String = ""
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.status = status
        self.sourceElementIDs = sourceElementIDs
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case name
        case status
        case sourceElementIDs = "source_element_ids"
        case notes
    }
}

public enum ProductionEntityKind: String, Codable, CaseIterable {
    case character
    case location
    case prop
    case wardrobe
    case visualEffect = "visual_effect"
    case question
}

public enum ProductionEntityStatus: String, Codable, CaseIterable {
    case suggested
    case accepted
    case ignored
}

public struct AISettings: Codable, Equatable {
    public var writingEnabled: Bool
    public var outlineEnabled: Bool
    public var directingEnabled: Bool
    public var boardsEnabled: Bool
    public var productionEnabled: Bool
    public var editEnabled: Bool

    public init(
        writingEnabled: Bool = false,
        outlineEnabled: Bool = false,
        directingEnabled: Bool = false,
        boardsEnabled: Bool = false,
        productionEnabled: Bool = false,
        editEnabled: Bool = false
    ) {
        self.writingEnabled = writingEnabled
        self.outlineEnabled = outlineEnabled
        self.directingEnabled = directingEnabled
        self.boardsEnabled = boardsEnabled
        self.productionEnabled = productionEnabled
        self.editEnabled = editEnabled
    }

    enum CodingKeys: String, CodingKey {
        case writingEnabled = "writing_enabled"
        case outlineEnabled = "outline_enabled"
        case directingEnabled = "directing_enabled"
        case boardsEnabled = "boards_enabled"
        case productionEnabled = "production_enabled"
        case editEnabled = "edit_enabled"
        case legacyPostEnabled = "post_enabled"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        writingEnabled = try container.decodeIfPresent(Bool.self, forKey: .writingEnabled) ?? false
        outlineEnabled = try container.decodeIfPresent(Bool.self, forKey: .outlineEnabled) ?? false
        directingEnabled = try container.decodeIfPresent(Bool.self, forKey: .directingEnabled) ?? false
        boardsEnabled = try container.decodeIfPresent(Bool.self, forKey: .boardsEnabled) ?? false
        productionEnabled = try container.decodeIfPresent(Bool.self, forKey: .productionEnabled) ?? false
        editEnabled = try container.decodeIfPresent(Bool.self, forKey: .editEnabled)
            ?? container.decodeIfPresent(Bool.self, forKey: .legacyPostEnabled)
            ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(writingEnabled, forKey: .writingEnabled)
        try container.encode(outlineEnabled, forKey: .outlineEnabled)
        try container.encode(directingEnabled, forKey: .directingEnabled)
        try container.encode(boardsEnabled, forKey: .boardsEnabled)
        try container.encode(productionEnabled, forKey: .productionEnabled)
        try container.encode(editEnabled, forKey: .editEnabled)
    }
}

public struct AIProposal: Codable, Equatable, Identifiable {
    public let id: UUID
    public var workflow: AIProposalWorkflow
    public var title: String
    public var body: String
    public var status: AIProposalStatus
    public var target: AIProposalTarget
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        workflow: AIProposalWorkflow,
        title: String,
        body: String,
        status: AIProposalStatus = .suggested,
        target: AIProposalTarget,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.workflow = workflow
        self.title = title
        self.body = body
        self.status = status
        self.target = target
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case workflow
        case title
        case body
        case status
        case target
        case createdAt = "created_at"
    }
}

public enum AIProposalWorkflow: String, Codable, CaseIterable {
    case writing
    case outline
    case directing
    case boards
    case production
    case edit

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "post":
            self = .edit
        default:
            guard let workflow = AIProposalWorkflow(rawValue: value) else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unknown AI proposal workflow: \(value)")
                )
            }
            self = workflow
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum AIProposalStatus: String, Codable, CaseIterable {
    case suggested
    case accepted
    case rejected
    case applied
}

public struct AIProposalTarget: Codable, Equatable {
    public var screenplayElementID: UUID?
    public var sceneSpineID: String?
    public var outlineBeatID: UUID?
    public var shotID: UUID?
    public var boardFrameID: UUID?
    public var contextRecordID: UUID?

    public init(
        screenplayElementID: UUID? = nil,
        sceneSpineID: String? = nil,
        outlineBeatID: UUID? = nil,
        shotID: UUID? = nil,
        boardFrameID: UUID? = nil,
        contextRecordID: UUID? = nil
    ) {
        self.screenplayElementID = screenplayElementID
        self.sceneSpineID = sceneSpineID
        self.outlineBeatID = outlineBeatID
        self.shotID = shotID
        self.boardFrameID = boardFrameID
        self.contextRecordID = contextRecordID
    }

    enum CodingKeys: String, CodingKey {
        case screenplayElementID = "screenplay_element_id"
        case sceneSpineID = "scene_spine_id"
        case outlineBeatID = "outline_beat_id"
        case shotID = "shot_id"
        case boardFrameID = "board_frame_id"
        case contextRecordID = "context_record_id"
    }
}

public struct ActivityEvent: Codable, Equatable, Identifiable {
    public let id: UUID
    public var actor: ActivityActor
    public var action: String
    public var detail: String
    public var target: AIProposalTarget
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        actor: ActivityActor,
        action: String,
        detail: String,
        target: AIProposalTarget = AIProposalTarget(),
        createdAt: Date = Date()
    ) {
        self.id = id
        self.actor = actor
        self.action = action
        self.detail = detail
        self.target = target
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case actor
        case action
        case detail
        case target
        case createdAt = "created_at"
    }
}

public enum ActivityActor: String, Codable, CaseIterable {
    case manual
    case proposal
    case contextAssistant = "context_assistant"
    case system
}

public struct OutlineBeat: Codable, Equatable, Identifiable {
    public let id: UUID
    public var template: String
    public var order: Int
    public var name: String
    public var purpose: String
    public var notes: String
    public var linkedSceneSpineIDs: [String]

    public init(
        id: UUID = UUID(),
        template: String,
        order: Int,
        name: String,
        purpose: String,
        notes: String = "",
        linkedSceneSpineIDs: [String] = []
    ) {
        self.id = id
        self.template = template
        self.order = order
        self.name = name
        self.purpose = purpose
        self.notes = notes
        self.linkedSceneSpineIDs = linkedSceneSpineIDs
    }

    enum CodingKeys: String, CodingKey {
        case id
        case template
        case order
        case name
        case purpose
        case notes
        case linkedSceneSpineIDs = "linked_scene_spine_ids"
    }
}

public struct ScriptNote: Codable, Equatable, Identifiable {
    public let id: UUID
    public var screenplayElementID: UUID
    public var sceneSpineID: String
    public var body: String
    public var status: ScriptNoteStatus
    public var createdAt: Date
    public var resolvedAt: Date?

    public init(
        id: UUID = UUID(),
        screenplayElementID: UUID,
        sceneSpineID: String,
        body: String,
        status: ScriptNoteStatus = .open,
        createdAt: Date = Date(),
        resolvedAt: Date? = nil
    ) {
        self.id = id
        self.screenplayElementID = screenplayElementID
        self.sceneSpineID = sceneSpineID
        self.body = body
        self.status = status
        self.createdAt = createdAt
        self.resolvedAt = resolvedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case screenplayElementID = "screenplay_element_id"
        case sceneSpineID = "scene_spine_id"
        case body
        case status
        case createdAt = "created_at"
        case resolvedAt = "resolved_at"
    }
}

public enum ScriptNoteStatus: String, Codable, CaseIterable {
    case open
    case resolved
}

public struct ProductionNote: Codable, Equatable, Identifiable {
    public let id: UUID
    public var title: String
    public var body: String
    public var status: ProductionEntityStatus
    public var sourceElementIDs: [UUID]

    public init(
        id: UUID = UUID(),
        title: String,
        body: String,
        status: ProductionEntityStatus = .suggested,
        sourceElementIDs: [UUID] = []
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.status = status
        self.sourceElementIDs = sourceElementIDs
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case body
        case status
        case sourceElementIDs = "source_element_ids"
    }
}

public struct ScreenplayMetadata: Codable, Equatable {
    public var title: String
    public var episodeTitle: String?

    public init(title: String, episodeTitle: String? = nil) {
        self.title = title
        self.episodeTitle = episodeTitle
    }

    enum CodingKeys: String, CodingKey {
        case title
        case episodeTitle = "episode_title"
    }
}

public struct ScreenplayElement: Codable, Equatable, Identifiable {
    public let id: UUID
    public var type: ElementType
    public var text: String {
        didSet {
            guard let runs, !oldValue.unicodeScalars.elementsEqual(text.unicodeScalars) else { return }
            self.runs = try? StyledText(text: oldValue, runs: runs).replacingText(text).runs
        }
    }
    public private(set) var runs: [StyledText.Run]?
    public var styledText: StyledText { try! StyledText(text: text, runs: runs ?? []) }
    public mutating func setStyledText(_ value: StyledText) {
        text = value.text
        runs = value.runs.isEmpty ? nil : value.runs
    }

    public var spineID: String?
    public var externalIDs: [String: String]
    public var revisionMark: RevisionMark?

    public init(
        id: UUID = UUID(),
        type: ElementType,
        text: String,
        spineID: String? = nil,
        externalIDs: [String: String] = [:],
        revisionMark: RevisionMark? = nil
    ) {
        self.id = id
        self.type = type
        self.text = text
        self.spineID = spineID
        self.externalIDs = externalIDs
        self.revisionMark = revisionMark
    }

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case text
        case runs
        case spineID = "spine_id"
        case externalIDs = "external_ids"
        case revisionMark = "revision_mark"
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        type = try c.decode(ElementType.self, forKey: .type)
        text = try c.decode(String.self, forKey: .text)
        runs = try c.decodeIfPresent([StyledText.Run].self, forKey: .runs)
        _ = try StyledText(text: text, runs: runs ?? [])
        spineID = try c.decodeIfPresent(String.self, forKey: .spineID)
        externalIDs = try c.decode([String: String].self, forKey: .externalIDs)
        revisionMark = try c.decodeIfPresent(RevisionMark.self, forKey: .revisionMark)
    }

}

public struct RevisionMark: Codable, Equatable {
    public var label: String
    public var color: RevisionColor
    public var changedAt: Date

    public init(label: String, color: RevisionColor, changedAt: Date = Date()) {
        self.label = label
        self.color = color
        self.changedAt = changedAt
    }

    enum CodingKeys: String, CodingKey {
        case label
        case color
        case changedAt = "changed_at"
    }
}

public enum ElementType: String, Codable, CaseIterable {
    case sceneHeading = "scene_heading"
    case action
    case character
    case dialogue
    case parenthetical
    case transition
    case general
    case shot
    case pageBreak = "page_break"
}

public struct Shot: Codable, Equatable, Identifiable {
    public let id: UUID
    public var sceneSpineID: String
    public var shotNumber: Int
    public var label: String
    public var setup: ShotSetup
    public var status: ShotStatus
    public var sourceRefs: [ShotSourceRef]
    public var notes: String

    public init(
        id: UUID = UUID(),
        sceneSpineID: String = "",
        shotNumber: Int = 0,
        label: String,
        setup: ShotSetup = .coverage,
        status: ShotStatus = .suggested,
        sourceRefs: [ShotSourceRef] = [],
        notes: String = ""
    ) {
        self.id = id
        self.sceneSpineID = sceneSpineID
        self.shotNumber = shotNumber
        self.label = label
        self.setup = setup
        self.status = status
        self.sourceRefs = sourceRefs
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey {
        case id
        case sceneSpineID = "scene_spine_id"
        case shotNumber = "shot_number"
        case label
        case setup
        case status
        case sourceRefs = "source_refs"
        case notes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        sceneSpineID = try container.decodeIfPresent(String.self, forKey: .sceneSpineID) ?? ""
        shotNumber = try container.decodeIfPresent(Int.self, forKey: .shotNumber) ?? 0
        label = try container.decode(String.self, forKey: .label)
        setup = try container.decodeIfPresent(ShotSetup.self, forKey: .setup) ?? .coverage
        status = try container.decodeIfPresent(ShotStatus.self, forKey: .status) ?? .suggested
        sourceRefs = try container.decode([ShotSourceRef].self, forKey: .sourceRefs)
        notes = try container.decode(String.self, forKey: .notes)
    }
}

public enum ShotSetup: String, Codable, CaseIterable {
    case establishing
    case master
    case coverage
    case insert
    case visualEffect = "visual_effect"
}

public enum ShotStatus: String, Codable, CaseIterable {
    case suggested
    case selected
    case boarded
    case shot
    case omitted
}

public struct BoardFrame: Codable, Equatable, Identifiable {
    public let id: UUID
    public var shotID: UUID
    public var sceneSpineID: String
    public var frameNumber: Int
    public var label: String
    public var prompt: String
    public var durationSeconds: Double
    public var status: ShotStatus
    public var notes: String
    public var sourceRefs: [ShotSourceRef]

    public init(
        id: UUID = UUID(),
        shotID: UUID,
        sceneSpineID: String,
        frameNumber: Int,
        label: String,
        prompt: String = "",
        durationSeconds: Double = 4.0,
        status: ShotStatus = .suggested,
        notes: String = "",
        sourceRefs: [ShotSourceRef] = []
    ) {
        self.id = id
        self.shotID = shotID
        self.sceneSpineID = sceneSpineID
        self.frameNumber = frameNumber
        self.label = label
        self.prompt = prompt
        self.durationSeconds = durationSeconds
        self.status = status
        self.notes = notes
        self.sourceRefs = sourceRefs
    }

    enum CodingKeys: String, CodingKey {
        case id
        case shotID = "shot_id"
        case sceneSpineID = "scene_spine_id"
        case frameNumber = "frame_number"
        case label
        case prompt
        case durationSeconds = "duration_seconds"
        case status
        case notes
        case sourceRefs = "source_refs"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        shotID = try container.decode(UUID.self, forKey: .shotID)
        sceneSpineID = try container.decode(String.self, forKey: .sceneSpineID)
        frameNumber = try container.decode(Int.self, forKey: .frameNumber)
        label = try container.decode(String.self, forKey: .label)
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        durationSeconds = try container.decodeIfPresent(Double.self, forKey: .durationSeconds) ?? 4.0
        status = try container.decodeIfPresent(ShotStatus.self, forKey: .status) ?? .suggested
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        sourceRefs = try container.decodeIfPresent([ShotSourceRef].self, forKey: .sourceRefs) ?? []
    }
}

public struct EditorialSpine: Codable, Equatable {
    public var sequences: [EditorialSequence]

    public init(sequences: [EditorialSequence] = []) {
        self.sequences = sequences
    }

    public mutating func ensureSceneBeats(for elements: [ScreenplayElement], preserveOrder: Bool = false) {
        let scenes = elements.filter { $0.type == .sceneHeading }
        guard !scenes.isEmpty else {
            sequences = sequences.map { sequence in
                var cleaned = sequence
                cleaned.beats = []
                return cleaned
            }
            return
        }

        if sequences.isEmpty {
            sequences = [EditorialSequence(name: "Main Sequence", order: 1)]
        }

        let sceneIDs = Set(scenes.compactMap(\.spineID))
        sequences = sequences.map { sequence in
            var cleaned = sequence
            cleaned.beats = cleaned.beats.filter { sceneIDs.contains($0.sceneSpineID) }
            return cleaned
        }

        let linkedSceneIDs = Set(sequences.flatMap { sequence in
            sequence.beats.map(\.sceneSpineID)
        })
        var beatOrder = (sequences.first?.beats.map(\.order).max() ?? 0) + 1
        var newBeats: [EditorialBeat] = []

        for scene in scenes {
            guard let sceneSpineID = scene.spineID, !linkedSceneIDs.contains(sceneSpineID) else {
                continue
            }

            newBeats.append(EditorialBeat(
                order: beatOrder,
                sceneSpineID: sceneSpineID,
                title: scene.text.isEmpty ? sceneSpineID : scene.text,
                sourceElementIDs: [scene.id]
            ))
            beatOrder += 1
        }

        sequences[0].beats.append(contentsOf: newBeats)

        let sceneOrderByID = Dictionary(uniqueKeysWithValues: scenes.enumerated().compactMap { index, scene in
            scene.spineID.map { ($0, index) }
        })
        for sequenceIndex in sequences.indices {
            if preserveOrder {
                sequences[sequenceIndex].beats.sort { $0.order < $1.order }
            } else {
                sequences[sequenceIndex].beats.sort {
                    (sceneOrderByID[$0.sceneSpineID] ?? Int.max) < (sceneOrderByID[$1.sceneSpineID] ?? Int.max)
                }
            }
            for beatIndex in sequences[sequenceIndex].beats.indices {
                sequences[sequenceIndex].beats[beatIndex].order = beatIndex + 1
            }
        }
    }

    public mutating func syncEditReferences(shots: [Shot], boardFrames: [BoardFrame]) {
        let shotsByID = Dictionary(uniqueKeysWithValues: shots.map { ($0.id, $0) })

        for sequenceIndex in sequences.indices {
            var timelineCursor = 0.0

            for beatIndex in sequences[sequenceIndex].beats.indices {
                let sceneSpineID = sequences[sequenceIndex].beats[beatIndex].sceneSpineID
                let sceneShots = shots
                    .filter { $0.sceneSpineID == sceneSpineID }
                    .sorted { $0.shotNumber < $1.shotNumber }
                let sceneBoardFrames = boardFrames
                    .filter { $0.sceneSpineID == sceneSpineID }
                    .sorted { $0.frameNumber < $1.frameNumber }

                sequences[sequenceIndex].beats[beatIndex].shotIDs = sceneShots.map(\.id)
                sequences[sequenceIndex].beats[beatIndex].boardFrameIDs = sceneBoardFrames.map(\.id)
                sequences[sequenceIndex].beats[beatIndex].editClips = editClips(
                    for: sceneShots,
                    boardFrames: sceneBoardFrames,
                    shotsByID: shotsByID,
                    existingClips: sequences[sequenceIndex].beats[beatIndex].editClips,
                    startingAt: timelineCursor
                )

                timelineCursor += sequences[sequenceIndex].beats[beatIndex].editDurationSeconds
            }
        }
    }

    private func editClips(
        for shots: [Shot],
        boardFrames: [BoardFrame],
        shotsByID: [UUID: Shot],
        existingClips: [EditClip],
        startingAt timelineStart: Double
    ) -> [EditClip] {
        var cursor = timelineStart

        if !boardFrames.isEmpty {
            return boardFrames.map { frame in
                defer { cursor += max(0.5, frame.durationSeconds) }
                // This guide still derives timing from boards; rebuilding it must not
                // replace the identity of a surviving occurrence in the same beat.
                return EditClip(
                    id: existingClips.first { $0.sourceKind == .boardFrame && $0.boardFrameID == frame.id }?.id ?? UUID(),
                    sceneSpineID: frame.sceneSpineID,
                    shotID: frame.shotID,
                    boardFrameID: frame.id,
                    sourceElementIDs: frame.sourceRefs.map(\.screenplayElementID),
                    label: frame.label,
                    sourceKind: .boardFrame,
                    timelineStartSeconds: cursor,
                    timelineDurationSeconds: max(0.5, frame.durationSeconds),
                    status: frame.status == .omitted ? .omitted : .planned
                )
            }
        }

        return shots.map { shot in
            defer { cursor += 4.0 }
            return EditClip(
                id: existingClips.first { $0.sourceKind == .shotPlaceholder && $0.shotID == shot.id }?.id ?? UUID(),
                sceneSpineID: shot.sceneSpineID,
                shotID: shot.id,
                sourceElementIDs: shot.sourceRefs.map(\.screenplayElementID),
                label: shot.label,
                sourceKind: .shotPlaceholder,
                timelineStartSeconds: cursor,
                timelineDurationSeconds: 4.0,
                status: shot.status == .omitted ? .omitted : .placeholder
            )
        }
    }

    enum CodingKeys: String, CodingKey {
        case sequences
    }
}

public struct EditorialSequence: Codable, Equatable, Identifiable {
    public let id: UUID
    public var name: String
    public var order: Int
    public var beats: [EditorialBeat]

    public init(
        id: UUID = UUID(),
        name: String,
        order: Int,
        beats: [EditorialBeat] = []
    ) {
        self.id = id
        self.name = name
        self.order = order
        self.beats = beats
    }
}

public struct EditorialBeat: Codable, Equatable, Identifiable {
    public let id: UUID
    public var order: Int
    public var sceneSpineID: String
    public var title: String
    public var sourceElementIDs: [UUID]
    public var shotIDs: [UUID]
    public var boardFrameIDs: [UUID]
    public var editClips: [EditClip]
    public var editNotes: String
    public var markerCategory: EditorialMarkerCategory
    public var status: EditorialBeatStatus

    public init(
        id: UUID = UUID(),
        order: Int,
        sceneSpineID: String,
        title: String,
        sourceElementIDs: [UUID] = [],
        shotIDs: [UUID] = [],
        boardFrameIDs: [UUID] = [],
        editClips: [EditClip] = [],
        editNotes: String = "",
        markerCategory: EditorialMarkerCategory = .scene,
        status: EditorialBeatStatus = .planned
    ) {
        self.id = id
        self.order = order
        self.sceneSpineID = sceneSpineID
        self.title = title
        self.sourceElementIDs = sourceElementIDs
        self.shotIDs = shotIDs
        self.boardFrameIDs = boardFrameIDs
        self.editClips = editClips
        self.editNotes = editNotes
        self.markerCategory = markerCategory
        self.status = status
    }

    public var editDurationSeconds: Double {
        editClips.reduce(0.0) { $0 + $1.timelineDurationSeconds }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case order
        case sceneSpineID = "scene_spine_id"
        case title
        case sourceElementIDs = "source_element_ids"
        case shotIDs = "shot_ids"
        case boardFrameIDs = "board_frame_ids"
        case editClips = "edit_clips"
        case editNotes = "edit_notes"
        case markerCategory = "marker_category"
        case status
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        order = try container.decode(Int.self, forKey: .order)
        sceneSpineID = try container.decode(String.self, forKey: .sceneSpineID)
        title = try container.decode(String.self, forKey: .title)
        sourceElementIDs = try container.decodeIfPresent([UUID].self, forKey: .sourceElementIDs) ?? []
        shotIDs = try container.decodeIfPresent([UUID].self, forKey: .shotIDs) ?? []
        boardFrameIDs = try container.decodeIfPresent([UUID].self, forKey: .boardFrameIDs) ?? []
        editClips = try container.decodeIfPresent([EditClip].self, forKey: .editClips) ?? []
        editNotes = try container.decodeIfPresent(String.self, forKey: .editNotes) ?? ""
        markerCategory = try container.decodeIfPresent(EditorialMarkerCategory.self, forKey: .markerCategory) ?? .scene
        status = try container.decodeIfPresent(EditorialBeatStatus.self, forKey: .status) ?? .planned
    }
}

public struct EditClip: Codable, Equatable, Identifiable {
    public let id: UUID
    public var sceneSpineID: String
    public var shotID: UUID?
    public var boardFrameID: UUID?
    public var sourceElementIDs: [UUID]
    public var label: String
    public var sourceKind: EditClipSourceKind
    public var timelineStartSeconds: Double
    public var timelineDurationSeconds: Double
    public var sourceStartSeconds: Double
    public var status: EditClipStatus
    public var notes: String

    public init(
        id: UUID = UUID(),
        sceneSpineID: String,
        shotID: UUID? = nil,
        boardFrameID: UUID? = nil,
        sourceElementIDs: [UUID] = [],
        label: String,
        sourceKind: EditClipSourceKind,
        timelineStartSeconds: Double,
        timelineDurationSeconds: Double,
        sourceStartSeconds: Double = 0,
        status: EditClipStatus = .planned,
        notes: String = ""
    ) {
        self.id = id
        self.sceneSpineID = sceneSpineID
        self.shotID = shotID
        self.boardFrameID = boardFrameID
        self.sourceElementIDs = sourceElementIDs
        self.label = label
        self.sourceKind = sourceKind
        self.timelineStartSeconds = timelineStartSeconds
        self.timelineDurationSeconds = timelineDurationSeconds
        self.sourceStartSeconds = sourceStartSeconds
        self.status = status
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey {
        case id
        case sceneSpineID = "scene_spine_id"
        case shotID = "shot_id"
        case boardFrameID = "board_frame_id"
        case sourceElementIDs = "source_element_ids"
        case label
        case sourceKind = "source_kind"
        case timelineStartSeconds = "timeline_start_seconds"
        case timelineDurationSeconds = "timeline_duration_seconds"
        case sourceStartSeconds = "source_start_seconds"
        case status
        case notes
    }
}

public enum EditClipSourceKind: String, Codable, CaseIterable {
    case shotPlaceholder = "shot_placeholder"
    case boardFrame = "board_frame"
    case productionMedia = "production_media"
    case generatedVideo = "generated_video"
}

public enum EditClipStatus: String, Codable, CaseIterable {
    case placeholder
    case planned
    case assembled
    case replaced
    case locked
    case omitted
}

public enum EditorialMarkerCategory: String, Codable, CaseIterable {
    case scene
    case story
    case shot
    case continuity
    case pickup
    case visualEffect = "visual_effect"
}

public enum EditorialBeatStatus: String, Codable, CaseIterable {
    case planned
    case readyForEdit = "ready_for_edit"
    case inEdit = "in_edit"
    case locked
    case shot
    case selected
    case needsPickup = "needs_pickup"
    case cut
}

public struct ShotSourceRef: Codable, Equatable {
    public var screenplayElementID: UUID
    public var startOffset: Int?
    public var endOffset: Int?

    public init(screenplayElementID: UUID, startOffset: Int? = nil, endOffset: Int? = nil) {
        self.screenplayElementID = screenplayElementID
        self.startOffset = startOffset
        self.endOffset = endOffset
    }

    enum CodingKeys: String, CodingKey {
        case screenplayElementID = "screenplay_element_id"
        case startOffset = "start_offset"
        case endOffset = "end_offset"
    }
}

public extension JSONEncoder {
    static func openScreenplayEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

public extension JSONDecoder {
    static func openScreenplayDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}


/// Frozen print boundaries, expressed as Character offsets in the normalized source text.
/// Keeping the baseline lets boundaries follow edits, splits, merges, and deleted paragraphs.
public struct ProductionPageLock: Codable, Equatable {
    public var text: String
    public var pageStarts: [Int]
    /// Optional for compatibility with locks saved before paragraph identities were recorded.
    public var elements: [ProductionLockElement]?
    public init(text: String, pageStarts: [Int], elements: [ProductionLockElement]? = nil) {
        self.text = text
        self.pageStarts = pageStarts
        self.elements = elements
    }
}

public struct ProductionLockElement: Codable, Equatable {
    public var id: UUID
    public var text: String
    public init(id: UUID, text: String) {
        self.id = id
        self.text = text
    }
}
