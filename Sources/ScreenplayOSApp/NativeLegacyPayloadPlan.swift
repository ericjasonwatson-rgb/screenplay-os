import Foundation
import CryptoKit
import ScreenplayDomain

/// Complete in-memory payload split for a native converted copy. No file is
/// written here; every byte that a later writer may publish is inventoried.
struct NativeLegacyPayloadPlan: Equatable {
    struct InventoryEntry: Equatable {
        let sha256: String
        let bytes: Int
    }

    struct ObjectRevision: Equatable {
        let id: UUID
        let kind: String
        let revisionID: UUID
    }

    let payloads: [String: Data]
    let inventory: [String: InventoryEntry]
    let objects: [ObjectRevision]
    let projectData: Data

    enum Failure: LocalizedError, Equatable {
        case malformedSource
        case missingValue(String)
        case targetFieldCollision(String)
        case unsupportedNoteStatus(String)
        case invalidPayload(String)
        case identityCollision

        var errorDescription: String? {
            switch self {
            case .malformedSource: return "The authenticated legacy source cannot be split into destination payloads."
            case let .missingValue(path): return "The legacy source is missing the required value at \(path)."
            case let .targetFieldCollision(path): return "Legacy content already uses the destination field at \(path)."
            case let .unsupportedNoteStatus(status): return "The note status \(status) cannot be translated without loss."
            case let .invalidPayload(path): return "The destination payload \(path) is not valid JSON."
            case .identityCollision: return "The destination object inventory contains duplicate identities."
            }
        }
    }

    static func build(from preflight: NativeLegacyConversionPlan, identities: NativeLegacyIdentityPlan) throws -> Self {
        guard let source = try? JSONSerialization.jsonObject(with: preflight.sourceBytes) as? [String: Any],
              let project = source["project"] as? [String: Any],
              let projectID = project["id"] as? String,
              let metadata = project["metadata"] as? [String: Any],
              let screenplay = source["screenplay"] as? [String: Any],
              let screenplayID = screenplay["id"] as? String,
              var elements = screenplay["elements"] as? [[String: Any]] else { throw Failure.malformedSource }

        for index in elements.indices {
            guard let rawID = elements[index]["id"] as? String, let id = UUID(uuidString: rawID) else {
                throw Failure.missingValue("/screenplay/elements/\(index)/id")
            }
            if let sceneID = identities.sceneMap[id] {
                guard elements[index]["scene"] == nil else {
                    throw Failure.targetFieldCollision("/screenplay/elements/\(index)/scene")
                }
                elements[index]["scene"] = ["id": sceneID.uuidString.lowercased()]
            }
        }

        guard let translated = try translateSceneReferences(source, path: "", identities: identities) as? [String: Any] else {
            throw Failure.malformedSource
        }
        var values: [String: Any] = [:]
        values["manifest.json"] = [
            "format": "open-screenplay", "format_version": "1.0", "document_id": screenplayID,
            "title": try required(metadata, "title", at: "/project/metadata"),
            "author": try required(metadata, "author", at: "/project/metadata"),
            "created_at": try required(metadata, "created_at", at: "/project/metadata"),
            "modified_at": try required(metadata, "modified_at", at: "/project/metadata")
        ]
        var screenplayPayload: [String: Any] = ["id": screenplayID, "elements": elements]
        if let title = source["title_page"] { screenplayPayload["title_page"] = title }
        values["screenplay.json"] = screenplayPayload
        values["extensions.json"] = ["extensions": ["dev.screenplayos.legacy": [
            "version": "0.1", "source_sha256": preflight.sourceSHA256,
            "role": "immutable-migration-archive", "source": source
        ]]]

        if let notes = translated["script_notes"] as? [[String: Any]] {
            values["notes.json"] = ["notes": try notes.enumerated().map { index, original in
                guard original["text"] == nil, original["anchor"] == nil, original["resolved"] == nil else {
                    throw Failure.targetFieldCollision("/script_notes/\(index)")
                }
                var note = original
                guard let body = note.removeValue(forKey: "body"),
                      let element = note.removeValue(forKey: "screenplay_element_id"),
                      let status = note.removeValue(forKey: "status") as? String else {
                    throw Failure.missingValue("/script_notes/\(index)")
                }
                guard status == "open" || status == "resolved" else { throw Failure.unsupportedNoteStatus(status) }
                note["text"] = body; note["anchor"] = ["element_id": element]; note["resolved"] = status == "resolved"
                return note
            }]
        }

        if let shots = translated["shots"] as? [[String: Any]] {
            var groups: [UUID: [[String: Any]]] = [:]
            var order: [UUID] = []
            for (index, original) in shots.enumerated() {
                guard original["ordinal"] == nil else { throw Failure.targetFieldCollision("/shots/\(index)/ordinal") }
                guard let rawScene = original["scene_id"] as? String, let scene = UUID(uuidString: rawScene) else {
                    throw Failure.missingValue("/shots/\(index)/scene_id")
                }
                if groups[scene] == nil { groups[scene] = []; order.append(scene) }
                var shot = original
                shot["ordinal"] = groups[scene]!.count + 1
                if var refs = shot["source_refs"] as? [[String: Any]] {
                    for refIndex in refs.indices {
                        guard refs[refIndex]["element_id"] == nil else {
                            throw Failure.targetFieldCollision("/shots/\(index)/source_refs/\(refIndex)/element_id")
                        }
                        guard let element = refs[refIndex].removeValue(forKey: "screenplay_element_id") else {
                            throw Failure.missingValue("/shots/\(index)/source_refs/\(refIndex)/screenplay_element_id")
                        }
                        refs[refIndex]["element_id"] = element
                    }
                    shot["source_refs"] = refs
                }
                groups[scene]!.append(shot)
            }
            values["shots.json"] = ["shot_addenda": try order.map { scene in
                guard let id = identities.shotAddendumIDs[scene] else { throw Failure.missingValue("/shots/addendum") }
                return ["id": id.uuidString.lowercased(), "scene_id": scene.uuidString.lowercased(), "shots": groups[scene]!] as [String: Any]
            }]
        }

        for (sourceKey, file, wrapper) in [
            ("outline", "film/outline.json", "beats"), ("board_frames", "film/boards.json", "boards"),
            ("proposals", "film/proposals.json", "proposals"), ("activity", "film/activity.json", "activity")
        ] where translated[sourceKey] != nil {
            values[file] = [wrapper: translated[sourceKey]!]
        }
        for (sourceKey, file) in [("editorial_spine", "film/edit.json"), ("production_context", "film/production.json")]
            where translated[sourceKey] != nil { values[file] = translated[sourceKey]! }

        if !preflight.media.isEmpty {
            values["film/media.json"] = ["version": 1, "project_id": projectID, "media": preflight.media.map { board in
                ["id": board.boardID.uuidString.lowercased(), "board_id": board.boardID.uuidString.lowercased(),
                 "shot_id": board.shotID.uuidString.lowercased(),
                 "selected_version_id": board.selectedVersionID?.uuidString.lowercased() ?? NSNull(),
                 "versions": board.versions.map { version in
                    ["id": version.id.uuidString.lowercased(), "path": version.attachmentPath,
                     "sha256": version.sha256, "bytes": version.byteCount, "media_type": "image/png",
                     "width": version.width, "height": version.height, "prompt": version.prompt, "model": version.model]
                 }] as [String: Any]
            }]
        }

        var payloads: [String: Data] = [:]
        for (path, value) in values { payloads[path] = try json(value, path: path) }
        for (path, attachment) in preflight.attachments { payloads[path] = attachment.bytes }
        let inventory = Dictionary(uniqueKeysWithValues: payloads.map { path, data in
            (path, InventoryEntry(sha256: sha256(data), bytes: data.count))
        })

        var objects = identities.sourceIdentities.map { item in
            ObjectRevision(id: item.id, kind: item.path, revisionID: objectRevision(item.id, project: preflight.document.project.id, head: identities.revisionID))
        }
        objects += identities.sceneMap.values.map {
            ObjectRevision(id: $0, kind: "scene", revisionID: objectRevision($0, project: preflight.document.project.id, head: identities.revisionID))
        }
        objects += identities.shotAddendumIDs.values.map {
            ObjectRevision(id: $0, kind: "shot-addendum", revisionID: objectRevision($0, project: preflight.document.project.id, head: identities.revisionID))
        }
        guard Set(objects.map(\.id)).count == objects.count else { throw Failure.identityCollision }
        objects.sort { $0.id.uuidString < $1.id.uuidString }
        let projectPayload: [String: Any] = [
            "format": "open-screenplay-project", "format_version": "0.1-draft",
            "project_id": projectID, "screenplay_id": screenplayID,
            "head": ["id": identities.revisionID.uuidString.lowercased(), "parents": [], "created_at": identities.createdAt,
                     "objects": objects.map { ["id": $0.id.uuidString.lowercased(), "kind": $0.kind,
                                                "revision_id": $0.revisionID.uuidString.lowercased(), "parents": [], "state": "active"] },
                     "files": inventory.mapValues { ["sha256": $0.sha256, "bytes": $0.bytes] }]
        ]
        let projectData = try json(projectPayload, path: "project.json")
        return Self(payloads: payloads, inventory: inventory, objects: objects, projectData: projectData)
    }

