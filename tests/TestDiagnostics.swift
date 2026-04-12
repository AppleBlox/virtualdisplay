import XCTest
import Cocoa

class TestDiagnostics: XCTestCase {

    func testNoExternalMonitors() {
        let mainID = CGMainDisplayID()
        let warnings = runDiagnostics(physicalDisplayID: mainID)
        XCTAssertNotNil(warnings)
    }

    func testWarningCodesAreValid() {
        let w = DiagnosticWarning(code: "TEST", message: "test message")
        XCTAssertFalse(w.code.isEmpty)
        XCTAssertFalse(w.message.isEmpty)
    }
}
