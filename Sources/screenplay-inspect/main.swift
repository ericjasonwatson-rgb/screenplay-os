import Foundation
import ScreenplayDomain
import ScreenplayFDX

let arguments = CommandLine.arguments.dropFirst()

guard let inputPath = arguments.first else {
    FileHandle.standardError.write(Data("Usage: screenplay-inspect <file.fdx|file.json> [--json]\n".utf8))
    exit(64)
}

let emitJSON = arguments.contains("--json")
do {
    let url = URL(fileURLWithPath: inputPath)
    let document: ScreenplayOSDocument
    let warnings: [String]
    if url.pathExtension.lowercased() == "fdx" {
        let result = try FDXImporter().importFile(at: url)
        document = result.document
        warnings = result.warnings
    } else {
        document = try JSONDecoder.screenplayOSDecoder().decode(ScreenplayOSDocument.self, from: Data(contentsOf: url))
        warnings = []
    }

    if emitJSON {
        let data = try JSONEncoder.screenplayOSEncoder().encode(document)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    } else {
        let elements = document.screenplay.elements
        let scenes = elements.filter { $0.type == .sceneHeading }
        let characters = Set(elements.filter { $0.type == .character }.map(\.text)).sorted()

        print("ScreenplayOS document inspection")
        print("Title: \(document.project.metadata.title)")
        print("Elements: \(elements.count)")
        print("Scenes: \(scenes.count)")
        print("Characters: \(characters.count)")

        if !characters.isEmpty {
            print("Character index:")
            for character in characters.prefix(20) {
                print("- \(character)")
            }
        }

        if !warnings.isEmpty {
            print("Warnings:")
            for warning in warnings {
                print("- \(warning)")
            }
        }
    }
} catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    exit(1)
}
