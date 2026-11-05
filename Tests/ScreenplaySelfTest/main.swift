import Foundation
import ScreenplayDomain
import ScreenplayFDX

enum SelfTestError: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message):
            return message
        }
    }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw SelfTestError.failed(message)
    }
}

func testScreenplayOSDocumentEncodesStableTopLevelContract() throws {
    let screenplay = Screenplay(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        metadata: ScreenplayMetadata(title: "The Paper Bridge"),
        elements: [
            ScreenplayElement(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                type: .sceneHeading,
                text: "INT. MODEL WORKSHOP - DAY",
                spineID: "S001",
                externalIDs: ["fdx_paragraph_id": "source-1"],
                revisionMark: RevisionMark(
                    label: "Blue Revision",
                    color: .blue,
                    changedAt: Date(timeIntervalSince1970: 0)
                )
            )
        ],
        revisionSettings: RevisionSettings(modeEnabled: true, label: "Blue Revision", color: .blue)
    )
    let project = Project(
        id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
        metadata: ProjectMetadata(
            title: "The Paper Bridge",
            author: "Synthetic Test Writer",
            createdAt: Date(timeIntervalSince1970: 0),
            modifiedAt: Date(timeIntervalSince1970: 0)
        ),
        screenplayID: screenplay.id
    )
    let shot = Shot(
        id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
        sceneSpineID: "S001",
        shotNumber: 1,
        label: "S001-SH001 Inspect the model",
        setup: .establishing,
        status: .suggested,
        sourceRefs: [ShotSourceRef(screenplayElementID: screenplay.elements[0].id)],
        notes: "Opening geography."
    )
    let frame = BoardFrame(
        id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
        shotID: shot.id,
        sceneSpineID: "S001",
        frameNumber: 1,
        label: "S001-SH001 Inspect the model",
        prompt: "Tabletop tram beside a folded map.",
        durationSeconds: 4.5,
        status: .suggested,
        notes: "Use as the first board frame.",
        sourceRefs: shot.sourceRefs
    )
    let outline = OutlineBeat(
        id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
        template: "Hero's Journey",
        order: 1,
        name: "Ordinary World",
        purpose: "Show the hero's normal life.",
        notes: "Begin with a route card beside the model tram.",
        linkedSceneSpineIDs: ["S001"]
    )
    let proposal = AIProposal(
        id: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!,
        workflow: .writing,
        title: "Review opening",
        body: "Check the first image.",
        status: .suggested,
        target: AIProposalTarget(screenplayElementID: screenplay.elements[0].id, sceneSpineID: "S001", outlineBeatID: outline.id),
        createdAt: Date(timeIntervalSince1970: 0)
    )
    let aiSettings = AISettings(
        writingEnabled: true,
        outlineEnabled: true,
        directingEnabled: false,
        boardsEnabled: true,
        productionEnabled: true,
        editEnabled: true
    )
    let activity = ActivityEvent(
        id: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
        actor: .proposal,
        action: "Applied proposal",
        detail: "Review opening",
        target: proposal.target,
        createdAt: Date(timeIntervalSince1970: 0)
    )
    let scriptNote = ScriptNote(
        id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
        screenplayElementID: screenplay.elements[0].id,
        sceneSpineID: "S001",
        body: "Check visual continuity.",
        createdAt: Date(timeIntervalSince1970: 0)
    )
    let document = ScreenplayOSDocument(
        project: project,
        screenplay: screenplay,
        productionContext: ProductionContext(),
        aiSettings: aiSettings,
        proposals: [proposal],
        activity: [activity],
        outline: [outline],
        scriptNotes: [scriptNote],
        shots: [shot],
        boardFrames: [frame]
    )

    let data = try JSONEncoder.screenplayOSEncoder().encode(document)
    let json = String(decoding: data, as: UTF8.self)

    try expect(json.contains("\"format\" : \"screenplayos\""), "Missing ScreenplayOS format marker.")
    try expect(json.contains("\"format_version\" : \"1.0\""), "Missing format version.")
    try expect(json.contains("\"scene_heading\""), "Missing scene heading element type.")
    try expect(json.contains("\"spine_id\" : \"S001\""), "Missing persistent scene spine ID.")
    try expect(json.contains("\"screenplay_id\""), "Missing screenplay_id coding key.")
    try expect(json.contains("\"title_page\""), "Missing title page contract.")
    try expect(json.contains("\"author\" : \"Synthetic Test Writer\""), "Missing title page author.")
    try expect(json.contains("\"revision_settings\""), "Missing revision settings contract.")
    try expect(json.contains("\"revision_mark\""), "Missing revision mark contract.")
    try expect(json.contains("\"mode_enabled\" : true"), "Missing revision mode state.")
    try expect(json.contains("\"production_context\""), "Missing production context contract.")
    try expect(json.contains("\"ai_settings\""), "Missing AI settings contract.")
    try expect(json.contains("\"writing_enabled\" : true"), "Missing Writing AI toggle.")
    try expect(json.contains("\"outline_enabled\" : true"), "Missing Outline AI toggle.")
    try expect(json.contains("\"directing_enabled\" : false"), "Missing Directing AI toggle.")
    try expect(json.contains("\"boards_enabled\" : true"), "Missing Boards AI toggle.")
    try expect(json.contains("\"production_enabled\" : true"), "Missing Production AI toggle.")
    try expect(json.contains("\"edit_enabled\" : true"), "Missing Edit AI toggle.")
    try expect(json.contains("\"proposals\""), "Missing proposal queue.")
    try expect(json.contains("\"workflow\" : \"writing\""), "Missing proposal workflow.")
    try expect(json.contains("\"target\""), "Missing proposal target.")
    try expect(json.contains("\"outline_beat_id\""), "Missing proposal outline beat target.")
    try expect(json.contains("\"activity\""), "Missing activity log.")
    try expect(json.contains("\"actor\" : \"proposal\""), "Missing activity actor.")
    try expect(json.contains("\"outline\""), "Missing outline contract.")
    try expect(json.contains("\"template\" : \"Hero's Journey\""), "Missing outline template.")
    try expect(json.contains("\"linked_scene_spine_ids\""), "Missing outline scene links.")
    try expect(json.contains("\"script_notes\""), "Missing script notes contract.")
    try expect(json.contains("\"screenplay_element_id\""), "Missing script note element link.")
    try expect(json.contains("\"body\" : \"Check visual continuity.\""), "Missing script note body.")
    try expect(json.contains("\"scene_spine_id\""), "Missing shot scene spine contract.")
    try expect(json.contains("\"shot_number\""), "Missing shot number contract.")
    try expect(json.contains("\"setup\" : \"establishing\""), "Missing shot setup contract.")
    try expect(json.contains("\"status\" : \"suggested\""), "Missing shot status contract.")
    try expect(json.contains("\"board_frames\""), "Missing board frame contract.")
    try expect(json.contains("\"shot_id\""), "Missing board frame shot link.")
    try expect(json.contains("\"frame_number\""), "Missing board frame number.")
    try expect(json.contains("\"prompt\" : \"Tabletop tram beside a folded map.\""), "Missing board prompt.")
    try expect(json.contains("\"duration_seconds\" : 4.5"), "Missing board duration.")
    try expect(json.contains("\"editorial_spine\""), "Missing editorial spine contract.")
    try expect(json.contains("\"sequences\""), "Missing editorial sequence contract.")
    try expect(json.contains("\"marker_category\" : \"scene\""), "Missing editorial marker category.")
    try expect(json.contains("\"status\" : \"planned\""), "Missing editorial planned status.")
    try expect(EditorialBeatStatus.readyForEdit.rawValue == "ready_for_edit", "Missing edit ready-for-edit status.")
    try expect(EditorialBeatStatus.inEdit.rawValue == "in_edit", "Missing edit in-edit status.")
    try expect(EditorialBeatStatus.locked.rawValue == "locked", "Missing edit locked status.")
}

