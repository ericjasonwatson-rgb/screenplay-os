import Foundation

private struct FormattingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
private func checkFormattingKeys(_ decoder: Decoder, allowed: Set<String>) throws {
    let container = try decoder.container(keyedBy: FormattingKey.self)
    guard container.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else { throw StyledText.Failure.unsupportedStyle }
}

/// Paragraph-local formatting. Stored offsets count Unicode scalars, never UTF-16.
/// This projection is not a replacement for the preserving package reader/writer.
public struct StyledText: Equatable, Codable {
    public enum Failure: Error { case invalidRange, splitGrapheme, unsupportedStyle }
    public struct Style: Equatable, Codable {
        public var bold: Bool?
        public var italic: Bool?
        public var underline: Bool?
        public var strikethrough: Bool?
        public init(bold: Bool? = nil, italic: Bool? = nil, underline: Bool? = nil, strikethrough: Bool? = nil) {
            self.bold = bold; self.italic = italic; self.underline = underline; self.strikethrough = strikethrough
        }
        private enum Keys: String, CodingKey { case bold, italic, underline, strikethrough }
        private struct Key: CodingKey { var stringValue: String; var intValue: Int? { nil }; init?(stringValue: String) { self.stringValue = stringValue }; init?(intValue: Int) { return nil } }
        public init(from decoder: Decoder) throws {
            let all = try decoder.container(keyedBy: Key.self)
            guard all.allKeys.allSatisfy({ Keys(rawValue: $0.stringValue) != nil }) else { throw Failure.unsupportedStyle }
            let c = try decoder.container(keyedBy: Keys.self)
            bold = c.contains(.bold) ? try c.decode(Bool.self, forKey: .bold) : nil
            italic = c.contains(.italic) ? try c.decode(Bool.self, forKey: .italic) : nil
            underline = c.contains(.underline) ? try c.decode(Bool.self, forKey: .underline) : nil
            strikethrough = c.contains(.strikethrough) ? try c.decode(Bool.self, forKey: .strikethrough) : nil
        }
        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: Keys.self)
            try c.encodeIfPresent(bold, forKey: .bold); try c.encodeIfPresent(italic, forKey: .italic)
            try c.encodeIfPresent(underline, forKey: .underline); try c.encodeIfPresent(strikethrough, forKey: .strikethrough)
        }
        fileprivate func applying(_ patch: Style) -> Style {
            Style(bold: patch.bold ?? bold, italic: patch.italic ?? italic,
                  underline: patch.underline ?? underline, strikethrough: patch.strikethrough ?? strikethrough)
        }
        fileprivate var canonical: Style {
            Style(bold: bold == true ? true : nil, italic: italic == true ? true : nil,
                  underline: underline == true ? true : nil, strikethrough: strikethrough == true ? true : nil)
        }
    }
    public struct Run: Equatable, Codable {
        public let start: Int
        public let length: Int
        public let style: Style
        public init(start: Int, length: Int, style: Style) { self.start = start; self.length = length; self.style = style }
        private enum CodingKeys: String, CodingKey { case start, length, style }
        public init(from decoder: Decoder) throws {
            try checkFormattingKeys(decoder, allowed: ["start", "length", "style"])
            let c = try decoder.container(keyedBy: CodingKeys.self)
            start = try c.decode(Int.self, forKey: .start); length = try c.decode(Int.self, forKey: .length)
            style = try c.decode(Style.self, forKey: .style)
        }
    }
    public static func == (lhs: StyledText, rhs: StyledText) -> Bool {
        lhs.text.unicodeScalars.elementsEqual(rhs.text.unicodeScalars) && lhs.runs == rhs.runs
    }
    public private(set) var text: String
    public private(set) var runs: [Run]
    public init(text: String, runs: [Run] = []) throws {
        let count = text.unicodeScalars.count
        for run in runs {
            guard run.start >= 0, run.length >= 0, run.start <= count, run.length <= count - run.start else { throw Failure.invalidRange }
        }
        self.text = text; self.runs = runs
    }
    private enum CodingKeys: String, CodingKey { case text, runs }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try checkFormattingKeys(decoder, allowed: ["text", "runs"])
        try self.init(text: c.decode(String.self, forKey: .text), runs: c.contains(.runs) ? c.decode([Run].self, forKey: .runs) : [])
    }
    /// Preserve ordered overlapping runs on read; resolve them only for display/commands.
    public var resolvedRuns: [Run] { Self.compress(styles) }
    private var styles: [Style] {
        var result = Array(repeating: Style(), count: text.unicodeScalars.count)
        for run in runs {
            for i in run.start..<(run.start + run.length) { result[i] = result[i].applying(run.style) }
        }
        return result.map(\.canonical)
    }
    private static func compress(_ values: [Style]) -> [Run] {
        var result: [Run] = [], start = 0
        while start < values.count {
            var end = start + 1
            while end < values.count && values[end] == values[start] { end += 1 }
            if values[start] != Style() { result.append(Run(start: start, length: end - start, style: values[start])) }
            start = end
        }
        return result
    }
    private func checked(_ range: Range<Int>) throws -> Range<String.UnicodeScalarView.Index> {
        let scalars = text.unicodeScalars
        guard range.lowerBound >= 0, range.upperBound <= scalars.count else { throw Failure.invalidRange }
        let lower = scalars.index(scalars.startIndex, offsetBy: range.lowerBound)
        let upper = scalars.index(scalars.startIndex, offsetBy: range.upperBound)
        let boundaries = Set(text.indices).union([text.endIndex])
        guard boundaries.contains(lower), boundaries.contains(upper) else { throw Failure.splitGrapheme }
        return lower..<upper
    }
    public func scalarRange(fromUTF16 range: NSRange) throws -> Range<Int> {
        let count = text.utf16.count
        guard range.location >= 0, range.length >= 0, range.location <= count, range.length <= count - range.location,
              let native = Range(range, in: text) else { throw Failure.invalidRange }
        let start = text.unicodeScalars.distance(from: text.startIndex, to: native.lowerBound)
        let end = text.unicodeScalars.distance(from: text.startIndex, to: native.upperBound)
        _ = try checked(start..<end)
        return start..<end
    }
    public func utf16Range(fromScalars range: Range<Int>) throws -> NSRange {
        NSRange(try checked(range), in: text)
    }
    public mutating func format(_ range: Range<Int>, patch: Style) throws {
        _ = try checked(range)
        guard !range.isEmpty else { return } // Insertion style belongs to transient editor state.
        var values = styles
        let original = values
        for i in range { values[i] = values[i].applying(patch).canonical }
        if values != original { runs = Self.compress(values) }
    }
    public mutating func clear(_ range: Range<Int>) throws {
        try format(range, patch: Style(bold: false, italic: false, underline: false, strikethrough: false))
    }
    /// Caller supplies insertion style explicitly, avoiding ambiguous boundary inheritance.
    public mutating func replace(_ range: Range<Int>, with replacement: String, style: Style = Style()) throws {
        let indices = try checked(range)
        var values = styles
        var candidate = text
        candidate.replaceSubrange(indices, with: replacement)
        values.replaceSubrange(range, with: Array(repeating: style.canonical, count: replacement.unicodeScalars.count))
        text = candidate; runs = Self.compress(values)
    }
    public func split(at offset: Int) throws -> (StyledText, StyledText) {
        let point = try checked(offset..<offset).lowerBound
        let values = styles
        return (try StyledText(text: String(text[..<point]), runs: Self.compress(Array(values[..<offset]))),
                try StyledText(text: String(text[point...]), runs: Self.compress(Array(values[offset...]))))
    }
    public func appending(_ other: StyledText) throws -> StyledText {
        try StyledText(text: text + other.text, runs: Self.compress(styles + other.styles))
    }
}

