import Foundation

/// An in-memory JSON editing primitive. It does not authorize screenplay edits,
/// repair references, or write packages. Untouched tokens retain their exact bytes.
public struct PreservedJSON {
    public enum Component: Hashable {
        case key(String), index(Int)
        public static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case let (.key(a), .key(b)): return a.unicodeScalars.elementsEqual(b.unicodeScalars)
            case let (.index(a), .index(b)): return a == b
            default: return false
            }
        }
        public func hash(into hasher: inout Hasher) {
            switch self {
            case let .key(key): hasher.combine(0); hasher.combine(Data(key.utf8))
            case let .index(index): hasher.combine(1); hasher.combine(index)
            }
        }
    }
    public enum Failure: Error { case malformed, duplicateKey, limit, missingString, staleValue }
    public private(set) var data: Data
    private var values: [[Component]: Range<Int>]
    private var strings: [[Component]: Range<Int>]

    public init(_ data: Data) throws {
        guard data.count <= 32 * 1024 * 1024 else { throw Failure.limit }
        guard String(data: data, encoding: .utf8) != nil else { throw Failure.malformed }
        var parser = Parser(bytes: Array(data))
        try parser.value([], depth: 0)
        parser.space()
        guard parser.position == parser.bytes.count else { throw Failure.malformed }
        self.data = data
        self.strings = parser.strings
        self.values = parser.values
    }

    public func string(at path: [Component]) throws -> String {
        guard let range = strings[path] else { throw Failure.missingString }
        return try JSONDecoder().decode(String.self, from: data.subdata(in: range))
    }

    /// Compare-and-replace one complete string token. A failed request is atomic.
    /// Compare Unicode scalars, since Swift String equality normalizes equivalents.
    @discardableResult
    public mutating func replaceString(at path: [Component], expected: String, with replacement: String) throws -> Bool {
        let current = try string(at: path)
        guard current.unicodeScalars.elementsEqual(expected.unicodeScalars) else { throw Failure.staleValue }
        if current.unicodeScalars.elementsEqual(replacement.unicodeScalars) { return false }
        let encoded = try JSONEncoder().encode(replacement)
        var candidate = data
        candidate.replaceSubrange(strings[path]!, with: encoded)
        self = try PreservedJSON(candidate)
        return true
    }

    // Internal structural editing primitives; callers must validate domain semantics.
    func arrayValues(at path: [Component]) throws -> [Data] {
        guard let range = values[path], data[range.lowerBound] == 91 else { throw Failure.malformed }
        var result: [Data] = []
        while let child = values[path + [.index(result.count)]] { result.append(data.subdata(in: child)) }
        return result
    }
    mutating func replaceArray(at path: [Component], with items: [Data]) throws {
        _ = try arrayValues(at: path)
        var replacement = Data("[".utf8)
        for (index, item) in items.enumerated() {
            _ = try PreservedJSON(item)
            if index > 0 { replacement.append(contentsOf: ",".utf8) }
            replacement.append(item)
        }
        replacement.append(contentsOf: "]".utf8)
        var candidate = data
        candidate.replaceSubrange(values[path]!, with: replacement)
        self = try PreservedJSON(candidate)
    }

    func valueData(at path: [Component]) throws -> Data {
        guard let range = values[path] else { throw Failure.malformed }
        return data.subdata(in: range)
    }
    mutating func setMember(_ key: String, at path: [Component], value: Data) throws {
        _ = try PreservedJSON(value)
        guard let object = values[path], data[object.lowerBound] == 123 else { throw Failure.malformed }
        var candidate = data
        if let range = values[path + [.key(key)]] { candidate.replaceSubrange(range, with: value) }
        else {
            let hasMembers = values.keys.contains { $0.count == path.count + 1 && Array($0.prefix(path.count)) == path }
            var member = Data((hasMembers ? "," : "").utf8)
            member.append(try JSONEncoder().encode(key)); member.append(58); member.append(value)
            candidate.insert(contentsOf: member, at: object.upperBound - 1)
        }
        self = try PreservedJSON(candidate)
    }

    private struct Parser {
        let bytes: [UInt8]
        var position = 0
        var strings: [[Component]: Range<Int>] = [:]
        var values: [[Component]: Range<Int>] = [:]
        var current: UInt8? { position < bytes.count ? bytes[position] : nil }
        mutating func space() { while let byte = current, [9, 10, 13, 32].contains(byte) { position += 1 } }
        mutating func consume(_ byte: UInt8) throws {
            guard current == byte else { throw Failure.malformed }; position += 1
        }
        mutating func quoted() throws -> (String, Range<Int>) {
            let start = position
            try consume(34)
            while let byte = current {
                position += 1
                if byte == 92 {
                    guard current != nil else { throw Failure.malformed }
                    position += 1
                } else if byte == 34 {
                    let range = start..<position
                    do { return (try JSONDecoder().decode(String.self, from: Data(bytes[range])), range) }
                    catch { throw Failure.malformed }
                }
            }
            throw Failure.malformed
        }
        mutating func value(_ path: [Component], depth: Int) throws {
            guard depth < 128 else { throw Failure.limit }
            space()
            let start = position
            defer { values[path] = start..<position }
            switch current {
            case 34:
                strings[path] = try quoted().1
            case 123:
                position += 1; space()
                if current == 125 { position += 1; return }
                var keys = Set<Data>()
                while true {
                    space()
                    let key = try quoted().0
                    // JSON key identity follows decoded code points, not NFC equivalence.
                    guard keys.insert(Data(key.utf8)).inserted else { throw Failure.duplicateKey }
                    space(); try consume(58)
                    try value(path + [.key(key)], depth: depth + 1)
                    space()
                    if current == 125 { position += 1; return }
                    try consume(44)
                }
            case 91:
                position += 1; space()
                if current == 93 { position += 1; return }
                var index = 0
                while true {
                    try value(path + [.index(index)], depth: depth + 1)
                    index += 1; space()
                    if current == 93 { position += 1; return }
                    try consume(44)
                }
            case 116: try literal("true")
            case 102: try literal("false")
            case 110: try literal("null")
            default: try number()
            }
        }
        mutating func literal(_ word: String) throws {
            for byte in word.utf8 { try consume(byte) }
        }
        mutating func digits() throws {
            let start = position
            while let byte = current, (48...57).contains(byte) { position += 1 }
            guard position > start else { throw Failure.malformed }
        }
        mutating func number() throws {
            if current == 45 { position += 1 }
            if current == 48 { position += 1 }
            else {
                guard let byte = current, (49...57).contains(byte) else { throw Failure.malformed }
                try digits()
            }
            if current == 46 { position += 1; try digits() }
            if current == 101 || current == 69 {
                position += 1
                if current == 43 || current == 45 { position += 1 }
                try digits()
            }
        }
    }
}

