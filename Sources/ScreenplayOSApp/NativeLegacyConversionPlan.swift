import Foundation
import CryptoKit
import Darwin
import ScreenplayDomain

/// Read-only preparation for the native converted-copy writer. This type has no
/// package, preference, network, or active-document side effects.
struct NativeLegacyConversionPlan {
    static let maximumSourceBytes = 32 * 1024 * 1024
    static let maximumImageBytes = 100 * 1024 * 1024

    struct ImageVersion: Equatable {
        let id: UUID
        let attachmentPath: String
        let sha256: String
        let byteCount: Int
        let width: Int
        let height: Int
        let prompt: String
        let model: String
    }

    struct BoardMedia: Equatable {
        let boardID: UUID
        let shotID: UUID
        let selectedVersionID: UUID?
        let versions: [ImageVersion]
    }

    struct Attachment: Equatable {
        let sourceURL: URL
        let sha256: String
        let bytes: Data
    }

    let sourceURL: URL
    let sourceBytes: Data
    let sourceSHA256: String
    let document: ScreenplayOSDocument
    let media: [BoardMedia]
    /// Content-addressed relative package path to the one authenticated payload.
    let attachments: [String: Attachment]

    enum Failure: LocalizedError, Equatable {
        case sourceNotRegular
        case sourceTooLarge
        case malformedSource
        case sourceWouldLoseFields([String])
        case sourceChanged
        case selectedImageMissing(UUID)
        case invalidImageURL(UUID)
        case imageNotRegular(UUID)
        case imageTooLarge(UUID)
        case invalidImageDigest(UUID)
        case imageDigestMismatch(UUID)
        case invalidPNG(UUID)

        var errorDescription: String? {
            switch self {
            case .sourceNotRegular: return "The source must be a regular file and cannot be a symbolic link."
            case .sourceTooLarge: return "The source exceeds the 32 MB conversion limit."
            case .malformedSource: return "The source is not a supported, losslessly preservable ScreenplayOS document."
            case let .sourceWouldLoseFields(paths): return "Conversion would omit unsupported source fields: \(paths.prefix(5).joined(separator: ", "))."
            case .sourceChanged: return "The source changed while the conversion plan was being prepared. Try again from the saved document."
            case let .selectedImageMissing(board): return "Board \(board) selects an image version that is not present."
            case let .invalidImageURL(id): return "Board image \(id) must be a local file or one file inside the adjacent Board Images folder."
            case let .imageNotRegular(id): return "Board image \(id) must be a regular file and cannot be a symbolic link."
            case let .imageTooLarge(id): return "Board image \(id) exceeds the 100 MB conversion limit."
            case let .invalidImageDigest(id): return "Board image \(id) has an invalid SHA-256 digest."
            case let .imageDigestMismatch(id): return "Board image \(id) does not match its recorded SHA-256 digest."
            case let .invalidPNG(id): return "Board image \(id) is not a supported PNG."
            }
        }
    }

    private enum ReadFailure: Error { case notRegular, tooLarge }

    static func prepare(sourceURL: URL) throws -> Self {
        try prepare(sourceURL: sourceURL, read: readRegularFile)
    }