    private static func translateSceneReferences(_ value: Any, path: String, identities: NativeLegacyIdentityPlan) throws -> Any {
        if let array = value as? [Any] {
            return try array.enumerated().map { try translateSceneReferences($0.element, path: path + "/\($0.offset)", identities: identities) }
        }
        guard var object = value as? [String: Any] else { return value }
        for key in object.keys { object[key] = try translateSceneReferences(object[key]!, path: path + "/" + key, identities: identities) }
        if let alias = object["scene_spine_id"] as? String {
            guard object["scene_id"] == nil else { throw Failure.targetFieldCollision(path + "/scene_id") }
            guard let id = identities.aliases[alias] else { throw Failure.missingValue(path + "/scene_spine_id") }
            object["scene_id"] = id.uuidString.lowercased()
        }
        if path.hasPrefix("/outline/"), path.split(separator: "/").count == 2,
           let aliases = object["linked_scene_spine_ids"] as? [String] {
            guard object["linked_scene_ids"] == nil else { throw Failure.targetFieldCollision(path + "/linked_scene_ids") }
            object["linked_scene_ids"] = try aliases.map {
                guard let id = identities.aliases[$0] else { throw Failure.missingValue(path + "/linked_scene_spine_ids") }
                return id.uuidString.lowercased()
            }
        }
        return object
    }

    private static func required(_ object: [String: Any], _ key: String, at path: String) throws -> Any {
        guard let value = object[key] else { throw Failure.missingValue(path + "/" + key) }; return value
    }
    private static func json(_ value: Any, path: String) throws -> Data {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              (try? PreservedJSON(data)) != nil else { throw Failure.invalidPayload(path) }
        return data
    }
    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    private static func objectRevision(_ id: UUID, project: UUID, head: UUID) -> UUID {
        NativeLegacyIdentityPlan.uuid5(namespace: project, name: "legacy-destination-0.1:object:\(id.uuidString.lowercased()):\(head.uuidString.lowercased())")
    }
}