/// Exact-byte undo/redo for an editing session; no filesystem side effects.
public struct PreservedJSONSession {
    public private(set) var document: PreservedJSON
    private struct State { let id: UUID; let bytes: Data; let group: UUID? }
    private var undoStates: [State] = []
    private var redoStates: [State] = []
    public static let maximumHistoryBytes = 64 * 1024 * 1024
    public static let maximumHistorySteps = 200
    public init(_ data: Data) throws { document = try PreservedJSON(data) }
    public var canUndo: Bool { !undoStates.isEmpty }
    public var canRedo: Bool { !redoStates.isEmpty }
    public var undoHistoryID: UUID? { undoStates.last?.id }
    public var redoHistoryID: UUID? { redoStates.last?.id }
    public var historyIDs: Set<UUID> { Set((undoStates + redoStates).map(\.id)) }
    public var historyBytes: Int { (undoStates + redoStates).reduce(0) { $0 + $1.bytes.count } }
    private mutating func trim() {
        while undoStates.count + redoStates.count > Self.maximumHistorySteps || historyBytes > Self.maximumHistoryBytes {
            if !undoStates.isEmpty { undoStates.removeFirst() }
            else if !redoStates.isEmpty { redoStates.removeFirst() }
            else { break }
        }
    }
    public mutating func replaceString(at path: [PreservedJSON.Component], expected: String, with replacement: String, historyGroup: UUID? = nil) throws {
        var candidate = document
        guard try candidate.replaceString(at: path, expected: expected, with: replacement) else { return }
        commit(candidate, historyGroup: historyGroup)
    }
    mutating func commit(_ candidate: PreservedJSON, historyGroup: UUID? = nil) {
        guard candidate.data != document.data else { return }
        if historyGroup == nil || undoStates.last?.group != historyGroup || !redoStates.isEmpty {
            undoStates.append(State(id: UUID(), bytes: document.data, group: historyGroup))
        }
        redoStates.removeAll(); document = candidate; trim()
    }
    public mutating func undo() {
        guard let previous = undoStates.popLast() else { return }
        redoStates.append(State(id: previous.id, bytes: document.data, group: nil))
        document = try! PreservedJSON(previous.bytes); trim()
    }
    public mutating func redo() {
        guard let next = redoStates.popLast() else { return }
        undoStates.append(State(id: next.id, bytes: document.data, group: nil))
        document = try! PreservedJSON(next.bytes); trim()
    }
}