    /// The injected reader exists so tests can simulate an outside edit between
    /// the two mandatory source reads without racing the filesystem.
    static func prepare(sourceURL: URL, read: (URL, Int) throws -> Data) throws -> Self {
        let source: Data
        do { source = try read(sourceURL, maximumSourceBytes) }
        catch ReadFailure.tooLarge { throw Failure.sourceTooLarge }
        catch { throw Failure.sourceNotRegular }

        do { _ = try PreservedJSON(source) }
        catch { throw Failure.malformedSource }

        let decoded: ScreenplayOSDocument
        do { decoded = try JSONDecoder.screenplayOSDecoder().decode(ScreenplayOSDocument.self, from: source) }
        catch { throw Failure.malformedSource }
        let dropped = LegacyRoundTrip.droppedPaths(original: source, document: decoded)
        guard dropped.isEmpty else { throw Failure.sourceWouldLoseFields(dropped) }

        var media: [BoardMedia] = []
        var attachments: [String: Attachment] = [:]
        for board in decoded.boardFrames {
            let ids = Set(board.imageVersions.map(\.id))
            if let selected = board.selectedImageID, !ids.contains(selected) {
                throw Failure.selectedImageMissing(board.id)
            }
            var versions: [ImageVersion] = []
            for version in board.imageVersions {
                guard version.sha256.count == 64,
                      version.sha256.allSatisfy({ $0.isASCII && ($0.isNumber || ("a"..."f").contains(String($0))) }) else {
                    throw Failure.invalidImageDigest(version.id)
                }
                let imageURL = try resolve(version.fileURL, beside: sourceURL, id: version.id)
                let bytes: Data
                do { bytes = try read(imageURL, maximumImageBytes) }
                catch ReadFailure.tooLarge { throw Failure.imageTooLarge(version.id) }
                catch { throw Failure.imageNotRegular(version.id) }
                let digest = sha256(bytes)
                guard digest == version.sha256 else { throw Failure.imageDigestMismatch(version.id) }
                let dimensions = try pngDimensions(bytes, id: version.id)
                let path = "attachments/boards/\(digest).png"
                if let prior = attachments[path], prior.bytes != bytes { throw Failure.imageDigestMismatch(version.id) }
                attachments[path] = attachments[path] ?? Attachment(sourceURL: imageURL, sha256: digest, bytes: bytes)
                versions.append(ImageVersion(
                    id: version.id, attachmentPath: path, sha256: digest, byteCount: bytes.count,
                    width: dimensions.width, height: dimensions.height, prompt: version.prompt, model: version.model
                ))
            }
            if !versions.isEmpty {
                media.append(BoardMedia(boardID: board.id, shotID: board.shotID,
                                        selectedVersionID: board.selectedImageID, versions: versions))
            }
        }

        let reread: Data
        do { reread = try read(sourceURL, maximumSourceBytes) }
        catch { throw Failure.sourceChanged }
        guard reread == source else { throw Failure.sourceChanged }
        return Self(sourceURL: sourceURL, sourceBytes: source, sourceSHA256: sha256(source),
                    document: decoded, media: media, attachments: attachments)
    }

    private static func resolve(_ reference: URL, beside source: URL, id: UUID) throws -> URL {
        guard reference.query == nil, reference.fragment == nil else { throw Failure.invalidImageURL(id) }
        if reference.scheme == nil {
            let parts = reference.path.split(separator: "/", omittingEmptySubsequences: false)
            guard parts.count == 2, parts[0] == "Board Images", !parts[1].isEmpty,
                  parts[1] != ".", parts[1] != ".." else { throw Failure.invalidImageURL(id) }
            return source.deletingLastPathComponent().appendingPathComponent(reference.path).standardizedFileURL
        }
        guard reference.isFileURL, reference.host == nil || reference.host == "" || reference.host == "localhost" else {
            throw Failure.invalidImageURL(id)
        }
        return reference.standardizedFileURL
    }

    private static func pngDimensions(_ data: Data, id: UUID) throws -> (width: Int, height: Int) {
        let signature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
        guard data.count >= 24, data.prefix(8).elementsEqual(signature),
              data[12..<16].elementsEqual([73, 72, 68, 82]) else { throw Failure.invalidPNG(id) }
        let width = data[16..<20].reduce(0) { ($0 << 8) | Int($1) }
        let height = data[20..<24].reduce(0) { ($0 << 8) | Int($1) }
        guard (1...32768).contains(width), (1...32768).contains(height) else { throw Failure.invalidPNG(id) }
        return (width, height)
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func readRegularFile(_ url: URL, maximumBytes: Int) throws -> Data {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else {
            if errno == ELOOP { throw ReadFailure.notRegular }
            throw CocoaError(.fileReadNoSuchFile)
        }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { throw ReadFailure.notRegular }
        guard info.st_size <= maximumBytes else { throw ReadFailure.tooLarge }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let allowed = min(buffer.count, maximumBytes - data.count + 1)
            let count = Darwin.read(descriptor, &buffer, allowed)
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                throw CocoaError(.fileReadUnknown)
            }
            data.append(buffer, count: count)
            guard data.count <= maximumBytes else { throw ReadFailure.tooLarge }
        }
        return data
    }
}