func testProductionContextEncodesReviewableEntities() throws {
    let screenplay = Screenplay(metadata: ScreenplayMetadata(title: "Context Test"))
    let project = Project(
        metadata: ProjectMetadata(
            title: "Context Test",
            author: "",
            createdAt: Date(timeIntervalSince1970: 0),
            modifiedAt: Date(timeIntervalSince1970: 0)
        ),
        screenplayID: screenplay.id
    )
    let entity = ProductionEntity(
        id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
        kind: .location,
        name: "MODEL WORKSHOP",
        status: .suggested,
        sourceElementIDs: [UUID(uuidString: "55555555-5555-5555-5555-555555555555")!]
    )
    let context = ProductionContext(contextEnabled: true, entities: [entity])
    let document = ScreenplayOSDocument(project: project, screenplay: screenplay, productionContext: context)

    let data = try JSONEncoder.screenplayOSEncoder().encode(document)
    let decoded = try JSONDecoder.screenplayOSDecoder().decode(ScreenplayOSDocument.self, from: data)

    try expect(decoded.productionContext.contextEnabled, "Production context enabled state was not preserved.")
    try expect(decoded.productionContext.entities.first?.kind == .location, "Production entity kind was not preserved.")
    try expect(decoded.productionContext.entities.first?.status == .suggested, "Production entity review status was not preserved.")
}

