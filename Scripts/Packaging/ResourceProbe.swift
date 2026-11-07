// Compiled only by validate-campaign-app.py, never shipped in ScreenplayOS.
// Commerce.swift and SwiftPM's generated accessor are compiled unchanged with it.
import Foundation

@main
struct ResourceProbe {
    static func main() throws {
        // Evaluate the actual production accessor before reading the comparison file.
        let actual = PricingConfiguration.current
        let expectedData = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let expected = try JSONDecoder().decode(PricingConfiguration.self, from: expectedData)
        guard actual == expected else {
            FileHandle.standardError.write(Data("Decoded packaged pricing differs from source.\n".utf8))
            exit(2)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(actual))
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
