import Foundation
import ScreenplayDomain
import ScreenplayFDX

let arguments = CommandLine.arguments.dropFirst()

guard let inputPath = arguments.first else {
    FileHandle.standardError.write(Data("Usage: screenplay-inspect <file.fdx> [--json]\n".utf8))
    exit(64)
}

let emitJSON = arguments.contains("--json")
do {
    let importer = FDXImporter()
    let result = try importer.importFile(at: URL(fileURLWithPath: inputPath))
    let document = result.document

    if emitJSON {
        let data = try JSONEncoder.openScreenplayEncoder().encode(document)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    } else {
        let elements = document.screenplay.elements
        let scenes = elements.filter { $0.type == .sceneHeading }
        let characters = Set(elements.filter { $0.type == .character }.map(\.text)).sorted()

        print("Open Screenplay inspection")
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

        if !result.warnings.isEmpty {
            print("Warnings:")
            for warning in result.warnings {
                print("- \(warning)")
            }
        }
    }
} catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    exit(1)
}
