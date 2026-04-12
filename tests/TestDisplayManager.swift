import XCTest
import Cocoa

class TestVirtualDisplayCreation: XCTestCase {

    func testCreateVirtualDisplay() {
        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.setDispatchQueue(.main)
        descriptor.name = "Test Display"
        descriptor.maxPixelsWide = 1920
        descriptor.maxPixelsHigh = 1080
        descriptor.sizeInMillimeters = CGSize(width: 527, height: 296)
        descriptor.productID = 0xFFFF
        descriptor.vendorID = 0xFFFF
        descriptor.serialNum = 0x9999

        let display = CGVirtualDisplay(descriptor: descriptor)
        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = 0
        settings.modes = [
            CGVirtualDisplayMode(width: 1920, height: 1080, refreshRate: 240),
        ]
        display.apply(settings)

        XCTAssertNotEqual(display.displayID, 0, "Virtual display should have a valid ID")

        var count: CGDisplayCount = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        var found = ids.contains(display.displayID)
        if !found {
            Thread.sleep(forTimeInterval: 1.0)
            CGGetActiveDisplayList(0, nil, &count)
            ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
            CGGetActiveDisplayList(count, &ids, &count)
            found = ids.contains(display.displayID)
        }
        XCTAssertTrue(found, "Virtual display should appear in active display list")
    }

    func testCustomRefreshRate() {
        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.setDispatchQueue(.main)
        descriptor.name = "Test 360Hz"
        descriptor.maxPixelsWide = 1920
        descriptor.maxPixelsHigh = 1080
        descriptor.sizeInMillimeters = CGSize(width: 527, height: 296)
        descriptor.productID = 0xFFFE
        descriptor.vendorID = 0xFFFE
        descriptor.serialNum = 0x9998

        let display = CGVirtualDisplay(descriptor: descriptor)
        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = 0
        settings.modes = [
            CGVirtualDisplayMode(width: 1920, height: 1080, refreshRate: 360),
        ]
        display.apply(settings)

        XCTAssertNotEqual(display.displayID, 0)
    }
}