func testAISettingsDecodeOlderThreeModeFiles() throws {
    let json = """
    {
      "writing_enabled": true,
      "directing_enabled": false,
      "production_enabled": true
    }
    """

    let settings = try JSONDecoder.screenplayOSDecoder().decode(AISettings.self, from: Data(json.utf8))

    try expect(settings.writingEnabled, "Older Writing AI setting was not preserved.")
    try expect(settings.outlineEnabled == false, "Older files should default Outline AI off.")
    try expect(settings.directingEnabled == false, "Older Directing AI setting was not preserved.")
    try expect(settings.boardsEnabled == false, "Older files should default Boards AI off.")
    try expect(settings.productionEnabled, "Older Production AI setting was not preserved.")
    try expect(settings.editEnabled == false, "Older files should default Edit AI off.")
}

func testAISettingsDecodeLegacyPostModeFiles() throws {
    let json = """
    {
      "writing_enabled": false,
      "directing_enabled": false,
      "production_enabled": false,
      "post_enabled": true
    }
    """

    let settings = try JSONDecoder.screenplayOSDecoder().decode(AISettings.self, from: Data(json.utf8))

    try expect(settings.editEnabled, "Legacy Post AI setting should migrate to Edit AI.")
}

func testSceneSpineIDsAreAssignedAndStable() throws {
    let screenplay = Screenplay(
        metadata: ScreenplayMetadata(title: "Scene Spine Test"),
        elements: [
            ScreenplayElement(type: .sceneHeading, text: "INT. FIRST ROOM - DAY"),
            ScreenplayElement(type: .sceneHeading, text: "EXT. SECOND STREET - NIGHT"),
            ScreenplayElement(type: .action, text: "The city waits."),
            ScreenplayElement(type: .sceneHeading, text: "INT. SAVED ROOM - DAY", spineID: "S009"),
            ScreenplayElement(type: .sceneHeading, text: "EXT. DUPLICATE STREET - NIGHT", spineID: "S009")
        ]
    )
    let project = Project(
        metadata: ProjectMetadata(
            title: "Scene Spine Test",
            author: "",
            createdAt: Date(timeIntervalSince1970: 0),
            modifiedAt: Date(timeIntervalSince1970: 0)
        ),
        screenplayID: screenplay.id
    )

    let document = ScreenplayOSDocument(project: project, screenplay: screenplay)
    let sceneIDs = document.screenplay.elements
        .filter { $0.type == .sceneHeading }
        .compactMap(\.spineID)

    try expect(sceneIDs.count == 4, "Scene headings should all receive spine IDs.")
    try expect(Set(sceneIDs).count == sceneIDs.count, "Scene spine IDs must be unique.")
    try expect(sceneIDs.contains("S001"), "Missing first assigned spine ID.")
    try expect(sceneIDs.contains("S002"), "Missing second assigned spine ID.")
    try expect(sceneIDs.contains("S009"), "Existing spine ID should be preserved.")
    try expect(document.screenplay.elements[2].spineID == nil, "Non-scene elements should not receive scene spine IDs.")
}

