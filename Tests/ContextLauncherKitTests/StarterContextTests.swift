import Foundation
import XCTest
@testable import ContextLauncherKit

final class StarterContextTests: XCTestCase {
    func testFirstRunNeedsOnboardingOnlyWithoutStoredContexts() throws {
        let missingFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("StarterContextTests-\(UUID().uuidString)/contexts.json")
        let empty = try ContextStore(fileURL: missingFile).load()

        XCTAssertTrue(OnboardingState.needsOnboarding(contexts: empty))
        XCTAssertFalse(OnboardingState.needsOnboarding(contexts: StarterContexts.all))
    }
}
