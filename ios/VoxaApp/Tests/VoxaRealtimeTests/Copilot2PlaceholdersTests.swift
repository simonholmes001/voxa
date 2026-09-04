import XCTest
@testable import VoxaRealtime

final class Copilot2PlaceholdersTests: XCTestCase {
    func test_placeholder_plan_files_exist() {
        // Basic guard that the test-plan files were created in the worktree.
        let fm = FileManager.default
        let base = FileManager.default.currentDirectoryPath
        let paths = [
            "ios/VoxaApp/Tests/COPILOT2_HOME_RESUME_PLAN.md",
            "ios/VoxaApp/Tests/COPILOT2_TALK_UX_PLAN.md",
            "ios/VoxaApp/Tests/COPILOT2_PLACEHOLDERS_PLAN.md",
        ]
        for p in paths {
            let full = base + "/.worktrees/feature/mvp-acceleration-copilot2/" + p
            XCTAssertTrue(fm.fileExists(atPath: full), "Missing plan file: \(full)")
        }
    }
}