func testEditorialSpineSeedsFromSceneSpineIDs() throws {
    let firstSceneID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    let secondSceneID = UUID(uuidString: "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF")!
    let screenplay = Screenplay(
        metadata: ScreenplayMetadata(title: "Editorial Spine Test"),
        elements: [
            ScreenplayElement(id: firstSceneID, type: .sceneHeading, text: "INT. CONTROL ROOM - DAY", spineID: "S010"),
            ScreenplayElement(type: .action, text: "Monitors glow."),
            ScreenplayElement(id: secondSceneID, type: .sceneHeading, text: "EXT. ROOFTOP - NIGHT", spineID: "S011")
        ]
    )
    let project = Project(
        metadata: ProjectMetadata(
            title: "Editorial Spine Test",
            author: "",
            createdAt: Date(timeIntervalSince1970: 0),
            modifiedAt: Date(timeIntervalSince1970: 0)
        ),
        screenplayID: screenplay.id
    )

    let document = ScreenplayOSDocument(project: project, screenplay: screenplay)
    let sequence = try expectValue(document.editorialSpine.sequences.first, "Editorial spine did not create a sequence.")
    let beats = sequence.beats

    try expect(sequence.name == "Main Sequence", "Editorial spine should seed a main sequence.")
    try expect(beats.count == 2, "Editorial spine should seed one beat per scene.")
    try expect(beats.map(\.sceneSpineID) == ["S010", "S011"], "Editorial beats did not preserve scene spine IDs.")
    try expect(beats[0].sourceElementIDs == [firstSceneID], "Editorial beat lost the source scene element.")
    try expect(beats[0].markerCategory == .scene, "Editorial beat marker category should default to scene.")
    try expect(beats[0].status == .planned, "Editorial beat status should default to planned.")
}

func testEditorialSpinePrunesRemovedScenes() throws {
    var spine = EditorialSpine(sequences: [
        EditorialSequence(
            name: "Main Sequence",
            order: 1,
            beats: [
                EditorialBeat(order: 1, sceneSpineID: "S001", title: "INT. KEPT ROOM - DAY"),
                EditorialBeat(order: 2, sceneSpineID: "S999", title: "EXT. REMOVED STREET - NIGHT")
            ]
        )
    ])
    let elements = [
        ScreenplayElement(type: .sceneHeading, text: "INT. KEPT ROOM - DAY", spineID: "S001")
    ]

    spine.ensureSceneBeats(for: elements)
    let beats = spine.sequences.flatMap(\.beats)

    try expect(beats.count == 1, "Editorial spine should remove beats for deleted scenes.")
    try expect(beats.first?.sceneSpineID == "S001", "Editorial spine removed the wrong beat.")
}

func testEditorialSpineFollowsReorderedScriptScenes() throws {
    var spine = EditorialSpine(sequences: [
        EditorialSequence(
            name: "Main Sequence",
            order: 1,
            beats: [
                EditorialBeat(order: 1, sceneSpineID: "S001", title: "INT. FIRST ROOM - DAY"),
                EditorialBeat(order: 2, sceneSpineID: "S002", title: "EXT. SECOND STREET - NIGHT")
            ]
        )
    ])
    let reorderedElements = [
        ScreenplayElement(type: .sceneHeading, text: "EXT. SECOND STREET - NIGHT", spineID: "S002"),
        ScreenplayElement(type: .action, text: "Rain falls."),
        ScreenplayElement(type: .sceneHeading, text: "INT. FIRST ROOM - DAY", spineID: "S001")
    ]

    spine.ensureSceneBeats(for: reorderedElements)
    let beats = try expectValue(spine.sequences.first?.beats, "Editorial spine beats missing after reorder.")

    try expect(beats.map(\.sceneSpineID) == ["S002", "S001"], "Editorial spine should follow reordered script scene order.")
    try expect(beats.map(\.order) == [1, 2], "Editorial spine beat order should be normalized after reorder.")
}

