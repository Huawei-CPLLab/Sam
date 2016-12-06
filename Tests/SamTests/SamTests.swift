import XCTest
@testable import Sam

class SamTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        XCTAssertEqual(Sam().text, "Hello, World!")
    }


    static var allTests : [(String, (SamTests) -> () throws -> Void)] {
        return [
            ("testExample", testExample),
        ]
    }
}
