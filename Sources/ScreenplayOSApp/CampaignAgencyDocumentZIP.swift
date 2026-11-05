import Foundation
import zlib

/// A deliberately narrow ZIP reader, never a filesystem extractor. All sizes,
/// offsets, member kinds, names and CRCs are validated before XML is interpreted.
/// Input is at most 2 MiB, each inflated member 4 MiB, total inflation 8 MiB.
enum CampaignAgencyDocumentZIP {
    typealias Failure = CampaignAgencyDocumentExtraction.Failure
    static let maximumEntries = 256
    static let maximumMemberBytes = 4 * 1_024 * 1_024
    static let maximumInflatedBytes = 8 * 1_024 * 1_024

    private struct Entry {
        let name: String
        let nameBytes: [UInt8]
        let flags: Int
        let method: Int
        let crc: UInt32
        let compressed: Int
        let expanded: Int
        let offset: Int
    }

    static func read(_ data: Data) throws -> [String: Data] {
        try Task.checkCancellation()
        guard data.count >= 22, data.count <= CampaignAgencyDocumentExtraction.maximumOriginalBytes else {
            throw Failure.unsafeArchive
        }
        let bytes = [UInt8](data)
        let reader = Reader(bytes: bytes)
        // Require one terminal end record; appended content and multipart ZIPs
        // are rejected rather than tolerated by a permissive general unzipper.
        var end: Int?
        for offset in stride(from: bytes.count - 22, through: max(0, bytes.count - 65_557), by: -1) {
            if try reader.u32(offset) == 0x06054b50,
               offset + 22 + (try reader.u16(offset + 20)) == bytes.count {
                end = offset
                break
            }
        }
        guard let end, try reader.u16(end + 4) == 0, try reader.u16(end + 6) == 0 else {
            throw Failure.unsafeArchive
        }
        let count = try reader.u16(end + 10)
        let centralSize = Int(try reader.u32(end + 12))
        let centralOffset = Int(try reader.u32(end + 16))
        guard count > 0, count <= maximumEntries, try reader.u16(end + 8) == count,
              centralOffset + centralSize == end else { throw Failure.unsafeArchive }
        var entries: [Entry] = []
        var names = Set<String>()
        var cursor = centralOffset
        var totalExpanded = 0
        for _ in 0..<count {
            try Task.checkCancellation()
            guard try reader.u32(cursor) == 0x02014b50 else { throw Failure.unsafeArchive }
            let madeBy = try reader.u16(cursor + 4) >> 8
            let requiredVersion = try reader.u16(cursor + 6)
            let flags = try reader.u16(cursor + 8)
            let method = try reader.u16(cursor + 10)
            let crc = try reader.u32(cursor + 16)
            let compressed = Int(try reader.u32(cursor + 20))
            let expanded = Int(try reader.u32(cursor + 24))
            let nameLength = try reader.u16(cursor + 28)
            let extraLength = try reader.u16(cursor + 30)
            let commentLength = try reader.u16(cursor + 32)
            let attributes = try reader.u32(cursor + 38)
            let localOffset = Int(try reader.u32(cursor + 42))
            // Bits 1/2 are deflate options, 3 is a data descriptor, 11 UTF-8.
            // All encryption, patching, masked headers and reserved flags fail.
            guard requiredVersion <= 20, [0, 3].contains(madeBy),
                  flags & ~0x080e == 0, [0, 8].contains(method),
                  method == 8 || flags & 0x0006 == 0,
                  try reader.u16(cursor + 34) == 0,
                  attributes & 0x10 == 0,
                  madeBy != 3 || [0, 0o100000].contains(Int(attributes >> 16) & 0o170000),
                  compressed <= bytes.count, expanded <= maximumMemberBytes else { throw Failure.unsafeArchive }
            totalExpanded += expanded
            guard totalExpanded <= maximumInflatedBytes else { throw Failure.unsafeArchive }
            let nameBytes = try reader.slice(cursor + 46, nameLength)
            guard let name = String(bytes: nameBytes, encoding: .utf8), safeName(name),
                  names.insert(name.precomposedStringWithCanonicalMapping.lowercased()).inserted else {
                throw Failure.unsafeArchive
            }
            try reader.validateExtra(cursor + 46 + nameLength, extraLength)
            cursor += 46 + nameLength + extraLength + commentLength
            guard cursor <= end else { throw Failure.unsafeArchive }
            entries.append(Entry(name: name, nameBytes: nameBytes, flags: flags, method: method,
                                 crc: crc, compressed: compressed, expanded: expanded, offset: localOffset))
        }
        guard cursor == end else { throw Failure.unsafeArchive }
        var result: [String: Data] = [:]
        cursor = 0
        // Local records must cover exactly the area preceding the central
        // directory, with no overlap, hidden records, preamble or trailing gap.
        for entry in entries.sorted(by: { $0.offset < $1.offset }) {
            try Task.checkCancellation()
            guard entry.offset == cursor, try reader.u32(cursor) == 0x04034b50,
                  try reader.u16(cursor + 4) <= 20,
                  try reader.u16(cursor + 6) == entry.flags,
                  try reader.u16(cursor + 8) == entry.method else { throw Failure.unsafeArchive }
            let nameLength = try reader.u16(cursor + 26)
            let extraLength = try reader.u16(cursor + 28)
            guard try reader.slice(cursor + 30, nameLength) == entry.nameBytes else { throw Failure.unsafeArchive }
            try reader.validateExtra(cursor + 30 + nameLength, extraLength)
            let localCRC = try reader.u32(cursor + 14)
            let localCompressed = Int(try reader.u32(cursor + 18))
            let localExpanded = Int(try reader.u32(cursor + 22))
            if entry.flags & 8 == 0 {
                guard localCRC == entry.crc, localCompressed == entry.compressed,
                      localExpanded == entry.expanded else { throw Failure.unsafeArchive }
            } else {
                guard (localCRC == 0 || localCRC == entry.crc),
                      (localCompressed == 0 || localCompressed == entry.compressed),
                      (localExpanded == 0 || localExpanded == entry.expanded) else { throw Failure.unsafeArchive }
            }
            let start = cursor + 30 + nameLength + extraLength
            let compressed = try reader.slice(start, entry.compressed)
            cursor = start + entry.compressed
            if entry.flags & 8 != 0 {
                if try reader.u32(cursor) == 0x08074b50 { cursor += 4 }
                guard try reader.u32(cursor) == entry.crc,
                      Int(try reader.u32(cursor + 4)) == entry.compressed,
                      Int(try reader.u32(cursor + 8)) == entry.expanded else { throw Failure.unsafeArchive }
                cursor += 12
            }
            guard cursor <= centralOffset else { throw Failure.unsafeArchive }
            let content: [UInt8]
            if entry.method == 0 {
                guard entry.compressed == entry.expanded else { throw Failure.unsafeArchive }
                content = compressed
            } else {
                content = try inflate(compressed, expected: entry.expanded)
            }
            guard checksum(content) == entry.crc else { throw Failure.unsafeArchive }
            result[entry.name] = Data(content)
        }
        guard cursor == centralOffset else { throw Failure.unsafeArchive }
        return result
    }