func testEditorialSpineSyncsEditReferences() throws {
    let sceneID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    let shotID = UUID(uuidString: "22222222-3333-4444-5555-666666666666")!
    let boardID = UUID(uuidString: "33333333-4444-5555-6666-777777777777")!
    var spine = EditorialSpine(sequences: [
        EditorialSequence(
            name: "Main Sequence",
            order: 1,
            beats: [
                EditorialBeat(order: 1, sceneSpineID: "S001", title: "INT. MODEL WORKSHOP - DAY", sourceElementIDs: [sceneID])
            ]
        )
    ])
    let shot = Shot(id: shotID, sceneSpineID: "S001", shotNumber: 1, label: "S001-SH001")
    let boardFrame = BoardFrame(
        id: boardID,
        shotID: shotID,
        sceneSpineID: "S001",
        frameNumber: 1,
        label: "S001-SH001",
        prompt: "Wide opening frame.",
        durationSeconds: 6.5
    )

    spine.syncEditReferences(shots: [shot], boardFrames: [boardFrame])
    let beat = try expectValue(spine.sequences.first?.beats.first, "Edit beat missing after sync.")

    try expect(beat.shotIDs == [shotID], "Edit guide did not sync shot IDs.")
    try expect(beat.boardFrameIDs == [boardID], "Edit guide did not sync board frame IDs.")
    try expect(beat.editClips.count == 1, "Edit guide did not create a clip from the board frame.")
    let clip = try expectValue(beat.editClips.first, "Edit clip missing after sync.")
    try expect(clip.shotID == shotID, "Edit clip lost shot ID.")
    try expect(clip.boardFrameID == boardID, "Edit clip lost board frame ID.")
    try expect(clip.sourceKind == .boardFrame, "Edit clip should use board frame source kind.")
    try expect(clip.timelineStartSeconds == 0, "First edit clip should begin at zero.")
    try expect(clip.timelineDurationSeconds == 6.5, "Edit clip did not inherit board duration.")
    try expect(beat.editDurationSeconds == 6.5, "Edit beat duration should follow its clips.")
}

func testEditorialSpineCreatesShotPlaceholdersBeforeBoards() throws {
    let sceneID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    let shotID = UUID(uuidString: "22222222-3333-4444-5555-666666666666")!
    var spine = EditorialSpine(sequences: [
        EditorialSequence(
            name: "Main Sequence",
            order: 1,
            beats: [
                EditorialBeat(order: 1, sceneSpineID: "S001", title: "INT. MODEL WORKSHOP - DAY", sourceElementIDs: [sceneID])
            ]
        )
    ])
    let shot = Shot(id: shotID, sceneSpineID: "S001", shotNumber: 1, label: "S001-SH001")

    spine.syncEditReferences(shots: [shot], boardFrames: [])
    let clip = try expectValue(spine.sequences.first?.beats.first?.editClips.first, "Shot placeholder edit clip missing.")

    try expect(clip.sourceKind == .shotPlaceholder, "Edit clip should fall back to a shot placeholder before boards exist.")
    try expect(clip.timelineDurationSeconds == 4.0, "Shot placeholder should get a default editable duration.")
}

func expectValue<T>(_ value: T?, _ message: String) throws -> T {
    guard let value else {
        throw SelfTestError.failed(message)
    }
    return value
}

func testShotCanReferenceScreenplayElement() throws {
    let elementID = UUID()
    let shot = Shot(
        sceneSpineID: "S004",
        shotNumber: 1,
        label: "4.1 INSERT - ROUTE CARD",
        setup: .establishing,
        status: .selected,
        sourceRefs: [
            ShotSourceRef(screenplayElementID: elementID, startOffset: 0, endOffset: 42)
        ],
        notes: "Manual shot list support belongs in the free document layer."
    )

    try expect(shot.sourceRefs.first?.screenplayElementID == elementID, "Shot source ref lost element ID.")
    try expect(shot.sourceRefs.first?.startOffset == 0, "Shot source ref lost start offset.")
    try expect(shot.sourceRefs.first?.endOffset == 42, "Shot source ref lost end offset.")
    try expect(shot.sceneSpineID == "S004", "Shot lost scene spine ID.")
    try expect(shot.shotNumber == 1, "Shot lost shot number.")
    try expect(shot.setup == .establishing, "Shot lost setup.")
    try expect(shot.status == .selected, "Shot lost status.")
}

