import Foundation

/// Read-only line-break opportunities measured from print fragments. Restrict only
/// split dialogue paragraphs; all other text keeps normal TextKit wrapping.
struct NativeLineBreaks: Equatable {
    let starts: Set<Int>
    let paragraphs: [NSRange]

    func allows(_ offset: Int) -> Bool {
        !paragraphs.contains(where: { NSLocationInRange(offset, $0) }) || starts.contains(offset)
    }
}
