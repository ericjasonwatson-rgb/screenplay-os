import Foundation
import Darwin
import ScreenplayDomain

/// A bounded local reader. Original document bytes and exact extracted text are
/// previewed before import. No source directory path is retained.
enum CampaignAgencyImport {
    private static let importLock = NSLock()
    struct Preview {
        let filename: String
        let bytes: Data
        let text: String
        let origin: CampaignAgencyDocumentOrigin?
        init(filename: String, bytes: Data, text: String, origin: CampaignAgencyDocumentOrigin? = nil) {
            self.filename = filename; self.bytes = bytes; self.text = text; self.origin = origin
        }
    }

    static func read(_ url: URL) throws -> Preview {
        try Task.checkCancellation()
        // One synchronous extractor may run app-wide. Cancelled previews cannot
        // accumulate abandoned background readers through repeated picker use.
        guard importLock.try() else {
            throw CampaignError.invalid("Another document is still being read. Wait for it to finish, then choose the source again.")
        }
        defer { importLock.unlock() }
        let extensionName = url.pathExtension.lowercased()
        guard extensionName != "pdf" else {
            throw CampaignError.invalid("PDF import is not enabled until its parser can be isolated safely. Export verified UTF-8 text or a supported DOCX first. No OCR was performed.")
        }
        guard url.isFileURL, ["txt", "md", "fountain", "docx"].contains(extensionName) else {
            throw CampaignError.invalid("Choose UTF-8 text or a supported DOCX. PDF, legacy .doc, images and OCR are not enabled.")
        }
        let isDocument = extensionName == "docx"
        let limit = isDocument ? CampaignAgencyDocumentOrigin.maximumOriginalBytes : CampaignAgencyWorkspace.maximumSourceBytes
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw CampaignError.invalid("The selected text file could not be opened safely.") }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_size > 0, info.st_size <= Int64(limit) else {
            throw CampaignError.invalid("Choose a regular, nonempty file within the import limit (2 MiB for DOCX, 256 KiB for text).")
        }
        // Read at most one byte beyond the limit, including if the file grows
        // after fstat. A replaced pathname cannot redirect this open descriptor.
        var bytes = Data()
        var buffer = [UInt8](repeating: 0, count: 8_192)
        while bytes.count <= limit {
            try Task.checkCancellation()
            let count = Darwin.read(fd, &buffer, min(buffer.count, limit + 1 - bytes.count))
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
        guard !bytes.isEmpty, bytes.count <= limit else {
            throw CampaignError.invalid("The source exceeds its import size limit.")
        }
        try Task.checkCancellation()
        if isDocument {
            let extraction = try CampaignAgencyDocumentExtraction.extract(data: bytes, filename: url.lastPathComponent)
            let origin = try CampaignAgencyDocumentOrigin(format: extraction.formatRawValue, originalBytes: bytes,
                sections: extraction.sections, extractor: extraction.extractor, notices: extraction.notices)
            try Task.checkCancellation()
            return Preview(filename: url.lastPathComponent, bytes: Data(extraction.text.utf8), text: extraction.text, origin: origin)
        }
        let text = String(decoding: bytes, as: UTF8.self)
        guard !bytes.isEmpty, bytes.count <= limit,
              Data(text.utf8) == bytes, !text.unicodeScalars.contains(where: { $0.value == 0 }) else {
            throw CampaignError.invalid("The selected file must be nonempty UTF-8 text no larger than 256 KiB.")
        }
        try Task.checkCancellation()
        return Preview(filename: url.lastPathComponent, bytes: bytes, text: text)
    }
}