func testImportsMinimalFDXParagraphs() throws {
    let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <FinalDraft>
      <Content>
        <Paragraph Type="Scene Heading" id="scene-1"><Text>INT. MODEL WORKSHOP - DAY</Text></Paragraph>
        <Paragraph Type="Action" id="action-1"><Text>A receipt printer feeds a blank ticket.</Text></Paragraph>
        <Paragraph Type="Character" id="character-1"><Text>MARA</Text></Paragraph>
        <Paragraph Type="Dialogue" id="dialogue-1"><Text>The next route is ready.</Text></Paragraph>
      </Content>
    </FinalDraft>
    """

    let result = try FDXImporter().importData(Data(xml.utf8), title: "Fixture")
    let elements = result.document.screenplay.elements

    try expect(elements.map(\.type) == [.sceneHeading, .action, .character, .dialogue], "FDX paragraph types mapped incorrectly.")
    try expect(elements.first?.text == "INT. MODEL WORKSHOP - DAY", "First imported paragraph text was incorrect.")
    try expect(elements.first?.externalIDs["fdx_paragraph_id"] == "scene-1", "FDX paragraph ID was not preserved.")
    try expect(result.document.titlePage.title == "Fixture", "FDX import did not seed title page.")
}

func testImportsExplicitFDXPageBreaks() throws {
    let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <FinalDraft>
      <Content>
        <Paragraph Type="Action" id="action-1"><Text>Before the break.</Text></Paragraph>
        <Paragraph Type="Page Break" id="page-break-1"/>
        <Paragraph Type="Action" id="action-2"><Text>After the break.</Text></Paragraph>
      </Content>
    </FinalDraft>
    """

    let elements = try FDXImporter().importData(Data(xml.utf8), title: "Page Break Fixture").document.screenplay.elements

    try expect(elements.map(\.type) == [.action, .pageBreak, .action], "FDX page break was not preserved.")
    try expect(elements[1].externalIDs["fdx_paragraph_id"] == "page-break-1", "FDX page break ID was not preserved.")
}

// Original synthetic data. Page counts are defined by short scene blocks and
// explicit breaks, not by comparison with any production screenplay.
func testImportsSyntheticFixture() throws {
    let fixture = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Tests/Fixtures/Synthetic_Final_Draft.fdx")

    let result = try FDXImporter().importFile(at: fixture)
    let elements = result.document.screenplay.elements
    let scenes = elements.filter { $0.type == .sceneHeading }
    let characters = Set(elements.filter { $0.type == .character }.map { $0.text })
    let sceneIDs = scenes.compactMap(\.spineID)
    let editorialBeats = result.document.editorialSpine.sequences.flatMap(\.beats)

    try expect(elements.count == 193, "Synthetic import element count changed.")
    try expect(scenes.count == 12, "Synthetic import scene count changed.")
    try expect(elements.filter { $0.type == .pageBreak }.count == 11, "Authored page boundaries were lost.")
    try expect(sceneIDs == (1...12).map { String(format: "S%03d", $0) }, "Synthetic scene spine IDs changed.")
    try expect(editorialBeats.map(\.sceneSpineID) == sceneIDs, "Editorial spine did not seed every scene in order.")
    try expect(characters == Set(["MARA", "IVO", "UMA"]), "Synthetic character index changed.")
    try expect(elements.first?.text == "THE PAPER BRIDGE", "First synthetic element text changed.")
    try expect(scenes[1].text == "INT. SORTING ROOM - DAY", "Nested FDX metadata changed a scene heading.")
    try expect(!elements.contains { $0.text.contains("METADATA ONLY") }, "Nested metadata became screenplay text.")
    try expect(Set(elements.map { $0.type.rawValue }) == Set(ElementType.allCases.map(\.rawValue)), "Synthetic fixture lost an element type.")
    let paragraphIDs = elements.compactMap { $0.externalIDs["fdx_paragraph_id"] }
    try expect(paragraphIDs.count == elements.count && Set(paragraphIDs).count == elements.count, "FDX paragraph IDs are missing or duplicated.")
    try expect(elements.contains { $0.text.unicodeScalars.contains(where: { $0.value == 0x0301 }) }, "Combining Unicode scalar was lost.")
    try expect(elements.contains { $0.text.contains("🚀") }, "Non-BMP Unicode text was lost.")
    let styles = elements.flatMap { ($0.runs ?? []).map(\.style) }
    try expect(styles.contains { $0.bold == true }, "Bold fixture style was lost.")
    try expect(styles.contains { $0.italic == true }, "Italic fixture style was lost.")
    try expect(styles.contains { $0.underline == true }, "Underline fixture style was lost.")
    try expect(styles.contains { $0.strikethrough == true }, "Strikeout fixture style was lost.")
    try expect(result.document.formatVersion == "1.1", "Styled import did not select format 1.1.")
    try expect(result.document.titlePage.title == "The Paper Bridge", "Separate FDX title page was lost.")
}

