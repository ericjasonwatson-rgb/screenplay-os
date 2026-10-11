import Foundation
import CryptoKit

/// Deterministic identity and scene-reference stage for native destination construction.
/// It consumes an authenticated preflight and performs no I/O.
struct NativeLegacyIdentityPlan: Equatable {
    struct SourceIdentity: Equatable {
        let id: UUID
        let path: String
    }

    struct Reference: Equatable {
        let sourcePath: String
        let targetSceneID: UUID
    }

    let sceneMap: [UUID: UUID]
    let aliases: [String: UUID]
    let references: [Reference]
    let shotAddendumIDs: [UUID: UUID]
    let sourceIdentities: [SourceIdentity]
    let revisionID: UUID
    let createdAt: String

    enum Failure: LocalizedError, Equatable {
        case malformedSource
        case duplicateSceneAlias(String)
        case unresolvedSceneAlias(String, String)
        case identityCollision
        case invalidTimestamp

        var errorDescription: String? {
            switch self {
            case .malformedSource: return "The authenticated legacy source could not be inspected for destination identities."
            case let .duplicateSceneAlias(alias): return "More than one scene heading uses the legacy alias \(alias)."
            case let .unresolvedSceneAlias(alias, path): return "The scene alias \(alias) at \(path) does not identify one scene."
            case .identityCollision: return "A deterministic destination identity collides with an existing project identity."
            case .invalidTimestamp: return "Destination construction requires an ISO 8601 timestamp with a time zone."
            }
        }
    }

    static func build(from preflight: NativeLegacyConversionPlan, createdAt: String) throws -> Self {
        guard validTimestamp(createdAt) else { throw Failure.invalidTimestamp }
        guard let root = try? JSONSerialization.jsonObject(with: preflight.sourceBytes) as? [String: Any],
              let screenplay = root["screenplay"] as? [String: Any],
              let elements = screenplay["elements"] as? [[String: Any]] else { throw Failure.malformedSource }

        let namespace = preflight.document.project.id
        var sceneMap: [UUID: UUID] = [:]
        var aliases: [String: UUID] = [:]
        var allocated = Set<UUID>()
        for element in elements where element["type"] as? String == "scene_heading" {
            guard let rawID = element["id"] as? String, let elementID = UUID(uuidString: rawID) else {
                throw Failure.malformedSource
            }
            let sceneID = uuid5(namespace: namespace, name: "legacy-destination-0.1:scene:\(rawID.lowercased())")
            guard allocated.insert(sceneID).inserted else { throw Failure.identityCollision }
            sceneMap[elementID] = sceneID
            if let alias = element["spine_id"] as? String, !alias.isEmpty {
                guard aliases[alias] == nil else { throw Failure.duplicateSceneAlias(alias) }
                aliases[alias] = sceneID
            }
        }

        let sourceIdentities = try knownIdentities(in: root)
        let existing = Set(sourceIdentities.map(\.id))
        guard existing.isDisjoint(with: allocated) else { throw Failure.identityCollision }
        var references: [Reference] = []
        try collectSceneReferences(root, path: "", aliases: aliases, into: &references)

        var shotAddendumIDs: [UUID: UUID] = [:]
        for shot in preflight.document.shots {
            guard let sceneID = aliases[shot.sceneSpineID] else {
                throw Failure.unresolvedSceneAlias(shot.sceneSpineID, "/shots")
            }
            if shotAddendumIDs[sceneID] == nil {
                let id = uuid5(namespace: namespace, name: "legacy-destination-0.1:shot-addendum:\(sceneID.uuidString.lowercased())")
                guard !existing.contains(id), allocated.insert(id).inserted else { throw Failure.identityCollision }
                shotAddendumIDs[sceneID] = id
            }
        }

        let revision = uuid5(
            namespace: namespace,
            name: "legacy-destination-0.1:revision:\(preflight.sourceSHA256):\(createdAt)"
        )
        guard !existing.contains(revision), allocated.insert(revision).inserted else { throw Failure.identityCollision }
        return Self(sceneMap: sceneMap, aliases: aliases, references: references,
                    shotAddendumIDs: shotAddendumIDs, sourceIdentities: sourceIdentities,
                    revisionID: revision, createdAt: createdAt)
    }

    private static func collectSceneReferences(
        _ value: Any, path: String, aliases: [String: UUID], into result: inout [Reference]
    ) throws {
        if let values = value as? [Any] {
            for (index, child) in values.enumerated() {
                try collectSceneReferences(child, path: pointer(path, String(index)), aliases: aliases, into: &result)
            }
            return
        }
        guard let object = value as? [String: Any] else { return }
        for key in object.keys.sorted() {
            let child = object[key]!
            let childPath = pointer(path, key)
            if key == "scene_spine_id", let alias = child as? String {
                guard let target = aliases[alias] else { throw Failure.unresolvedSceneAlias(alias, childPath) }
                result.append(Reference(sourcePath: childPath, targetSceneID: target))
            } else if key == "linked_scene_spine_ids", let linked = child as? [Any] {
                for (index, item) in linked.enumerated() {
                    guard let alias = item as? String, let target = aliases[alias] else {
                        throw Failure.unresolvedSceneAlias(item as? String ?? "<invalid>", pointer(childPath, String(index)))
                    }
                    result.append(Reference(sourcePath: pointer(childPath, String(index)), targetSceneID: target))
                }
            }
            try collectSceneReferences(child, path: childPath, aliases: aliases, into: &result)
        }
    }

    private static func knownIdentities(in value: Any) throws -> [SourceIdentity] {
        var identities = Set<UUID>()
        var records: [SourceIdentity] = []
        func visit(_ node: Any, path: String) throws {
            if let values = node as? [Any] {
                for (index, value) in values.enumerated() { try visit(value, path: pointer(path, String(index))) }
                return
            }
            guard let object = node as? [String: Any] else { return }
            let historicalLock = path.contains("/production_page_lock/") || path.contains("/page_lock/")
            if !historicalLock, let raw = object["id"] as? String, let id = UUID(uuidString: raw) {
                guard identities.insert(id).inserted else { throw Failure.identityCollision }
                records.append(SourceIdentity(id: id, path: path.isEmpty ? "/" : path))
            }
            for (key, child) in object { try visit(child, path: pointer(path, key)) }
        }
        try visit(value, path: "")
        return records.sorted { $0.path < $1.path }
    }

    private static func pointer(_ base: String, _ component: String) -> String {
        let escaped = component.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1")
        return base + "/" + escaped
    }

    private static func validTimestamp(_ value: String) -> Bool {
        let expression = #"^\d{4}-\d{2}-\d{2}[Tt]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:[Zz]|[+-]\d{2}:\d{2})$"#
        guard value.range(of: expression, options: .regularExpression) != nil else { return false }
        return ISO8601DateFormatter().date(from: value) != nil
    }

    static func uuid5(namespace: UUID, name: String) -> UUID {
        var tuple = namespace.uuid
        var input = withUnsafeBytes(of: &tuple) { Data($0) }
        input.append(contentsOf: name.utf8)
        var bytes = Array(Insecure.SHA1.hash(data: input).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
