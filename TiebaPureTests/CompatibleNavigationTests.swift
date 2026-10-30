import XCTest
@testable import TiebaPure

final class CompatibleNavigationTests: XCTestCase {
    func testPoppingAtTheCurrentDepthKeepsThePath() {
        let path = ["home", "forum", "thread"]

        XCTAssertEqual(
            CompatibleNavigationPathPolicy.popping(path, toDepth: 3),
            ["home", "forum", "thread"]
        )
    }

    func testPoppingFromDeeperLevelsTruncatesToTheRequestedDepth() {
        let path = ["home", "forum", "thread", "user"]

        XCTAssertEqual(
            CompatibleNavigationPathPolicy.popping(path, toDepth: 1),
            ["home"]
        )
        XCTAssertEqual(
            CompatibleNavigationPathPolicy.popping(path, toDepth: 0),
            []
        )
    }

    func testPoppingPastTheEndIsIgnoredSoStaleLinksCannotRemoveALevel() {
        let path = ["home", "forum"]

        XCTAssertEqual(
            CompatibleNavigationPathPolicy.popping(path, toDepth: 5),
            ["home", "forum"]
        )
        XCTAssertEqual(
            CompatibleNavigationPathPolicy.popping(path, toDepth: -1),
            ["home", "forum"]
        )
    }

    func testTaskDelayConversionRoundsToNanoseconds() {
        XCTAssertEqual(CompatibleTaskDelay.nanoseconds(for: 0.25), 250_000_000)
        XCTAssertEqual(CompatibleTaskDelay.nanoseconds(for: 1.5), 1_500_000_000)
        XCTAssertEqual(CompatibleTaskDelay.nanoseconds(for: 0.35), 350_000_000)
    }

    func testTaskDelayConversionClampsNonPositiveAndNonFiniteIntervals() {
        XCTAssertEqual(CompatibleTaskDelay.nanoseconds(for: 0), 0)
        XCTAssertEqual(CompatibleTaskDelay.nanoseconds(for: -1), 0)
        XCTAssertEqual(CompatibleTaskDelay.nanoseconds(for: .infinity), 0)
        XCTAssertEqual(CompatibleTaskDelay.nanoseconds(for: .nan), 0)
    }
}
