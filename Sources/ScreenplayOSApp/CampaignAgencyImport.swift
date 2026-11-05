import Foundation
import Darwin
import ScreenplayDomain

/// A bounded local text reader. It neither extracts PDF/Office content nor
/// retains the source path. The exact selected bytes are previewed before import.
enum CampaignAgencyImport {
    struct Preview {
        let filename: String
        let bytes: Data
        let text: String
    }

    static func read(_ url: URL) throws -> Preview {
        guard url.isFileURL, ["txt", "md", "fountain"].contains(url.pathExtension.lowercased()) else {
            throw CampaignError.invalid("Choose a UTF-8 .txt, .md or .fountain file. PDF, Word, images and OCR are not supported; export the relevant text first and verify it against the original.")
        }
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw CampaignError.invalid("The selected text file could not be opened safely.") }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_size > 0, info.st_size <= CampaignAgencyWorkspace.maximumSourceBytes else {
            throw CampaignError.invalid("Choose a regular, nonempty text file no larger than 256 KiB.")
        }
        // Read at most one byte beyond the limit, including if the file grows
        // after fstat. A replaced pathname cannot redirect this open descriptor.
        var bytes = Data()
        var buffer = [UInt8](repeating: 0, count: 8_192)
        while bytes.count <= CampaignAgencyWorkspace.maximumSourceBytes {
            let count = Darwin.read(fd, &buffer, min(buffer.count, CampaignAgencyWorkspace.maximumSourceBytes + 1 - bytes.count))
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw CampaignError.invalid("The selected text file could not be read.") }
            if count == 0 { break }
            bytes.append(contentsOf: buffer.prefix(count))
        }
        var after = stat()
        guard fstat(fd, &after) == 0, info.st_size == after.st_size,
              info.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              info.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              info.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec,
              info.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec else {
            throw CampaignError.invalid("The source changed while it was being read. Choose it again after saving the source file.")
        }
        let text = String(decoding: bytes, as: UTF8.self)
        guard !bytes.isEmpty, bytes.count <= CampaignAgencyWorkspace.maximumSourceBytes,
              Data(text.utf8) == bytes, !text.unicodeScalars.contains(where: { $0.value == 0 }) else {
            throw CampaignError.invalid("The selected file must be nonempty UTF-8 text no larger than 256 KiB.")
        }
        return Preview(filename: url.lastPathComponent, bytes: bytes, text: text)
    }
}