/// A paragraph command harness using the same byte-history kernel as PackageTextSession.
/// Package integration must commit text and runs together in its document-wide history.
public struct StyledTextHistory {
    public enum Failure: Error { case staleRevision }
    public private(set) var value: StyledText
    public private(set) var revision = UUID()
    private var history: PreservedJSONSession
    public init(_ value: StyledText) throws {
        self.value = value
        history = try PreservedJSONSession(JSONEncoder().encode(value))
    }
    public mutating func perform(expectedRevision: UUID, _ edit: (inout StyledText) throws -> Void) throws {
        guard revision == expectedRevision else { throw Failure.staleRevision }
        var candidate = value
        try edit(&candidate)
        guard candidate != value else { return }
        history.commit(try PreservedJSON(JSONEncoder().encode(candidate)))
        value = candidate; revision = UUID()
    }
    public mutating func undo() {
        guard history.canUndo else { return }
        history.undo(); value = try! JSONDecoder().decode(StyledText.self, from: history.document.data); revision = UUID()
    }
    public mutating func redo() {
        guard history.canRedo else { return }
        history.redo(); value = try! JSONDecoder().decode(StyledText.self, from: history.document.data); revision = UUID()
    }
}

/// Proposed settings.json formatting projection. UI zoom and paper color do not belong here.
public struct DocumentTypography: Equatable, Codable {
    public enum Failure: Error { case invalidTypography }
    public let paper: String
    public let fontFamily: String
    public let fontSize: Double
    public init(paper: String = "US_LETTER", fontFamily: String = "Courier", fontSize: Double = 12) throws {
        guard ["US_LETTER", "A4"].contains(paper), !fontFamily.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              fontFamily.count <= 256, fontSize.isFinite, fontSize > 0, fontSize <= 200 else { throw Failure.invalidTypography }
        self.paper = paper; self.fontFamily = fontFamily; self.fontSize = fontSize
    }
    private enum CodingKeys: String, CodingKey { case paper; case fontFamily = "font_family"; case fontSize = "font_size" }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try checkFormattingKeys(decoder, allowed: ["paper", "font_family", "font_size"])
        try self.init(paper: c.decode(String.self, forKey: .paper), fontFamily: c.decode(String.self, forKey: .fontFamily), fontSize: c.decode(Double.self, forKey: .fontSize))
    }
}