func testSyntheticJSONMatchesFDXAndPreservesProductionLinks() throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Tests/Fixtures")
    let data = try Data(contentsOf: root.appendingPathComponent("Synthetic.open-screenplay.json"))
    let document = try JSONDecoder.screenplayOSDecoder().decode(ScreenplayOSDocument.self, from: data)
    let imported = try FDXImporter().importFile(at: root.appendingPathComponent("Synthetic_Final_Draft.fdx")).document
    let elements = document.screenplay.elements

    try expect(document.format == "screenplayos", "Legacy fixture format was not migrated.")
    try expect(document.project.screenplayID == document.screenplay.id, "Fixture project references the wrong screenplay.")
    try expect(elements.map(\.type) == imported.screenplay.elements.map(\.type), "JSON and FDX element types differ.")
    try expect(elements.map(\.styledText) == imported.screenplay.elements.map(\.styledText), "JSON and FDX text or styles differ.")
    try expect(elements.map(\.externalIDs) == imported.screenplay.elements.map(\.externalIDs), "JSON and FDX paragraph links differ.")
    try expect(LegacyRoundTrip.droppedPaths(original: data, document: document).isEmpty, "Synthetic JSON loses fields when saved.")
    let elementIDs = Set(elements.map(\.id))
    let sceneIDs = Set(elements.compactMap(\.spineID))
    try expect(elementIDs.count == elements.count, "Fixture element IDs are duplicated.")
    try expect(document.productionContext.entities.count == 3, "Production entity coverage changed.")
    for entity in document.productionContext.entities {
        try expect(entity.sourceElementIDs.allSatisfy { elementIDs.contains($0) }, "Production entity has a dangling source reference.")
    }
    try expect(document.shots.count == 2 && document.boardFrames.count == 2, "Fixture shot and board coverage changed.")
    for shot in document.shots {
        try expect(sceneIDs.contains(shot.sceneSpineID), "Shot has a dangling scene reference.")
        try expect(shot.sourceRefs.allSatisfy { elementIDs.contains($0.screenplayElementID) }, "Shot has a dangling element reference.")
    }
    let shotIDs = Set(document.shots.map(\.id))
    for board in document.boardFrames {
        try expect(shotIDs.contains(board.shotID) && sceneIDs.contains(board.sceneSpineID), "Board has a dangling shot or scene reference.")
    }
    for beat in document.outline {
        try expect(beat.linkedSceneSpineIDs.allSatisfy { sceneIDs.contains($0) }, "Outline has a dangling scene reference.")
    }
    try expect(document.editorialSpine.sequences.flatMap(\.beats).count == 12, "JSON fixture lost editorial beats.")
    let reopened = try JSONDecoder.screenplayOSDecoder().decode(ScreenplayOSDocument.self, from: JSONEncoder.screenplayOSEncoder().encode(document))
    try expect(reopened == document, "Synthetic fixture changed after JSON round trip.")
}

let tests: [(String, () throws -> Void)] = [
    ("ScreenplayOS JSON contract", testScreenplayOSDocumentEncodesStableTopLevelContract),
    ("Production context contract", testProductionContextEncodesReviewableEntities),
    ("AI settings backward compatibility", testAISettingsDecodeOlderThreeModeFiles),
    ("Legacy Post AI compatibility", testAISettingsDecodeLegacyPostModeFiles),
    ("Scene spine IDs", testSceneSpineIDsAreAssignedAndStable),
    ("Editorial spine", testEditorialSpineSeedsFromSceneSpineIDs),
    ("Editorial spine pruning", testEditorialSpinePrunesRemovedScenes),
    ("Editorial spine scene reorder", testEditorialSpineFollowsReorderedScriptScenes),
    ("Editorial spine edit references", testEditorialSpineSyncsEditReferences),
    ("Editorial spine shot placeholders", testEditorialSpineCreatesShotPlaceholdersBeforeBoards),
    ("Shot source references", testShotCanReferenceScreenplayElement),
    ("Minimal FDX import", testImportsMinimalFDXParagraphs),
    ("Explicit FDX page breaks", testImportsExplicitFDXPageBreaks),
    ("Synthetic fixture import", testImportsSyntheticFixture),
    ("Synthetic fixture JSON and production links", testSyntheticJSONMatchesFDXAndPreservesProductionLinks)
]

do {
    for (name, test) in tests {
        try test()
        print("PASS: \(name)")
    }
    print("\(tests.count) tests passed, 0 failures")
} catch {
    FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8))
    exit(1)
}