    private static func safeName(_ name: String) -> Bool {
        guard !name.isEmpty, name.utf8.count <= 1_024, !name.contains("\\"), !name.contains(":"),
              !name.hasPrefix("/"), !name.hasSuffix("/"),
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return false }
        return name.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    private static func inflate(_ input: [UInt8], expected: Int) throws -> [UInt8] {
        var stream = z_stream()
        guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw Failure.unsafeArchive
        }
        defer { inflateEnd(&stream) }
        // One extra byte detects dishonest declared sizes without allowing
        // unbounded expansion. The decoder may never grow this allocation.
        var output = [UInt8](repeating: 0, count: expected + 1)
        let status: Int32 = input.withUnsafeBytes { source in
            output.withUnsafeMutableBytes { destination in
                stream.next_in = UnsafeMutablePointer(mutating: source.bindMemory(to: Bytef.self).baseAddress)
                stream.avail_in = uInt(input.count)
                stream.next_out = destination.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(expected + 1)
                return zlib.inflate(&stream, Z_FINISH)
            }
        }
        guard status == Z_STREAM_END, Int(stream.total_out) == expected, stream.avail_in == 0 else {
            throw Failure.unsafeArchive
        }
        output.removeLast()
        return output
    }

    static func checksum(_ bytes: [UInt8]) -> UInt32 {
        var crc = UInt32.max
        for byte in bytes { crc = (crc >> 8) ^ crcTable[Int((crc ^ UInt32(byte)) & 0xff)] }
        return ~crc
    }

    private static let crcTable: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 { value = (value >> 1) ^ (value & 1 == 1 ? 0xedb88320 : 0) }
        return value
    }

    private struct Reader {
        let bytes: [UInt8]
        func slice(_ offset: Int, _ count: Int) throws -> [UInt8] {
            guard offset >= 0, count >= 0, offset <= bytes.count, count <= bytes.count - offset else {
                throw Failure.unsafeArchive
            }
            return Array(bytes[offset..<(offset + count)])
        }
        func u16(_ offset: Int) throws -> Int {
            guard offset >= 0, offset <= bytes.count - 2 else { throw Failure.unsafeArchive }
            return Int(bytes[offset]) | Int(bytes[offset + 1]) << 8
        }
        func u32(_ offset: Int) throws -> UInt32 {
            guard offset >= 0, offset <= bytes.count - 4 else { throw Failure.unsafeArchive }
            return UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 |
                UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
        }
        func validateExtra(_ offset: Int, _ count: Int) throws {
            _ = try slice(offset, count)
            var cursor = offset
            while cursor < offset + count {
                guard cursor + 4 <= offset + count else { throw Failure.unsafeArchive }
                let kind = try u16(cursor)
                let length = try u16(cursor + 2)
                guard ![0x0001, 0x0017, 0x9901, 0x7075].contains(kind),
                      cursor + 4 + length <= offset + count else { throw Failure.unsafeArchive }
                cursor += 4 + length
            }
        }
    }
}
