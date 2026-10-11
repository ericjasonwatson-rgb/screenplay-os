import Foundation
import Testing
@testable import ScreenplayOSApp

@Suite("Generation job UI boundaries")
struct GenerationJobUITests {
    @Test func offlineStorageIsProjectBound() throws {
        let projectID = UUID(uuidString: "71000000-0000-0000-0000-000000000001")!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("generation-ui-test")
        let url = try OfflineGenerationWorkflow.storageURL(projectID: projectID, root: root)
        #expect(url.path.hasPrefix(root.path + "/"))
        #expect(url.path.contains(projectID.uuidString))
        #expect(url.lastPathComponent == "generation-jobs-v1.json")
    }
}
