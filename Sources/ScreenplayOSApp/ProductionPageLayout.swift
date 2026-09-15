import Foundation
import ScreenplayDomain

/// Applies frozen page starts to a revised print stream. The source document is never rewritten.
enum ProductionPageLayout {
    static func suffix(_ number: Int) -> String {
        var value = number
        var result = ""
        while value > 0 {
            value -= 1
            result = String(UnicodeScalar(65 + value % 26)!) + result
            value /= 26
        }
        return result
    }

    static func mappedStarts(_ lock: ProductionPageLock, text: String) -> [Int] {
        let old = Array(lock.text)
        let new = Array(text)
        var removed = Set<Int>()
        var inserted = Set<Int>()
        for change in new.difference(from: old) {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        var mapping = [Int](repeating: 0, count: old.count + 1)
        var next = 0
        var replacementStart: Int?
        for offset in 0...old.count {
            // New text immediately before an anchor belongs to the preceding locked page.
            let insertionStart = next
            while next < new.count && inserted.contains(next) { next += 1 }
            if removed.contains(offset) {
                // Replacing the first word of a locked page must keep its replacement on that page.
                if replacementStart == nil { replacementStart = insertionStart }
                mapping[offset] = replacementStart!
            } else {
                replacementStart = nil
                mapping[offset] = next
                if offset < old.count { next += 1 }
            }
        }
        return lock.pageStarts.enumerated().map { index, value in
            index == 0 ? 0 : mapping[min(max(0, value), old.count)]
        }
    }

    /// Surviving paragraph IDs partition the diff so repeated text in a different
    /// paragraph cannot steal an anchor. Diffing between those IDs still lets a
    /// frozen boundary follow text through a split or merge.
    static func mappedStarts(_ lock: ProductionPageLock, source: [ScreenplayElement]) -> [Int] {
        let text = source.map(\.text).joined(separator: "\n")
        guard let baseline = lock.elements,
              baseline.map(\.text).joined(separator: "\n") == lock.text else {
            return mappedStarts(lock, text: text)
        }
        let old = Array(lock.text)
        let new = Array(text)
        var current: [UUID: Int] = [:]
        var position = 0
        for element in source {
            current[element.id] = position
            position += element.text.count + 1
        }
        var anchors: [(old: Int, new: Int)] = []
        position = 0
        for element in baseline {
            if let destination = current[element.id],
               anchors.last.map({ destination > $0.new }) ?? true {
                anchors.append((position, destination))
            }
            position += element.text.count + 1
        }
        if anchors.first?.old != 0 { anchors.insert((0, 0), at: 0) }
        anchors.append((old.count, new.count))
        var previous = 0
        return lock.pageStarts.enumerated().map { index, raw in
            guard index > 0 else { return 0 }
            let offset = min(max(raw, 0), old.count)
            let segment = anchors.lastIndex(where: { $0.old <= offset }) ?? 0
            let start = anchors[segment]
            let mapped: Int
            if offset == start.old || segment + 1 == anchors.count {
                mapped = start.new
            } else {
                let end = anchors[segment + 1]
                let local = ProductionPageLock(
                    text: String(old[start.old..<end.old]),
                    pageStarts: [0, offset - start.old])
                mapped = start.new + mappedStarts(local, text: String(new[start.new..<end.new]))[1]
            }
            // Reordering paragraphs must never produce backwards print boundaries.
            previous = min(new.count, max(previous, mapped))
            return previous
        }
    }

    static func elements(_ source: [ScreenplayElement], lock: ProductionPageLock) -> [ScreenplayElement] {
        let boundaries = mappedStarts(lock, source: source)
        var result = [ScreenplayElement(type: .pageBreak, text: "", externalIDs: ["screenplayos.lockStart": "1"])]
        var boundaryIndex = 1
        var position = 0
        func boundary() {
            result.append(ScreenplayElement(type: .pageBreak, text: "", externalIDs: ["screenplayos.lockBoundary": String(boundaryIndex + 1)]))
            boundaryIndex += 1
        }
        for element in source {
            let characters = Array(element.text)
            let end = position + characters.count
            var start = 0
            func fragment(to offset: Int) {
                guard offset > start else { return }
                var part = element
                let scalarStart = String(characters[..<start]).unicodeScalars.count
                let scalarLength = String(characters[start..<offset]).unicodeScalars.count
                if let tail = try? element.styledText.split(at: scalarStart).1,
                   let segment = try? tail.split(at: scalarLength).0 { part.setStyledText(segment) }
                part.externalIDs["screenplayos.printFragment"] = start == 0 ? "first" : "continued"
                result.append(part)
                start = offset
            }
            while boundaryIndex < boundaries.count && boundaries[boundaryIndex] <= end {
                fragment(to: min(characters.count, max(0, boundaries[boundaryIndex] - position)))
                boundary()
            }
            fragment(to: characters.count)
            if characters.isEmpty { result.append(element) }
            position = end + 1
        }
        while boundaryIndex < boundaries.count { boundary() }
        // A source break coincident with a frozen boundary must not create an extra page.
        return result.enumerated().compactMap { index, element in
            guard element.type == .pageBreak,
                  element.externalIDs["screenplayos.lockBoundary"] == nil,
                  element.externalIDs["screenplayos.lockStart"] == nil else { return element }
            var adjacent = index - 1
            while adjacent >= 0 && result[adjacent].type == .pageBreak {
                if result[adjacent].externalIDs["screenplayos.lockBoundary"] != nil { return nil }
                adjacent -= 1
            }
            adjacent = index + 1
            while adjacent < result.count && result[adjacent].type == .pageBreak {
                if result[adjacent].externalIDs["screenplayos.lockBoundary"] != nil { return nil }
                adjacent += 1
            }
            return element
        }
    }
}
