import XCTest
import Cocoa

class TestResolveDisplay: XCTestCase {

    func testRetinaDefaults() {
        let metrics = DisplayMetrics(
            pixelWidth: 2880, pixelHeight: 1800,
            scaleFactor: 2.0,
            physicalSizeMM: CGSize(width: 344, height: 215)
        )
        let r = resolveDisplay(metrics: metrics, customWidth: nil, customHeight: nil)
        XCTAssertEqual(r.width, 1440)
        XCTAssertEqual(r.height, 900)
        XCTAssertEqual(r.maxPixelsWide, 2880)
        XCTAssertEqual(r.maxPixelsHigh, 1800)
        XCTAssertTrue(r.hiDPI)
    }

    func testNonRetinaDefaults() {
        let metrics = DisplayMetrics(
            pixelWidth: 1920, pixelHeight: 1080,
            scaleFactor: 1.0,
            physicalSizeMM: CGSize(width: 527, height: 296)
        )
        let r = resolveDisplay(metrics: metrics, customWidth: nil, customHeight: nil)
        XCTAssertEqual(r.width, 1920)
        XCTAssertEqual(r.height, 1080)
        XCTAssertEqual(r.maxPixelsWide, 1920)
        XCTAssertEqual(r.maxPixelsHigh, 1080)
        XCTAssertFalse(r.hiDPI)
    }

    func testScaledRetinaUsesNativePixels() {
        let metrics = DisplayMetrics(
            pixelWidth: 2880, pixelHeight: 1800,
            scaleFactor: 2.0,
            physicalSizeMM: CGSize(width: 344, height: 215)
        )
        let r = resolveDisplay(metrics: metrics, customWidth: nil, customHeight: nil)
        XCTAssertEqual(r.maxPixelsWide, 2880)
        XCTAssertEqual(r.maxPixelsHigh, 1800)
    }

    func testCustomWidthOnly() {
        let metrics = DisplayMetrics(
            pixelWidth: 2880, pixelHeight: 1800,
            scaleFactor: 2.0,
            physicalSizeMM: CGSize(width: 344, height: 215)
        )
        let r = resolveDisplay(metrics: metrics, customWidth: 1024, customHeight: nil)
        XCTAssertEqual(r.width, 1024)
        XCTAssertEqual(r.height, 1800)
        XCTAssertFalse(r.hiDPI)
    }

    func testCustomBoth() {
        let metrics = DisplayMetrics(
            pixelWidth: 2880, pixelHeight: 1800,
            scaleFactor: 2.0,
            physicalSizeMM: CGSize(width: 344, height: 215)
        )
        let r = resolveDisplay(metrics: metrics, customWidth: 1024, customHeight: 768)
        XCTAssertEqual(r.width, 1024)
        XCTAssertEqual(r.height, 768)
        XCTAssertEqual(r.maxPixelsWide, 1024)
        XCTAssertEqual(r.maxPixelsHigh, 768)
        XCTAssertFalse(r.hiDPI)
    }

    func testMSeriesRetina() {
        let metrics = DisplayMetrics(
            pixelWidth: 3024, pixelHeight: 1964,
            scaleFactor: 2.0,
            physicalSizeMM: CGSize(width: 345, height: 224)
        )
        let r = resolveDisplay(metrics: metrics, customWidth: nil, customHeight: nil)
        XCTAssertEqual(r.width, 1512)
        XCTAssertEqual(r.height, 982)
        XCTAssertEqual(r.maxPixelsWide, 3024)
        XCTAssertEqual(r.maxPixelsHigh, 1964)
        XCTAssertTrue(r.hiDPI)
    }
}

// Minimal test runner
@main
struct TestRunner {
    static func main() {
        let classes: [XCTestCase.Type] = [
            TestResolveDisplay.self,
            TestDiagnostics.self,
            TestVirtualDisplayCreation.self,
        ]
        var totalTests = 0
        var totalFailures = 0
        var totalExceptions = 0
        for cls in classes {
            let suite = XCTestSuite(forTestCaseClass: cls)
            suite.run()
            let run = suite.testRun!
            totalTests += run.testCaseCount
            totalFailures += run.failureCount
            totalExceptions += run.unexpectedExceptionCount
        }
        print("\(totalTests) tests, \(totalFailures) failures, \(totalExceptions) exceptions")
        if totalFailures > 0 || totalExceptions > 0 {
            exit(1)
        }
    }
}
