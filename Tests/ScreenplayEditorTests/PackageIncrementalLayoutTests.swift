import AppKit
import Testing
import ScreenplayDomain
@testable import ScreenplayOSApp

@Suite("Incremental package pagination", .serialized) @MainActor
struct PackageIncrementalLayoutTests {
    @Test func reusedPagesMatchFreshLayoutAcrossEdits() async throws {
        let f = PackageTextSessionTests()
        var session = try PackageTextSession(files: f.fixture())
        for p in session.paragraphs { try session.delete(elementID: p.id, expectedRevision: session.revision) }
        for i in 0..<35 {
            _ = try session.insert(after: session.paragraphs.last?.id, expectedRevision: session.revision,
                type: i % 3 == 0 ? "character" : "dialogue", text: i % 3 == 0 ? "ALEX" : String(repeating: "The room stays quiet. ", count: 14))
        }
        var reused = try PackagePrintLayout.plan(session)
        func verify(_ fresh: PackagePrintLayout.Plan, _ cached: PackagePrintLayout.Plan) {
            #expect(cached.ranges == fresh.ranges)
            #expect(cached.headers == fresh.headers && cached.footers == fresh.footers)
            #expect(cached.headerHeights == fresh.headerHeights)
            for page in fresh.ranges.indices {
                var a: [NSRect] = [], b: [NSRect] = []
                fresh.layout.enumerateLineFragments(forGlyphRange: fresh.glyphRanges[page]) { r, _, _, _, _ in a.append(r) }
                cached.layout.enumerateLineFragments(forGlyphRange: cached.glyphRanges[page]) { r, _, _, _, _ in b.append(r) }
                #expect(a == b)
            }
        }
        for (iteration, position) in [34, 17, 0, 34].enumerated() {
            let id = session.paragraphs[position].id
            let old = try session.text(for: id)
            try session.replaceText(elementID: id, expectedRevision: session.revision, expectedText: old, replacement: old + " 👩🏽‍🚀 café")
            reused = try PackagePrintLayout.plan(session, reusing: reused)
            if iteration == 0 { #expect(reused.relayoutStart > 0) }
            verify(try PackagePrintLayout.plan(session), reused)
            await Task.yield()
        }
        let id = session.paragraphs.last!.id
        try session.format(elementID: id, expectedRevision: session.revision, range: 0..<4, patch: .init(bold: true))
        reused = try PackagePrintLayout.plan(session, reusing: reused)
        verify(try PackagePrintLayout.plan(session), reused)
        try session.setTypography(try .init(fontSize: 16), expectedRevision: session.revision)
        reused = try PackagePrintLayout.plan(session, reusing: reused)
        #expect(reused.relayoutStart == 0)
        verify(try PackagePrintLayout.plan(session), reused)
        session.undo()
        reused = try PackagePrintLayout.plan(session, reusing: reused)
        verify(try PackagePrintLayout.plan(session), reused)
        try session.delete(elementID: id, expectedRevision: session.revision)
        reused = try PackagePrintLayout.plan(session, reusing: reused)
        verify(try PackagePrintLayout.plan(session), reused)
    }
}
