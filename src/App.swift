import Cocoa
import ColorSync

class AppDelegate: NSObject, NSApplicationDelegate {
    private let showMenu: Bool
    private let customWidth: Int?
    private let customHeight: Int?
    private let refreshRate: Double
    private var virtualDisplay: CGVirtualDisplay?
    private var statusItem: NSStatusItem?
    private var nativeMode: CGDisplayMode?
    private var physicalDisplayID: CGDirectDisplayID = 0
    private var signalSources: [DispatchSourceSignal] = []
    private var isStopping = false
    private var pollTimer: Timer?
    private var colorProfileTmpURL: URL?

    init(showMenu: Bool, width: Int? = nil, height: Int? = nil, hz: Double = 240.0) {
        self.showMenu = showMenu
        self.customWidth = width
        self.customHeight = height
        self.refreshRate = hz
    }

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.accessory)
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler { [weak self] in self?.stop() }
            src.resume()
            signalSources.append(src)
        }
        setupVirtualDisplay()
        if showMenu { setupStatusBar() }
    }

    private func setupVirtualDisplay() {
        // Prefer the built-in display so external monitors are not affected.
        var count: CGDisplayCount = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        physicalDisplayID = ids.first(where: { CGDisplayIsBuiltin($0) != 0 }) ?? CGMainDisplayID()

        guard let screen = NSScreen.screens.first(where: { $0.displayID == physicalDisplayID }) ?? NSScreen.main else { return }

        let scale = screen.backingScaleFactor
        let currentMode = CGDisplayCopyDisplayMode(physicalDisplayID)
        let physicalW = currentMode?.pixelWidth  ?? CGDisplayPixelsWide(physicalDisplayID)
        let physicalH = currentMode?.pixelHeight ?? CGDisplayPixelsHigh(physicalDisplayID)

        let isCustom = customWidth != nil || customHeight != nil
        // Divide physical pixels by scale to get HiDPI logical dimensions that render
        // at exactly the panel's native pixel count, regardless of the user's chosen
        // "looks like" scaled resolution.
        let w = customWidth  ?? Int((Double(physicalW) / scale).rounded())
        let h = customHeight ?? Int((Double(physicalH) / scale).rounded())

        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.setDispatchQueue(.main)
        descriptor.name = "Virtual 240Hz"
        descriptor.maxPixelsWide = UInt32(isCustom ? w : physicalW)
        descriptor.maxPixelsHigh = UInt32(isCustom ? h : physicalH)
        descriptor.sizeInMillimeters = screen.physicalSizeInMillimeters
        descriptor.productID = 0x1234
        descriptor.vendorID = 0x3456
        descriptor.serialNum = 0x0002
        descriptor.terminationHandler = { [weak self] _, _ in self?.virtualDisplay = nil }

        let display = CGVirtualDisplay(descriptor: descriptor)
        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = (!isCustom && scale > 1) ? 1 : 0
        settings.modes = [
            CGVirtualDisplayMode(width: UInt(w), height: UInt(h), refreshRate: refreshRate),
            CGVirtualDisplayMode(width: UInt(w), height: UInt(h), refreshRate: 60),
        ]
        display.apply(settings)
        virtualDisplay = display

        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.pollForMirroring()
        }
    }

    private func pollForMirroring() {
        guard let vd = virtualDisplay else { pollTimer?.invalidate(); return }
        var count: CGDisplayCount = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        guard ids.contains(vd.displayID) else { return }
        pollTimer?.invalidate()
        pollTimer = nil
        applyColorProfile(to: vd.displayID)
        enableMirroring()
    }

    // Copy the physical display's ICC profile to the virtual display so apps
    // running on it use the correct color space.
    private func applyColorProfile(to virtualID: CGDirectDisplayID) {
        guard
            let screen = NSScreen.screens.first(where: { $0.displayID == physicalDisplayID }),
            let iccData = screen.colorSpace?.iccProfileData
        else { return }
        let uuid = CGDisplayCreateUUIDFromDisplayID(virtualID).takeRetainedValue()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("virtualdisplay-\(virtualID).icc")
        guard (try? iccData.write(to: url)) != nil else { return }
        colorProfileTmpURL = url

        ColorSyncDeviceSetCustomProfiles(
            "mntr" as CFString,
            uuid,
            ["DeviceDefaultProfile": url] as CFDictionary
        )
    }

    private func enableMirroring() {
        guard let vd = virtualDisplay else { return }
        nativeMode = CGDisplayCopyDisplayMode(physicalDisplayID)
        if CGDisplayIsInMirrorSet(physicalDisplayID) != 0 {
            var cfg: CGDisplayConfigRef?
            CGBeginDisplayConfiguration(&cfg)
            CGConfigureDisplayMirrorOfDisplay(cfg, physicalDisplayID, kCGNullDirectDisplay)
            CGCompleteDisplayConfiguration(cfg, CGConfigureOption(rawValue: 0))
        }
        var cfg: CGDisplayConfigRef?
        CGBeginDisplayConfiguration(&cfg)
        CGConfigureDisplayMirrorOfDisplay(cfg, physicalDisplayID, vd.displayID)
        CGCompleteDisplayConfiguration(cfg, CGConfigureOption(rawValue: 0))
    }

    private func disableMirroring() {
        guard CGDisplayIsInMirrorSet(physicalDisplayID) != 0 else { return }
        var cfg: CGDisplayConfigRef?
        CGBeginDisplayConfiguration(&cfg)
        CGConfigureDisplayMirrorOfDisplay(cfg, physicalDisplayID, kCGNullDirectDisplay)
        if let mode = nativeMode {
            CGConfigureDisplayWithDisplayMode(cfg, physicalDisplayID, mode, nil)
        }
        CGCompleteDisplayConfiguration(cfg, CGConfigureOption(rawValue: 0))
        nativeMode = nil
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "display", accessibilityDescription: nil)
        let menu = NSMenu()
        menu.addItem(withTitle: "Virtual \(Int(refreshRate))Hz Display", action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(.separator())
        menu.addItem(withTitle: "Stop", action: #selector(stop), keyEquivalent: "q")
        statusItem?.menu = menu
    }

    @objc func stop() {
        guard !isStopping else { return }
        isStopping = true
        pollTimer?.invalidate()
        pollTimer = nil
        disableMirroring()
        virtualDisplay = nil
        if let url = colorProfileTmpURL {
            try? FileManager.default.removeItem(at: url)
        }
        NSApp.terminate(nil)
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID {
        deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as! CGDirectDisplayID
    }

    var physicalSizeInMillimeters: CGSize {
        guard let dpi = deviceDescription[NSDeviceDescriptionKey("NSDeviceResolution")] as? NSValue else {
            return CGSize(width: 600, height: 340)
        }
        let d = dpi.sizeValue
        guard d.width > 0, d.height > 0 else { return CGSize(width: 600, height: 340) }
        return CGSize(width: frame.width / d.width * 25.4, height: frame.height / d.height * 25.4)
    }
}
